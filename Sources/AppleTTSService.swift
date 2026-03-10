import AVFoundation

// MARK: - AppleTTSService

/// Fallback TTS using Apple's built-in AVSpeechSynthesizer.
/// Each participant is mapped to a different Apple voice for variety.
/// Used when LuxTTS is unavailable or the user prefers the built-in option.
final class AppleTTSService: NSObject, @unchecked Sendable, AVSpeechSynthesizerDelegate {

    static let shared = AppleTTSService()

    private let synthesizer = AVSpeechSynthesizer()
    private var completion: (() -> Void)?

    // Map voice IDs to Apple voice identifiers.
    // These are enhanced voices — if not downloaded, falls back to compact.
    private let voiceMap: [String: String] = [
        "autoclawd": "com.apple.voice.compact.en-US.Samantha",
        "clawd":     "com.apple.voice.compact.en-AU.Karen",
        "narrator":  "com.apple.voice.compact.en-GB.Daniel",
        "sameep":    "com.apple.voice.compact.en-IN.Rishi",
    ]

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API

    /// Speak text with the voice mapped to the given voice ID.
    /// Calls the completion handler when done (for sequential playback).
    func speak(text: String, voiceID: String, rate: Float = 0.5, completion: (() -> Void)? = nil) {
        self.completion = completion

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.volume = SettingsManager.shared.ttsVolume

        // Try to use mapped voice, fall back to default
        if let voiceIdentifier = voiceMap[voiceID],
           let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            // Use a generic English voice
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        synthesizer.speak(utterance)
    }

    /// Stop any ongoing speech.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        completion = nil
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        completion?()
        completion = nil
    }
}
