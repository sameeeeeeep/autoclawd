import AVFoundation
import Foundation
import Speech

// MARK: - StreamingLocalTranscriber
//
// Uses SFSpeechAudioBufferRecognitionRequest to transcribe live audio buffers
// in real-time — words appear as they're spoken, no 30-second wait.
//
// Usage:
//   1. start()  — creates SFSpeechRecognizer + recognition request
//   2. appendBuffer(_:)  — feed AVAudioPCMBuffer from mic tap (called continuously)
//   3. commitAndReset() async  — end current chunk, await final text, start fresh
//   4. stop()  — tear everything down
//
// onPartial fires on every partial result (main thread) — use for live UI preview.
// commitAndReset() returns the finalized text for the chunk; starts a new request
// so the next chunk immediately begins accumulating.

final class StreamingLocalTranscriber: @unchecked Sendable {

    /// Called on the main thread with every intermediate transcript update.
    /// Ideal for driving a live-text preview in the UI.
    var onPartial: ((String) -> Void)?

    private let lock = NSLock()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var _latestTranscript = ""
    private var _gotFinal = false

    // MARK: - Lifecycle

    /// Requests speech auth if needed, then starts the first recognition request.
    func start() throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status != .authorized {
            // Auth is async — best-effort synchronous check; ChunkManager already
            // calls requestAuthorization() at configure time in local mode.
            guard status != .denied && status != .restricted else {
                throw TranscriptionError.failed("Speech recognition not authorized")
            }
        }

        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              rec.isAvailable else {
            throw TranscriptionError.failed("On-device speech recognizer unavailable")
        }
        recognizer = rec
        _startNewRequest(recognizer: rec)
        Log.info(.transcribe, "StreamingLocalTranscriber: started (on-device: \(rec.supportsOnDeviceRecognition))")
    }

    /// Feed a live PCM buffer. Called from the AudioRecorder tap — always on,
    /// even between chunk boundaries (engine stays hot).
    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { recognitionRequest?.append(buffer) }
    }

    /// Ends the current recognition request, waits up to 1.5 s for the final
    /// result, then starts a fresh request for the next chunk.
    /// Returns the committed transcript (empty string if nothing was detected).
    func commitAndReset() async -> String {
        // Signal to SFSpeech that no more audio is coming for this chunk.
        lock.withLock {
            _gotFinal = false
            recognitionRequest?.endAudio()
        }

        // Poll up to 1.5 s for isFinal. In practice SFSpeech delivers it within
        // 100–400 ms after endAudio(). Fall back to latest partial on timeout.
        for _ in 0..<15 {
            try? await Task.sleep(for: .milliseconds(100))
            if lock.withLock({ _gotFinal }) { break }
        }

        let committed = lock.withLock { _latestTranscript }
        lock.withLock {
            _latestTranscript = ""
            _gotFinal = false
        }

        // Immediately start fresh so the next chunk begins accumulating.
        if let rec = lock.withLock({ recognizer }) {
            _startNewRequest(recognizer: rec)
        }

        return committed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Fully tears down recognition. Safe to call multiple times.
    func stop() {
        lock.withLock {
            recognitionRequest?.endAudio()
            recognitionTask?.cancel()
            recognitionRequest = nil
            recognitionTask = nil
        }
        Log.info(.transcribe, "StreamingLocalTranscriber: stopped")
    }

    // MARK: - Private

    private func _startNewRequest(recognizer: SFSpeechRecognizer) {
        lock.withLock {
            recognitionTask?.cancel()

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            recognitionRequest = req

            let task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                guard let self else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    self.lock.withLock { self._latestTranscript = text }

                    // Fire partial callback on main thread for live UI update.
                    DispatchQueue.main.async { self.onPartial?(text) }

                    if result.isFinal {
                        self.lock.withLock {
                            self._latestTranscript = text
                            self._gotFinal = true
                        }
                    }
                }

                if let error {
                    let msg = error.localizedDescription
                    if !msg.localizedCaseInsensitiveContains("no speech") &&
                       !msg.localizedCaseInsensitiveContains("cancel") {
                        Log.warn(.transcribe, "StreamingLocalTranscriber error: \(msg)")
                    }
                    // Mark final so commitAndReset() doesn't time out waiting.
                    self.lock.withLock { self._gotFinal = true }
                }
            }
            recognitionTask = task
        }
    }
}
