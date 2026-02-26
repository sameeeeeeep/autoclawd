import Foundation
import AppKit

/// Listens for now-playing notifications from Apple Music and Spotify via
/// NSDistributedNotificationCenter (no entitlements required).
@MainActor
final class NowPlayingService: ObservableObject {

    @Published private(set) var currentTitle: String?   = nil
    @Published private(set) var currentArtist: String?  = nil
    @Published private(set) var isPlaying: Bool         = false

    private var observers: [NSObjectProtocol] = []

    init() { start() }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    private func start() {
        let dnc = DistributedNotificationCenter.default()

        // Apple Music / iTunes
        let musicObs = dnc.addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil, queue: .main
        ) { [weak self] note in
            self?.handleAppleMusic(note)
        }

        // Legacy iTunes name (still fires on some macOS versions)
        let itunesObs = dnc.addObserver(
            forName: NSNotification.Name("com.apple.iTunes.playerInfo"),
            object: nil, queue: .main
        ) { [weak self] note in
            self?.handleAppleMusic(note)
        }

        // Spotify
        let spotifyObs = dnc.addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, queue: .main
        ) { [weak self] note in
            self?.handleSpotify(note)
        }

        observers = [musicObs, itunesObs, spotifyObs]
    }

    private func handleAppleMusic(_ note: Notification) {
        let info = note.userInfo
        let state = info?["Player State"] as? String ?? ""
        if state == "Playing" {
            currentTitle  = info?["Name"]   as? String
            currentArtist = info?["Artist"] as? String
            isPlaying     = true
        } else {
            currentTitle  = nil
            currentArtist = nil
            isPlaying     = false
        }
    }

    private func handleSpotify(_ note: Notification) {
        let info = note.userInfo
        let state = info?["Player State"] as? String ?? ""
        if state == "Playing" {
            currentTitle  = info?["Name"]   as? String
            currentArtist = info?["Artist"] as? String
            isPlaying     = true
        } else {
            currentTitle  = nil
            currentArtist = nil
            isPlaying     = false
        }
    }
}
