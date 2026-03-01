# Draggable Dots + Music Person — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make map dots draggable for physical positioning, fix Spotify detection, and replace the separate MusicDotView with a first-class "Music" person in the people roster.

**Architecture:** `Person` gains `isMusic: Bool`; AppState seeds a Music person on first launch and uses Combine to auto-activate it when NowPlayingService fires; `AmbientMapView` renders it like any other person and adds `DragGesture` to all dots; `MusicDotView`/`SongBubbleView` are deleted.

**Tech Stack:** SwiftUI, Combine, SQLite3, NSDistributedNotificationCenter

---

### Task 1: Add `isMusic` to `Person` model

**Files:**
- Modify: `Sources/Person.swift`

**Step 1: Add `isMusic: Bool` property to the struct**

After `var isMe: Bool`, add:
```swift
var isMusic: Bool
```

**Step 2: Add `isMusic` to `CodingKeys`**
```swift
enum CodingKeys: String, CodingKey {
    case id, name, colorIndex, posX, posY, isMe, isMusic
}
```

**Step 3: Update `init`**
```swift
init(id: UUID, name: String, colorIndex: Int, mapPosition: CGPoint, isMe: Bool, isMusic: Bool = false) {
    self.id = id; self.name = name; self.colorIndex = colorIndex
    self.mapPosition = mapPosition; self.isMe = isMe; self.isMusic = isMusic
}
```

**Step 4: Update `init(from decoder:)`** — add after `isMe` decode:
```swift
isMusic = (try? c.decode(Bool.self, forKey: .isMusic)) ?? false
```
(Optional decode with `??` so existing saved data without `isMusic` defaults to `false`.)

**Step 5: Update `encode(to encoder:)`** — add after `isMe` encode:
```swift
try c.encode(isMusic, forKey: .isMusic)
```

**Step 6: Add `makeMusic()` factory**
```swift
static func makeMusic() -> Person {
    Person(id: UUID(), name: "Music ♫",
           colorIndex: PersonColor.pink.rawValue,
           mapPosition: CGPoint(x: 0.82, y: 0.80),
           isMe: false, isMusic: true)
}
```

**Step 7: Build**
```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd" && make all 2>&1 | tail -10
```
Expected: clean build.

**Step 8: Commit**
```bash
git add Sources/Person.swift
git commit -m "feat: add isMusic flag to Person model"
```

---

### Task 2: Fix Spotify parser in NowPlayingService

**Files:**
- Modify: `Sources/NowPlayingService.swift`

**The bug:** `handleSpotify` checks `info?["Playing"] as? Bool` but Spotify actually sends `info?["Player State"] as? String` (same as Apple Music).

**Step 1: Replace `handleSpotify` entirely**
```swift
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
```

**Step 2: Build**
```bash
make all 2>&1 | tail -5
```

**Step 3: Commit**
```bash
git add Sources/NowPlayingService.swift
git commit -m "fix: Spotify uses Player State string, not Playing Bool"
```

---

### Task 3: Update AppState — seed music person + Combine observation

**Files:**
- Modify: `Sources/AppState.swift`

**Step 1: Add `nowPlayingSongTitle` published property** — after `currentSpeakerID`:
```swift
@Published var nowPlayingSongTitle: String? = nil
```

**Step 2: Update `init_loadPeople()` to ensure a Music person always exists**

Replace the existing static func body:
```swift
private static func init_loadPeople() -> [Person] {
    var people: [Person]
    if let data = UserDefaults.standard.data(forKey: peopleKey),
       let decoded = try? JSONDecoder().decode([Person].self, from: data),
       !decoded.isEmpty {
        people = decoded
    } else {
        people = [Person.makeMe()]
    }
    // Ensure exactly one isMusic person exists (upgrade migration)
    if !people.contains(where: { $0.isMusic }) {
        people.append(Person.makeMusic())
    }
    return people
}
```

**Step 3: Add Combine observation in `AppState.init`** — after the existing Combine subscriptions (find where `cancellables` is used, add nearby):

```swift
// Auto-activate Music person when NowPlayingService detects a song
nowPlaying.$isPlaying
    .combineLatest(nowPlaying.$currentTitle)
    .receive(on: RunLoop.main)
    .sink { [weak self] isPlaying, title in
        guard let self else { return }
        guard let musicPerson = self.people.first(where: { $0.isMusic }) else { return }
        if isPlaying {
            self.currentSpeakerID    = musicPerson.id
            self.nowPlayingSongTitle = title
        } else if self.currentSpeakerID == musicPerson.id {
            self.currentSpeakerID    = nil
            self.nowPlayingSongTitle = nil
        }
    }
    .store(in: &cancellables)
```

**Step 4: Build**
```bash
make all 2>&1 | tail -10
```

**Step 5: Commit**
```bash
git add Sources/AppState.swift
git commit -m "feat: seed Music person + Combine auto-activation from NowPlayingService"
```

