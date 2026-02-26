# ShazamKit Ambient Music Recognition Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Recognize ambient music captured by the mic using ShazamKit, activating the Music ♫ person on the map when a song is identified.

**Architecture:** `AudioRecorder` fires an `onBuffer` callback per PCM buffer → `ShazamKitService` feeds buffers into `SHSession.matchStreamingBuffer` → on a match, AppState's Combine sink activates the Music person (only when NowPlayingService isn't already playing).

**Tech Stack:** Swift, ShazamKit (`SHSession`, `SHSessionDelegate`), AVFoundation (`AVAudioPCMBuffer`), Combine, swiftc direct compilation.

---

### Task 1: Add ShazamKit framework to Makefile

**Files:**
- Modify: `Makefile`

**Step 1: Add `-framework ShazamKit` to SWIFT_FLAGS**

In `Makefile`, find:
```makefile
SWIFT_FLAGS = \
	-parse-as-library \
	-sdk $(SDK) \
	-target $(TARGET) \
	-lsqlite3
```

Replace with:
```makefile
SWIFT_FLAGS = \
	-parse-as-library \
	-sdk $(SDK) \
	-target $(TARGET) \
	-lsqlite3 \
	-framework ShazamKit
```

**Step 2: Verify build still passes (no ShazamKit code yet — just flags)**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd" && make all 2>&1 | tail -5
```
Expected: `Built build/AutoClawd.app` — no errors.

**Step 3: Commit**

```bash
git add Makefile
git commit -m "build: link ShazamKit framework"
```

---

### Task 2: Create `ShazamKitService.swift`

**Files:**
- Create: `Sources/ShazamKitService.swift`

**Step 1: Create the file**

```swift
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
```

**Step 2: Build to verify it compiles**

```bash
make all 2>&1 | tail -5
```
Expected: `Built build/AutoClawd.app` — no errors. (ShazamKit symbols should resolve with the flag added in Task 1.)

**Step 3: Commit**

```bash
git add Sources/ShazamKitService.swift
git commit -m "feat: add ShazamKitService for ambient music recognition"
```

---

### Task 3: Add `onBuffer` callback to `AudioRecorder`

**Files:**
- Modify: `Sources/AudioRecorder.swift`

**Step 1: Add the callback property**

In `AudioRecorder` class body, after the `isSilentNow` property (around line 122), add:

```swift
/// Called with every PCM buffer — used by ShazamKitService to identify ambient music.
var onBuffer: ((AVAudioPCMBuffer) -> Void)?
```

**Step 2: Fire the callback in `processBuffer`**

In `processBuffer(_:)`, after the line:
```swift
audioFileQueue.sync {
    if let file = audioFile {
        try? file.write(from: buffer)
    }
}
```

Add:
```swift
// Forward buffer to registered handlers (e.g. ShazamKitService)
onBuffer?(buffer)
```

**Step 3: Build**

```bash
make all 2>&1 | tail -5
```
Expected: `Built build/AutoClawd.app`

**Step 4: Commit**

```bash
git add Sources/AudioRecorder.swift
git commit -m "feat: add onBuffer callback to AudioRecorder for downstream processing"
```

---

### Task 4: Expose buffer hook on `ChunkManager`

`AudioRecorder` is `private` inside `ChunkManager`, so `AppState` can't reach it directly. Add a single forwarding method.

**Files:**
- Modify: `Sources/ChunkManager.swift`

**Step 1: Add `setBufferHandler` method**

In `ChunkManager`, after the `configure(...)` method (around line 80), add:

```swift
/// Forwards raw PCM buffers from the mic to an external handler (e.g. ShazamKitService).
func setBufferHandler(_ handler: @escaping (AVAudioPCMBuffer) -> Void) {
    audioRecorder.onBuffer = handler
}
```

**Step 2: Build**

```bash
make all 2>&1 | tail -5
```
Expected: `Built build/AutoClawd.app`

**Step 3: Commit**

```bash
git add Sources/ChunkManager.swift
git commit -m "feat: expose setBufferHandler on ChunkManager for ShazamKit"
```

---

### Task 5: Wire up `ShazamKitService` in `AppState`

**Files:**
- Modify: `Sources/AppState.swift`

**Step 1: Add `shazam` service property**

In the `// MARK: - Services` section (around line 100), after `let nowPlaying = NowPlayingService()`, add:

```swift
let shazam = ShazamKitService()
```

**Step 2: Start Shazam and wire the buffer handler in `init`**

In `init()`, after `configureChunkManager()` (and after the existing `nowPlaying.$isPlaying` Combine subscription), add:

```swift
// Start ShazamKit ambient recognition
shazam.start()
chunkManager.setBufferHandler { [weak self] buf in
    self?.shazam.process(buf)
}

// Surface Shazam matches when NowPlayingService isn't already playing
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

**Step 3: Build**

```bash
make all 2>&1 | tail -5
```
Expected: `Built build/AutoClawd.app` — no errors.

**Step 4: Commit**

```bash
git add Sources/AppState.swift
git commit -m "feat: wire ShazamKitService into AppState — ambient music auto-activates Music person"
```

---

### Task 6: Bump version to v1.4.0 + install

**Files:**
- Modify: `Info.plist`

**Step 1: Bump version**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
sed -i '' 's/<string>1\.3\.0<\/string>/<string>1.4.0<\/string>/g' Info.plist
grep "CFBundleShortVersionString" -A1 Info.plist
```
Expected output confirms `1.4.0`.

**Step 2: Final build**

```bash
make all 2>&1 | tail -5
```

**Step 3: Commit + push**

```bash
git add Info.plist
git commit -m "chore: bump to v1.4.0"
git push origin main
```

**Step 4: Install**

Copy entitlements to /tmp to avoid path-with-spaces issues, then install:

```bash
cp "/Users/sameeprehlan/Documents/Claude Code/autoclawd/AutoClawd-adhoc.entitlements" /tmp/AutoClawd-adhoc.entitlements

APP_SRC="/Users/sameeprehlan/Documents/Claude Code/autoclawd/build/AutoClawd.app"
APP_DST="/Applications/AutoClawd.app"

osascript <<EOF
do shell script "pkill -x AutoClawd; true" with administrator privileges
do shell script "rm -rf '$APP_DST' && cp -r '$APP_SRC' '$APP_DST' && xattr -cr '$APP_DST' && codesign --force --sign - --entitlements /tmp/AutoClawd-adhoc.entitlements '$APP_DST'" with administrator privileges
EOF
```

**Step 5: Verify + launch**

```bash
codesign --verify --deep /Applications/AutoClawd.app && \
defaults read /Applications/AutoClawd.app/Contents/Info.plist CFBundleShortVersionString && \
open /Applications/AutoClawd.app
```
Expected: `Signature OK` and `1.4.0`.

---

## Smoke Test Checklist

- [ ] App launches, version shows v1.4.0
- [ ] Play music from a Bluetooth speaker or another device near the Mac mic — Music ♫ dot activates and shows the song title after ~10–15 seconds
- [ ] Stop the music — title clears after ~30 seconds (hold timer)
- [ ] While Apple Music is playing, Shazam result does NOT override the NowPlaying title
- [ ] Apple Music stops → if ambient music still audible, Shazam takes over
