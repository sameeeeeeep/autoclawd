# Ambient Map — People Roster & Speaker Tagging

**Date:** 2026-02-26
**Status:** Approved

## Goal

Replace the static mock dots on the ambient map with a live, editable people roster. Users can tap a dot to mark who is currently speaking; transcript chunks get tagged with the speaker's name. The people list and location name persist across sessions.

## Data Model

### `Person` (new, `Codable`)
```swift
struct Person: Identifiable, Codable {
    var id: UUID
    var name: String
    var colorIndex: Int        // index into 8-color palette
    var mapPosition: CGPoint   // normalized 0..1
    var isMe: Bool
}
```
Stored as JSON in `UserDefaults` under key `"autoclawd.people"`.
Default seed: one "You" (isMe=true) at position (0.5, 0.58).

### `AppState` additions
- `@Published var people: [Person]` — UserDefaults-backed
- `@Published var currentSpeakerID: UUID?` — transient, resets on launch
- `@Published var locationName: String` — UserDefaults key `"autoclawd.locationName"`, default `"My Room"`

### `TranscriptRecord` addition
- `speakerName: String?` — new optional column
- SQLite migration: `ALTER TABLE transcripts ADD COLUMN speaker_name TEXT`
- `TranscriptStore.save()` gains `speakerName: String? = nil` param

## UI

### AmbientMapView (updated)
- Reads `@EnvironmentObject var appState: AppState` (or passed binding)
- Renders dots from `appState.people` mapped to `VoiceDot`
- `isSpeaking` = `appState.currentSpeakerID == person.id`
- Tap dot → toggle `appState.currentSpeakerID` (tap same = clear)
- `✎` button (top-right corner, 22×22, monospaced) → `showEditor = true`

### MapEditorView (new popover)
Anchored to the `✎` button via `.popover`. Width ~220px.

Sections:
1. **Location** — `TextField("Location name", text: $appState.locationName)`
2. **People** — `List` of rows, each: name `TextField` + color dot swatch + trash button. "You" row has no trash button.
3. **Add person** — text field + "+" button. On confirm: appends `Person` with next color in palette, position auto-placed at centroid of empty space.

Color palette (8 entries, fixed):
```
neonGreen, cyan, orange, purple, pink, yellow, teal, red
```

### Transcript display (MainPanelView)
Each `TranscriptRecord` with `speakerName != nil` prepends a small `[Name]` chip (capsule, colored white/dim) before the chunk text.

## Data Flow

```
User taps dot
  → appState.currentSpeakerID = person.id

Audio chunk finishes
  → ChunkManager reads appState.currentSpeakerID
  → looks up name in appState.people
  → passes speakerName to TranscriptStore.save()
  → stored in SQLite speaker_name column

Transcript view
  → fetches TranscriptRecord rows
  → renders [SpeakerName] chip if speakerName != nil
```

## Files Changed

| File | Change |
|------|--------|
| `Sources/Person.swift` | NEW — Person model + color palette |
| `Sources/AppState.swift` | Add people, currentSpeakerID, locationName |
| `Sources/TranscriptStore.swift` | Add speakerName column + migration |
| `Sources/ChunkManager.swift` | Pass speakerName to TranscriptStore.save() |
| `Sources/AmbientMapView.swift` | Read from AppState, tap-to-tag, editor button |
| `Sources/MapEditorView.swift` | NEW — popover editor |
| `Sources/AppDelegate.swift` | Pass appState to AmbientMapView |
| `Sources/MainPanelView.swift` | Show speaker chip on transcript rows |

## Out of Scope

- Drag-to-reposition dots on the map (future)
- AI speaker identification (future — currentSpeakerID is the hook for it)
- Color picker (palette only for now)
- Photo/avatar per person