---

### Task 4: Refactor AmbientMapView — remove MusicDotView, add drag

**Files:**
- Modify: `Sources/AmbientMapView.swift`

This is the biggest task. Make these changes one at a time.

**Step 1: Remove `@ObservedObject private var nowPlaying`, the custom `init(appState:)`, and the `musicDot` computed property**

The view no longer needs direct nowPlaying access — AppState handles it via Combine.
Change the struct header back to a simple stored property (no custom init needed):
```swift
struct AmbientMapView: View {
    @ObservedObject var appState: AppState
    @State private var showEditor  = false
    @State private var dragStarts: [UUID: CGPoint] = [:]

    private let mapSize: CGFloat = 200
    // (no init, no nowPlaying, no musicDot)
```

**Step 2: In the `GeometryReader` block, replace the entire `ForEach` + `MusicDotView` block** with a version that uses `ForEach($appState.people)` binding and adds `DragGesture`:

```swift
GeometryReader { geo in
    ForEach($appState.people) { $person in
        let isSpeaking = appState.currentSpeakerID == person.id
        // Song title shown for music person while speaking
        let subtitle: String? = (person.isMusic && isSpeaking)
            ? appState.nowPlayingSongTitle
            : nil
        VoiceDotView(dot: VoiceDot(
            id: person.id.uuidString,
            name: person.name,
            color: person.color,
            position: person.mapPosition,
            isSpeaking: isSpeaking,
            isMe: person.isMe
        ), subtitle: subtitle)
        .position(
            x: person.mapPosition.x * geo.size.width,
            y: person.mapPosition.y * geo.size.height
        )
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                appState.toggleSpeaker(person.id)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { drag in
                    let start = dragStarts[person.id] ?? person.mapPosition
                    if dragStarts[person.id] == nil {
                        dragStarts[person.id] = person.mapPosition
                    }
                    let newX = start.x + drag.translation.width  / geo.size.width
                    let newY = start.y + drag.translation.height / geo.size.height
                    person.mapPosition = CGPoint(
                        x: max(0.05, min(0.95, newX)),
                        y: max(0.05, min(0.95, newY))
                    )
                }
                .onEnded { _ in
                    dragStarts.removeValue(forKey: person.id)
                }
        )
    }
}
.padding(16)
```

**Step 3: Update `VoiceDotView` to accept and display `subtitle`**

Change its signature:
```swift
struct VoiceDotView: View {
    let dot: VoiceDot
    var subtitle: String? = nil    // shown below name when set (e.g. song title)
    @State private var pulseScale: CGFloat = 1.0
```

In the body, find the name label (`Text(dot.name).offset(y: ...)`) and add a subtitle below it:
```swift
// Name label
Text(dot.name)
    .font(.system(size: 8, weight: .medium, design: .monospaced))
    .foregroundColor(.white.opacity(0.6))
    .offset(y: dotSize / 2 + 9)

// Song subtitle (music person only)
if let sub = subtitle {
    Text(sub)
        .font(.system(size: 7, design: .monospaced))
        .foregroundColor(.white.opacity(0.45))
        .lineLimit(1)
        .frame(maxWidth: 60)
        .offset(y: dotSize / 2 + 20)
}
```

**Step 4: Delete `MusicDotView` and `SongBubbleView`** — remove both structs entirely from the file.

**Step 5: Build**
```bash
make all 2>&1 | tail -10
```
Fix any errors. Common issues:
- `VoiceDotView` may need `subtitle` passed at existing call sites (it defaults to `nil` so no change needed for old callers)
- Ensure `ForEach($appState.people)` compiles — requires `$person` binding syntax

**Step 6: Commit**
```bash
git add Sources/AmbientMapView.swift
git commit -m "feat: draggable dots + music as regular person, remove MusicDotView"
```

---

### Task 5: Bump version + install

**Step 1: Bump to v1.3.0**
```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
sed -i '' 's/<string>1\.2\.0<\/string>/<string>1.3.0<\/string>/g' Info.plist
grep "CFBundleShortVersionString" -A1 Info.plist
```

**Step 2: Build**
```bash
make all 2>&1 | tail -5
```

**Step 3: Commit and push**
```bash
git add Info.plist
git commit -m "chore: bump to v1.3.0"
git push origin main
```

**Step 4: Verify smoke-test checklist (manual)**
- Map shows "Music ♫" dot at bottom-right alongside "You"
- Drag any dot → it moves, position saved on relaunch
- Tap dot → toggles speaker state; tap same → clears
- Play a song in Apple Music or Spotify → Music ♫ dot pulses + song title appears as subtitle
- Stop playback → dot returns to idle
- `✎` editor: Music ♫ appears in list, can rename, cannot be deleted (isMusic person has no trash button — verify `isMe` guard also covers `isMusic` in `PersonRowView`)
