import AVFoundation
import Foundation

final class SpeechService: @unchecked Sendable {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()
    private let voiceID = "com.apple.voice.compact.en-US.Samantha"
    private let maxWords = 10

    private init() {}

    /// Speak up to the first `maxWords` words of `text`.
    func speak(_ text: String) {
        let words = text.split(separator: " ").prefix(maxWords)
        guard !words.isEmpty else { return }
        let trimmed = words.joined(separator: " ")

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceID)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52
        utterance.volume = 0.9

        DispatchQueue.main.async { [weak self] in
            self?.synthesizer.stopSpeaking(at: .immediate)
            self?.synthesizer.speak(utterance)
        }
        Log.info(.system, "TTS: \"\(trimmed)\"")
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
