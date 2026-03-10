import AVFoundation
import Combine

// MARK: - TTSPlayer

/// Manages a sequential audio playback queue for TTS narration.
/// Each participant's speech is queued and played one at a time.
/// The `currentVoiceID` drives speaking animations in the UI.
@MainActor
final class TTSPlayer: ObservableObject {

    // MARK: - Published State

    @Published var isPlaying = false
    @Published var currentVoiceID: String? = nil

    // MARK: - Configuration

    var masterVolume: Float = 0.8

    // MARK: - Private State

    private var player: AVAudioPlayer?
    private var queue: [(voiceID: String, data: Data)] = []
    private var volumePerVoice: [String: Float] = [:]
    private var playerDelegate: PlayerDelegate?

    // MARK: - Public API

    /// Enqueue audio for sequential playback.
    func enqueue(voiceID: String, audioData: Data) {
        queue.append((voiceID: voiceID, data: audioData))
        if !isPlaying {
            playNext()
        }
    }

    /// Skip the currently playing utterance and move to next.
    func skip() {
        player?.stop()
        player = nil
        playNext()
    }

    /// Stop all playback and clear the queue.
    func stopAll() {
        player?.stop()
        player = nil
        queue.removeAll()
        isPlaying = false
        currentVoiceID = nil
    }

    /// Set volume for a specific voice (0.0–1.0). Pass nil to mute.
    func setVolume(_ volume: Float?, for voiceID: String) {
        volumePerVoice[voiceID] = volume
        // Update live player if it's this voice
        if currentVoiceID == voiceID, let player {
            player.volume = (volume ?? 0) * masterVolume
        }
    }

    // MARK: - Playback Engine

    private func playNext() {
        guard !queue.isEmpty else {
            isPlaying = false
            currentVoiceID = nil
            return
        }

        let item = queue.removeFirst()

        // Check if this voice is muted
        let muted = SettingsManager.shared.ttsMutedVoices
        if muted.contains(item.voiceID) {
            playNext()
            return
        }

        do {
            let audioPlayer = try AVAudioPlayer(data: item.data)
            let voiceVol = volumePerVoice[item.voiceID] ?? 1.0
            audioPlayer.volume = voiceVol * masterVolume

            let delegate = PlayerDelegate { [weak self] in
                Task { @MainActor [weak self] in
                    self?.playNext()
                }
            }
            audioPlayer.delegate = delegate
            self.playerDelegate = delegate

            audioPlayer.prepareToPlay()
            audioPlayer.play()

            player = audioPlayer
            isPlaying = true
            currentVoiceID = item.voiceID

        } catch {
            Log.warn(.system, "[TTS] Failed to play audio: \(error)")
            playNext()
        }
    }
}

// MARK: - PlayerDelegate

/// Bridges AVAudioPlayerDelegate to a closure for sequential playback.
private class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinished: () -> Void

    init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinished()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        onFinished()
    }
}
