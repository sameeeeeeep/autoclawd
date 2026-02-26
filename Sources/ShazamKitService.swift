import AVFoundation
import ShazamKit

/// Identifies ambient music from mic audio using ShazamKit.
/// Call start() before feeding buffers via process(_:).
/// Publishes currentTitle/currentArtist on match.
/// NowPlayingService takes priority — AppState guards against overriding it.
@MainActor
final class ShazamKitService: NSObject, ObservableObject {

    @Published private(set) var currentTitle:  String? = nil
    @Published private(set) var currentArtist: String? = nil

    private var session: SHSession?
    private var holdTask: Task<Void, Never>?
    /// Seconds to keep the song title displayed after the last Shazam match
    /// (prevents flicker when audio briefly dips below recognition threshold).
    private let holdDuration: TimeInterval = 30

    // MARK: - Lifecycle

    func start() {
        resetSession()
    }

    func stop() {
        session = nil
        holdTask?.cancel()
        holdTask = nil
        currentTitle  = nil
        currentArtist = nil
    }

    // MARK: - Buffer ingestion

    /// Call this for every AVAudioPCMBuffer from the mic.
    func process(_ buffer: AVAudioPCMBuffer) {
        session?.matchStreamingBuffer(buffer, at: nil)
    }

    // MARK: - Private helpers

    private func resetSession() {
        let s = SHSession()
        s.delegate = self
        session = s
    }
}

// MARK: - SHSessionDelegate

extension ShazamKitService: SHSessionDelegate {

    nonisolated func session(_ session: SHSession, didFind match: SHMatch) {
        guard let item = match.mediaItems.first else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.holdTask?.cancel()
            self.holdTask = nil
            self.currentTitle  = item.title
            self.currentArtist = item.artist
            // Recreate session so we're ready to detect the next song immediately
            self.resetSession()
        }
    }

    nonisolated func session(
        _ session: SHSession,
        didNotFindMatchFor signature: SHSignature,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // The hold timer resets on every no-match signature while ambient audio is present.
            // This is intentional: the title lingers as long as any audio (even unrecognisable)
            // is reaching the mic, and only clears ~holdDuration seconds after audio ceases.
            self.holdTask?.cancel()
            self.holdTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(self?.holdDuration ?? 30))
                self?.currentTitle  = nil
                self?.currentArtist = nil
            }
        }
    }
}
