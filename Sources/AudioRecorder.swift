import AVFoundation
import CoreAudio
import Foundation
import os

// MARK: - AudioDevice

struct AudioDevice: Identifiable {
    let id: AudioDeviceID
    let uid: String
    let name: String

    static func availableInputDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &propertyAddress, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &propertyAddress, 0, nil, &dataSize, &deviceIDs) == noErr
        else { return [] }

        var devices: [AudioDevice] = []
        for deviceID in deviceIDs {
            var inputStreamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &inputStreamAddress, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else { continue }

            let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferListPointer.deallocate() }
            guard AudioObjectGetPropertyData(deviceID, &inputStreamAddress, 0, nil, &streamSize,
                                             bufferListPointer) == noErr else { continue }
            let inputChannels = UnsafeMutableAudioBufferListPointer(bufferListPointer)
                .reduce(0) { $0 + Int($1.mNumberChannels) }
            guard inputChannels > 0 else { continue }

            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uidRef: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uidRef) == noErr,
                  let uid = uidRef?.takeUnretainedValue() as String? else { continue }

            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameRef: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &nameRef) == noErr,
                  let name = nameRef?.takeUnretainedValue() as String? else { continue }

            devices.append(AudioDevice(id: deviceID, uid: uid, name: name))
        }
        return devices
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        availableInputDevices().first(where: { $0.uid == uid })?.id
    }
}

// MARK: - AudioRecorderError

enum AudioRecorderError: LocalizedError {
    case invalidInputFormat(String)
    case missingInputDevice

    var errorDescription: String? {
        switch self {
        case .invalidInputFormat(let d): return "Invalid input format: \(d)"
        case .missingInputDevice:        return "No audio input device available."
        }
    }
}

// MARK: - AudioRecorder

/// AVAudioEngine-based always-on recorder.
/// Tracks audio level and silence ratio per chunk.
final class AudioRecorder: NSObject, ObservableObject, @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private let audioFileQueue = DispatchQueue(label: "com.autoclawd.audiofile", qos: .utility)
    private var currentDeviceUID: String?
    private var storedInputFormat: AVAudioFormat?

    // Silence tracking — reset on each startRecording()
    private var totalFrames: Int = 0
    private var silentFrames: Int = 0
    private let silenceThreshold: Float = 0.005  // RMS below this = silent

    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    private var smoothedLevel: Float = 0.0
    private let _recording = OSAllocatedUnfairLock(initialState: false)

    /// Ratio of silent frames in the last chunk (0.0 – 1.0).
    var silenceRatio: Float {
        guard totalFrames > 0 else { return 1.0 }
        return Float(silentFrames) / Float(totalFrames)
    }

    /// True if the most recent audio buffer was below the silence threshold.
    private(set) var isSilentNow: Bool = false

    // MARK: - Start

    func startRecording(outputURL: URL, deviceUID: String? = nil) throws {
        totalFrames = 0
        silentFrames = 0
        smoothedLevel = 0.0

        guard AVCaptureDevice.default(for: .audio) != nil else {
            throw AudioRecorderError.missingInputDevice
        }

        // Reuse engine if same device
        if audioEngine == nil || currentDeviceUID != deviceUID {
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine?.stop()
            audioEngine = nil

            let engine = AVAudioEngine()
            if let uid = deviceUID, !uid.isEmpty, uid != "default",
               let deviceID = AudioDevice.deviceID(forUID: uid) {
                var id = deviceID
                AudioUnitSetProperty(
                    engine.inputNode.audioUnit!,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &id,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                )
            }

            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0 else {
                throw AudioRecorderError.invalidInputFormat("Invalid sample rate: \(inputFormat.sampleRate)")
            }
            storedInputFormat = inputFormat

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                guard let self, self._recording.withLock({ $0 }) else { return }
                self.processBuffer(buffer)
            }

            engine.prepare()
            audioEngine = engine
            currentDeviceUID = deviceUID
        }

        if let engine = audioEngine, !engine.isRunning {
            try engine.start()
        }

        guard let inputFormat = storedInputFormat else {
            throw AudioRecorderError.invalidInputFormat("No stored input format")
        }

        // Open output file
        let newFile: AVAudioFile
        do {
            newFile = try AVAudioFile(forWriting: outputURL, settings: inputFormat.settings)
        } catch {
            let fallback: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: inputFormat.sampleRate,
                AVNumberOfChannelsKey: inputFormat.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: inputFormat.isInterleaved ? 0 : 1
            ]
            newFile = try AVAudioFile(
                forWriting: outputURL,
                settings: fallback,
                commonFormat: .pcmFormatInt16,
                interleaved: inputFormat.isInterleaved
            )
        }

        tempFileURL = outputURL
        audioFileQueue.sync { self.audioFile = newFile }
        _recording.withLock { $0 = true }
        DispatchQueue.main.async { self.isRecording = true }
    }

    // MARK: - Stop

    /// Stop recording and return the file URL.
    func stopRecording() -> URL? {
        _recording.withLock { $0 = false }
        audioFileQueue.sync { audioFile = nil }
        audioEngine?.stop()
        DispatchQueue.main.async {
            self.isRecording = false
            self.audioLevel = 0.0
        }
        return tempFileURL
    }

    // MARK: - Buffer Processing

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        // Compute RMS
        var rms: Float = 0
        if let ch = buffer.floatChannelData {
            let samples = ch[0]
            var sum: Float = 0
            for i in 0..<frames { sum += samples[i] * samples[i] }
            rms = (sum / Float(frames)).squareRoot()
        }

        totalFrames += frames
        if rms < silenceThreshold { silentFrames += frames }
        isSilentNow = rms < silenceThreshold

        // Write to file
        audioFileQueue.sync {
            if let file = audioFile {
                try? file.write(from: buffer)
            }
        }

        // Update level for UI
        let scaled = min(rms * 10.0, 1.0)
        smoothedLevel = rms > smoothedLevel / 10.0
            ? smoothedLevel * 0.3 + scaled * 0.7
            : smoothedLevel * 0.6 + scaled * 0.4

        let level = smoothedLevel
        DispatchQueue.main.async { self.audioLevel = level }
    }
}
