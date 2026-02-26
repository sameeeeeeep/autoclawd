# Draggable Dots + Music as Person Design

**Date:** 2026-02-26
**Status:** Approved

## Changes

### 1. Fix NowPlayingService — Spotify parser
Spotify posts `com.spotify.client.PlaybackStateChanged` with `"Player State": "Playing"/"Paused"/"Stopped"` (String), not `"Playing": Bool`. Current code checks `Bool` — fix to match Apple Music pattern.

### 2. Music becomes a first-class Person (sound source)

**`Person` model:** add `isMusic: Bool` (default `false`). CGPoint custom Codable already handles encoding; add `isMusic` to `CodingKeys`.

**AppState seeding:** `init_loadPeople()` ensures the decoded array always contains exactly one `isMusic == true` person. If none exists, inject a default Music person (pink, position 0.82/0.80, name "Music ♫") alongside "You". This is idempotent — re-entrant on upgrade.

**Remove:** `MusicDotView`, `SongBubbleView`, `musicDot` computed property from `AmbientMapView.swift`.

**NowPlayingService integration in AppState:**
- Add `@Published var nowPlayingSongTitle: String? = nil`
- Observe `nowPlaying.$isPlaying` and `nowPlaying.$currentTitle` via Combine `sink` in `AppState.init`
- When playing: find `musicPerson` (the `isMusic == true` person), set `currentSpeakerID = musicPerson.id`, set `nowPlayingSongTitle = nowPlaying.currentTitle`
- When stopped: if `currentSpeakerID == musicPerson.id`, clear both

**VoiceDotView:** when `dot.isMusic && dot.isSpeaking`, show `nowPlayingSongTitle` (passed as optional param) below the speech bubble instead of (or in addition to) the name label.

### 3. Draggable dots

**`AmbientMapView`:** each person dot gets a `DragGesture` alongside the existing `TapGesture`.

- Use `.simultaneousGesture(DragGesture(minimumDistance: 6))` so taps still fire for short presses
- On `drag.onChange`: convert drag translation to normalized delta, clamp to `0.05...0.95`, update `appState.people[index].mapPosition` in real-time
- Position saves automatically via `people.didSet → savePeople()`
- No special "edit mode" needed — minimum drag distance of 6pt distinguishes from taps

## Files Changed

| File | Change |
|------|--------|
| `Sources/Person.swift` | Add `isMusic: Bool` to struct + CodingKeys |
| `Sources/AppState.swift` | Seed music person, Combine observation of nowPlaying, `nowPlayingSongTitle` |
| `Sources/NowPlayingService.swift` | Fix Spotify `"Player State"` string parsing |
| `Sources/AmbientMapView.swift` | Remove MusicDotView/SongBubbleView, add DragGesture, pass song title to VoiceDotView |

## Out of Scope
- Multiple simultaneous speakers
- Drag handles / visual drag affordance
- Music person photo/icon differentiation beyond name
