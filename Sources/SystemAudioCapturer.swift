import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

// MARK: - SystemAudioCapturer

/// Captures system audio (and optional low-res screen preview) via ScreenCaptureKit.
/// Follows the same `onBuffer` callback pattern as AudioRecorder for drop-in integration.
final class SystemAudioCapturer: NSObject, ObservableObject, @unchecked Sendable {

    @Published var isCapturing = false
    @Published var audioLevel: Float = 0.0

    /// PCM audio buffers — same pattern as AudioRecorder.onBuffer.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// Low-res screen frames for preview (~2 fps).
    var onFrame: ((CGImage) -> Void)?

    private var stream: SCStream?
    private var streamOutput: SystemAudioStreamOutput?
    private var smoothedLevel: Float = 0.0

    // MARK: - Permission

    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - Start

    func start() async throws {
        guard !isCapturing else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        )
        guard let display = content.displays.first else {
            throw SystemAudioError.noDisplay
        }

        // Filter: capture entire display (all apps)
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true   // avoid feedback loop
        config.channelCount = 1                     // mono for transcription
        config.sampleRate = 48000                   // match common system rate

        // Low-res video for screen preview
        config.width = 320
        config.height = 180
        config.minimumFrameInterval = CMTime(value: 1, timescale: 2) // ~2 fps
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let output = SystemAudioStreamOutput(
            onAudio: { [weak self] buffer in
                self?.onBuffer?(buffer)
                self?.updateLevel(buffer)
            },
            onVideo: { [weak self] image in
                self?.onFrame?(image)
            }
        )
        streamOutput = output

        let scStream = SCStream(filter: filter, configuration: config, delegate: nil)
        try scStream.addStreamOutput(output, type: .audio,
                                     sampleHandlerQueue: .global(qos: .userInteractive))
        try scStream.addStreamOutput(output, type: .screen,
                                     sampleHandlerQueue: .global(qos: .utility))
        try await scStream.startCapture()

        stream = scStream
        await MainActor.run { self.isCapturing = true }
        Log.info(.audio, "SystemAudioCapturer: started (display \(display.displayID))")
    }

    // MARK: - Stop

    func stop() {
        stream?.stopCapture { _ in }
        stream = nil
        streamOutput = nil
        DispatchQueue.main.async {
            self.isCapturing = false
            self.audioLevel = 0.0
        }
        Log.info(.audio, "SystemAudioCapturer: stopped")
    }

    // MARK: - Level Metering

    private func updateLevel(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        var sum: Float = 0
        for i in 0..<frames { sum += ch[0][i] * ch[0][i] }
        let rms = (sum / Float(frames)).squareRoot()
        let scaled = min(rms * 10.0, 1.0)
        let newLevel = rms > smoothedLevel / 10.0
            ? smoothedLevel * 0.3 + scaled * 0.7
            : smoothedLevel * 0.6 + scaled * 0.4
        smoothedLevel = newLevel
        DispatchQueue.main.async { self.audioLevel = newLevel }
    }
}

// MARK: - Stream Output

/// Receives CMSampleBuffers from SCStream and converts audio to AVAudioPCMBuffer.
final class SystemAudioStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let audioHandler: (AVAudioPCMBuffer) -> Void
    private let videoHandler: (CGImage) -> Void

    init(onAudio: @escaping (AVAudioPCMBuffer) -> Void,
         onVideo: @escaping (CGImage) -> Void) {
        self.audioHandler = onAudio
        self.videoHandler = onVideo
    }

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        switch type {
        case .audio:
            guard let pcmBuffer = sampleBuffer.toPCMBuffer() else { return }
            audioHandler(pcmBuffer)
        case .screen:
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
            let context = CIContext()
            let rect = CGRect(x: 0, y: 0,
                              width: CVPixelBufferGetWidth(imageBuffer),
                              height: CVPixelBufferGetHeight(imageBuffer))
            guard let cgImage = context.createCGImage(ciImage, from: rect) else { return }
            videoHandler(cgImage)
        case .microphone:
            break
        @unknown default:
            break
        }
    }
}

// MARK: - CMSampleBuffer → AVAudioPCMBuffer

extension CMSampleBuffer {
    func toPCMBuffer() -> AVAudioPCMBuffer? {
        guard let formatDesc = formatDescription else { return nil }
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }
        guard let format = AVAudioFormat(streamDescription: asbd) else { return nil }
        let frameCount = CMSampleBufferGetNumSamples(self)
        guard frameCount > 0 else { return nil }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        // Copy sample data into the PCM buffer
        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let bufferListSize = MemoryLayout<AudioBufferList>.size

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            self,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: bufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let srcBuf = audioBufferList.mBuffers
        guard let srcData = srcBuf.mData else { return nil }
        let dstList = buffer.mutableAudioBufferList
        let dstBuf = dstList.pointee.mBuffers
        guard let dstData = dstBuf.mData else { return nil }

        let copySize = min(Int(srcBuf.mDataByteSize), Int(dstBuf.mDataByteSize))
        memcpy(dstData, srcData, copySize)

        return buffer
    }
}

// MARK: - SystemAudioMixer

/// Thread-safe audio mixer that stores the latest system audio buffer
/// and mixes it into mic buffers on demand. Not actor-isolated — safe
/// to call from AVAudioEngine tap callbacks on any thread.
final class SystemAudioMixer: @unchecked Sendable {
    private var latestBuffer: AVAudioPCMBuffer?
    private let lock = NSLock()
    private var converter: AVAudioConverter?

    func storeBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        latestBuffer = buffer
        lock.unlock()
    }

    func reset() {
        lock.lock()
        latestBuffer = nil
        converter = nil
        lock.unlock()
    }

    /// Mix stored system audio into the given mic buffer (in-place).
    /// Resamples if formats differ. Clamps to [-1, 1].
    func mix(into micBuffer: AVAudioPCMBuffer) {
        lock.lock()
        guard let sysBuffer = latestBuffer else {
            lock.unlock()
            return
        }
        lock.unlock()

        let micFormat = micBuffer.format
        let sysFormat = sysBuffer.format

        let sourceBuf: AVAudioPCMBuffer
        if sysFormat.sampleRate != micFormat.sampleRate || sysFormat.channelCount != micFormat.channelCount {
            if converter == nil || converter?.inputFormat != sysFormat || converter?.outputFormat != micFormat {
                converter = AVAudioConverter(from: sysFormat, to: micFormat)
            }
            guard let conv = converter else { return }
            let ratio = micFormat.sampleRate / sysFormat.sampleRate
            let outFrames = AVAudioFrameCount(Double(sysBuffer.frameLength) * ratio)
            guard let converted = AVAudioPCMBuffer(pcmFormat: micFormat, frameCapacity: outFrames) else { return }
            do {
                try conv.convert(to: converted, from: sysBuffer)
            } catch {
                return
            }
            sourceBuf = converted
        } else {
            sourceBuf = sysBuffer
        }

        guard let micData = micBuffer.floatChannelData,
              let sysData = sourceBuf.floatChannelData else { return }
        let frames = min(Int(micBuffer.frameLength), Int(sourceBuf.frameLength))
        for i in 0..<frames {
            let mixed = micData[0][i] + sysData[0][i]
            micData[0][i] = max(-1.0, min(1.0, mixed))
        }
    }
}

// MARK: - Error

enum SystemAudioError: LocalizedError {
    case noDisplay
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplay:        return "No display found for audio capture"
        case .permissionDenied: return "Screen Recording permission required"
        }
    }
}
