import AVFoundation
import Foundation
import os

// MARK: - CameraService

/// AVFoundation-based camera capture for real-time frame analysis.
/// No video is recorded or stored — frames are forwarded to registered handlers
/// (gesture recognizer, face tracker) and then discarded.
///
/// Mirrors the AudioRecorder pattern: callback-based, thread-safe, with
/// frame-rate throttling to keep CPU usage low (~8 fps analysis).
final class CameraService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    @Published var isRunning: Bool = false

    private var captureSession: AVCaptureSession?
    private let processingQueue = DispatchQueue(label: "com.autoclawd.camera", qos: .userInitiated)
    private var lastProcessedTime: TimeInterval = 0

    /// Minimum interval between processed frames (default ~125ms = 8fps).
    var minFrameInterval: TimeInterval = 0.125

    // Thread-safe callback for forwarding frames (like AudioRecorder.onBuffer)
    private let _onFrame = OSAllocatedUnfairLock<((CMSampleBuffer) -> Void)?>(initialState: nil)

    var onFrame: ((CMSampleBuffer) -> Void)? {
        get { _onFrame.withLock { $0 } }
        set { _onFrame.withLock { $0 = newValue } }
    }

    // MARK: - Start

    func start() throws {
        guard captureSession == nil else { return }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status == .authorized else {
            Log.warn(.camera, "Camera permission not granted (status: \(status.rawValue))")
            return
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
              ?? AVCaptureDevice.default(for: .video)
        else {
            Log.error(.camera, "No camera device available")
            return
        }

        let session = AVCaptureSession()
        session.sessionPreset = .low  // lowest resolution sufficient for Vision analysis

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            Log.error(.camera, "Cannot add camera input to session")
            return
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: processingQueue)
        guard session.canAddOutput(output) else {
            Log.error(.camera, "Cannot add video output to session")
            return
        }
        session.addOutput(output)

        captureSession = session
        processingQueue.async { [weak self] in
            session.startRunning()
            DispatchQueue.main.async {
                self?.isRunning = true
            }
        }
        Log.info(.camera, "Camera started (throttle: \(minFrameInterval)s)")
    }

    // MARK: - Stop

    func stop() {
        guard let session = captureSession else { return }
        processingQueue.async {
            session.stopRunning()
        }
        captureSession = nil
        DispatchQueue.main.async {
            self.isRunning = false
        }
        Log.info(.camera, "Camera stopped")
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Frame-rate throttling — skip frames within minFrameInterval of last processed
        let now = CACurrentMediaTime()
        guard now - lastProcessedTime >= minFrameInterval else { return }
        lastProcessedTime = now

        // Forward to registered handlers (gesture recognizer, face tracker)
        let handler = _onFrame.withLock { $0 }
        handler?(sampleBuffer)
    }
}
