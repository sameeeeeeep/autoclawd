import AVFoundation
import ShazamKit

/// Identifies ambient music from mic audio using ShazamKit.
/// Feed PCM buffers via process(_:). Publishes currentTitle/currentArtist on match.
/// NowPlayingService takes priority — AppState guards against overriding it.
@MainActor
final class ShazamKitService: NSObject, ObservableObject {

    @Published private(set) var currentTitle:  String? = nil
    @Published private(set) var currentArtist: String? = nil

    private var session: SHSession?
    private var holdTimer: Timer?
    /// Seconds to keep the song title displayed after the last Shazam match
    /// (prevents flicker when audio briefly dips below recognition threshold).
    private let holdDuration: TimeInterval = 30

    // MARK: - Lifecycle

    func start() {
        resetSession()
    }

    func stop() {
        session = nil
        holdTimer?.invalidate()
        holdTimer = nil
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
            self.holdTimer?.invalidate()
            self.holdTimer = nil
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
            // Reset hold timer — clear title after holdDuration of no matches
            self.holdTimer?.invalidate()
            self.holdTimer = Timer.scheduledTimer(
                withTimeInterval: self.holdDuration,
                repeats: false
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.currentTitle  = nil
                    self?.currentArtist = nil
                }
            }
        }
    }
}
