# ShazamKit Ambient Music Recognition — Design

**Date:** 2026-02-27
**Version target:** v1.4.0

## Problem

`NowPlayingService` detects music from Apple Music and Spotify via `NSDistributedNotificationCenter`. It cannot detect music from any other source — outdoor speakers, a venue sound system, a YouTube video, a different audio app. The mic is always on; we should use it to identify ambient music even when no recognised app is playing.

## Approach

Use Apple's native **ShazamKit** framework (`SHSession`, available macOS 12+) to fingerprint audio coming off the existing `AVAudioEngine` tap in `AudioRecorder`. No external dependencies, no API key, no subprocess. The `SHSession` delegate fires on a match with title + artist.

**Priority rule:** `NowPlayingService` (Apple Music / Spotify) always wins. Shazam only surfaces a result when `nowPlaying.isPlaying == false`.

## Architecture

```
mic → AudioRecorder.processBuffer
           ↓ onBuffer? closure
      ShazamKitService.process(_:)
           ↓ SHSession.matchStreamingBuffer
      SHSessionDelegate.didFind(match:)
           ↓ @Published currentTitle / currentArtist
      AppState Combine sink
           ↓ (guard !nowPlaying.isPlaying)
      nowPlayingSongTitle + Music person active
```

## Components

### `Sources/ShazamKitService.swift` (new)

```swift
import ShazamKit

@MainActor
final class ShazamKitService: NSObject, ObservableObject, SHSessionDelegate {
    @Published private(set) var currentTitle:  String? = nil
    @Published private(set) var currentArtist: String? = nil

    private var session: SHSession?
    private var holdTimer: Timer?
    private let holdDuration: TimeInterval = 30  // seconds to keep title after last match

    func start() {
        session = SHSession()
        session?.delegate = self
    }

    func stop() {
        session = nil
        holdTimer?.invalidate()
        currentTitle  = nil
        currentArtist = nil
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        session?.matchStreamingBuffer(buffer, at: nil)
    }

    // SHSessionDelegate — called on main queue (session delivers on delegate queue)
    func session(_ session: SHSession, didFind match: SHMatch) {
        guard let item = match.mediaItems.first else { return }
        holdTimer?.invalidate()
        currentTitle  = item.title
        currentArtist = item.artist
        // After a match, recreate session so we're ready to detect the next song
        self.session = SHSession()
        self.session?.delegate = self
    }

    func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        // Start / reset the hold timer — clear title after 30s of no matches
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdDuration, repeats: false) { [weak self] _ in
            self?.currentTitle  = nil
            self?.currentArtist = nil
        }
    }
}
```

### `Sources/AudioRecorder.swift` (minor addition)

- Add `var onBuffer: ((AVAudioPCMBuffer) -> Void)?`
- In `processBuffer(_:)`, after writing to file: `onBuffer?(buffer)`
- No other changes.

### `Sources/AppState.swift` (wire-up)

1. Add `let shazam = ShazamKitService()` alongside existing services.
2. After `configureChunkManager()` in `init`, call `shazam.start()` and set the buffer callback:
   ```swift
   chunkManager.audioRecorder.onBuffer = { [weak self] buf in
       self?.shazam.process(buf)
   }
   ```
   *(Need to verify `chunkManager.audioRecorder` is accessible — check `ChunkManager.swift` during impl.)*
3. Add Combine subscription:
   ```swift
   shazam.$currentTitle
       .receive(on: RunLoop.main)
       .sink { [weak self] title in
           guard let self, !self.nowPlaying.isPlaying else { return }
           guard let musicPerson = self.people.first(where: { $0.isMusic }) else { return }
           if let title {
               self.currentSpeakerID    = musicPerson.id
               self.nowPlayingSongTitle = title
           } else if self.currentSpeakerID == musicPerson.id {
               self.currentSpeakerID    = nil
               self.nowPlayingSongTitle = nil
           }
       }
       .store(in: &cancellables)
   ```

### `Info.plist`

Bump `CFBundleShortVersionString` to `1.4.0`.

### `Makefile`

Add `-framework ShazamKit` to the `swiftc` link flags.

## Data Flow — Priority

| Source | Condition | Effect |
|--------|-----------|--------|
| NowPlayingService | Apple Music / Spotify playing | Always activates Music person + sets title |
| ShazamKitService | Shazam match fires + `nowPlaying.isPlaying == false` | Activates Music person + sets title |
| ShazamKitService | Hold timer expires (30s no match) | Clears Music person + title (only if NowPlaying also silent) |

## Out of Scope

- Shazam history / match log in the transcript
- Confidence threshold UI
- Manual "listen now" trigger
- Displaying artist name separately (title only for now, consistent with existing behaviour)
