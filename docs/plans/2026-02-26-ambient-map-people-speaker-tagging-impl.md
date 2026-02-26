# Ambient Map — People Roster & Speaker Tagging — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace static mock dots with a live, editable people roster; tap a dot to tag the current speaker; transcript chunks are stored with a speaker name.

**Architecture:** `Person` model stored as JSON in UserDefaults; `AppState` owns `people`, `currentSpeakerID`, and `locationName`; `TranscriptStore` gains a `speaker_name` SQLite column via safe migration; `ChunkManager` reads `currentSpeakerID` at save time; `AmbientMapView` becomes interactive via an edit popover.

**Tech Stack:** SwiftUI, SQLite3 (direct), UserDefaults, Combine

---

### Task 1: Create `Person` model + color palette

**Files:**
- Create: `Sources/Person.swift`

**Step 1: Create the file**

```swift
// Sources/Person.swift
import SwiftUI

// MARK: - Color Palette

enum PersonColor: Int, CaseIterable, Codable {
    case neonGreen, cyan, orange, purple, pink, yellow, teal, red

    var color: Color {
        switch self {
        case .neonGreen: return BrutalistTheme.neonGreen
        case .cyan:      return Color(red: 0.0, green: 0.85, blue: 1.0)
        case .orange:    return Color(red: 1.0, green: 0.65, blue: 0.0)
        case .purple:    return Color(red: 0.72, green: 0.38, blue: 1.0)
        case .pink:      return Color(red: 1.0, green: 0.40, blue: 0.75)
        case .yellow:    return Color(red: 1.0, green: 0.90, blue: 0.20)
        case .teal:      return Color(red: 0.20, green: 0.80, blue: 0.70)
        case .red:       return Color(red: 1.0, green: 0.28, blue: 0.28)
        }
    }
}

// MARK: - Person

struct Person: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var colorIndex: Int          // PersonColor.rawValue
    var mapPosition: CGPoint     // normalized 0..1
    var isMe: Bool

    var personColor: PersonColor {
        PersonColor(rawValue: colorIndex) ?? .cyan
    }

    var color: Color { personColor.color }

    /// Default "You" person placed at centre-ish of map.
    static func makeMe() -> Person {
        Person(id: UUID(), name: "You", colorIndex: PersonColor.neonGreen.rawValue,
               mapPosition: CGPoint(x: 0.50, y: 0.58), isMe: true)
    }

    // CGPoint is not Codable by default — manual encode/decode
    enum CodingKeys: String, CodingKey {
        case id, name, colorIndex, posX, posY, isMe
    }
    init(id: UUID, name: String, colorIndex: Int, mapPosition: CGPoint, isMe: Bool) {
        self.id = id; self.name = name; self.colorIndex = colorIndex
        self.mapPosition = mapPosition; self.isMe = isMe
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self,   forKey: .id)
        name       = try c.decode(String.self, forKey: .name)
        colorIndex = try c.decode(Int.self,    forKey: .colorIndex)
        isMe       = try c.decode(Bool.self,   forKey: .isMe)
        let x      = try c.decode(CGFloat.self, forKey: .posX)
        let y      = try c.decode(CGFloat.self, forKey: .posY)
        mapPosition = CGPoint(x: x, y: y)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,              forKey: .id)
        try c.encode(name,            forKey: .name)
        try c.encode(colorIndex,      forKey: .colorIndex)
        try c.encode(isMe,            forKey: .isMe)
        try c.encode(mapPosition.x,   forKey: .posX)
        try c.encode(mapPosition.y,   forKey: .posY)
    }
}
```

**Step 2: Build to check it compiles**
```bash
cd ~/Documents/Claude\ Code/autoclawd && make all 2>&1 | tail -5
```
Expected: no errors.

**Step 3: Commit**
```bash
git add Sources/Person.swift
git commit -m "feat: add Person model + PersonColor palette"
```

---

### Task 2: Add `people`, `currentSpeakerID`, `locationName` to `AppState`

**Files:**
- Modify: `Sources/AppState.swift`

**Step 1: Add the three published properties after the existing `@Published var appearanceMode` block (around line 69)**

```swift
    // MARK: - People roster & speaker tagging

    @Published var people: [Person] {
        didSet { savePeople() }
    }

    /// Transient — which person is currently speaking (nil = unknown).
    @Published var currentSpeakerID: UUID? = nil

    @Published var locationName: String {
        didSet { UserDefaults.standard.set(locationName, forKey: "autoclawd.locationName") }
    }
```

**Step 2: Add the load/save helpers at the bottom of AppState, before the closing `}`**

```swift
    // MARK: - People persistence

    private static let peopleKey = "autoclawd.people"

    private func loadPeople() -> [Person] {
        guard let data = UserDefaults.standard.data(forKey: Self.peopleKey),
              let people = try? JSONDecoder().decode([Person].self, from: data),
              !people.isEmpty
        else {
            return [Person.makeMe()]
        }
        return people
    }

    private func savePeople() {
        if let data = try? JSONEncoder().encode(people) {
            UserDefaults.standard.set(data, forKey: Self.peopleKey)
        }
    }

    /// Name of the person currently tagged as speaker, or nil.
    var currentSpeakerName: String? {
        guard let id = currentSpeakerID else { return nil }
        return people.first(where: { $0.id == id })?.name
    }

    /// Toggle speaker: tap same person = clear, tap different = set.
    func toggleSpeaker(_ id: UUID) {
        currentSpeakerID = (currentSpeakerID == id) ? nil : id
    }

    /// Add a new person with the next unused color.
    func addPerson(name: String) {
        let usedColors = Set(people.map { $0.colorIndex })
        let nextColor = PersonColor.allCases.first(where: { !usedColors.contains($0.rawValue) })
            ?? PersonColor.allCases[people.count % PersonColor.allCases.count]
        // Simple spiral placement: scatter around centre
        let angle = Double(people.count) * 137.5 * (.pi / 180)
        let r = 0.18 + Double(people.count) * 0.04
        let x = max(0.1, min(0.9, 0.5 + r * cos(angle)))
        let y = max(0.1, min(0.9, 0.5 + r * sin(angle)))
        let p = Person(id: UUID(), name: name, colorIndex: nextColor.rawValue,
                       mapPosition: CGPoint(x: x, y: y), isMe: false)
        people.append(p)
    }
```

**Step 3: Initialise the two new properties in `AppState.init` (find the existing init and add these two lines alongside the other property initializations)**

Look for the `init()` or where other UserDefaults-backed props are loaded, and add:
```swift
self.people       = Self.init_loadPeople()   // see below
self.locationName = UserDefaults.standard.string(forKey: "autoclawd.locationName") ?? "My Room"
```

Because `loadPeople()` uses `self`, use a static helper to allow calling before full init. Replace the `private func loadPeople` with a private static version:

```swift
    private static func init_loadPeople() -> [Person] {
        guard let data = UserDefaults.standard.data(forKey: peopleKey),
              let people = try? JSONDecoder().decode([Person].self, from: data),
              !people.isEmpty
        else { return [Person.makeMe()] }
        return people
    }
    private func savePeople() {
        if let data = try? JSONEncoder().encode(people) {
            UserDefaults.standard.set(data, forKey: Self.peopleKey)
        }
    }
```

And remove the non-static `loadPeople()`.

**Step 4: Build**
```bash
make all 2>&1 | tail -10
```
Expected: no errors.

**Step 5: Commit**
```bash
git add Sources/AppState.swift
git commit -m "feat: add people roster, currentSpeakerID, locationName to AppState"
```

---

### Task 3: Add `speakerName` to `TranscriptStore`

**Files:**
- Modify: `Sources/TranscriptStore.swift`

**Step 1: Add `speakerName` to `TranscriptRecord` struct (around line 6)**
```swift
struct TranscriptRecord: Identifiable {
    let id: Int64
    let timestamp: Date
    let durationSeconds: Int
    let text: String
    let audioFilePath: String
    let sessionID: String?
    let sessionChunkSeq: Int
    var projectID: UUID?
    var speakerName: String?    // ← ADD THIS
}
```

**Step 2: Add migration in `createTables()` — after the existing three `execSQL("ALTER TABLE …")` lines**
```swift
execSQL("ALTER TABLE transcripts ADD COLUMN speaker_name TEXT;")
```
(Safe — silently ignored if column already exists, matching the pattern already used.)

**Step 3: Add `speakerName` param to `save()` public method**

Change:
```swift
func save(text: String, durationSeconds: Int, audioFilePath: String,
          sessionID: String? = nil, sessionChunkSeq: Int = 0,
          projectID: UUID? = nil, timestamp: Date? = nil) {
    queue.async { [weak self] in
        self?.insertTranscript(text: text, duration: durationSeconds, path: audioFilePath,
                               sessionID: sessionID, sessionChunkSeq: sessionChunkSeq,
                               projectID: projectID, timestamp: timestamp)
    }
}
```
To:
```swift
func save(text: String, durationSeconds: Int, audioFilePath: String,
          sessionID: String? = nil, sessionChunkSeq: Int = 0,
          projectID: UUID? = nil, timestamp: Date? = nil,
          speakerName: String? = nil) {
    queue.async { [weak self] in
        self?.insertTranscript(text: text, duration: durationSeconds, path: audioFilePath,
                               sessionID: sessionID, sessionChunkSeq: sessionChunkSeq,
                               projectID: projectID, timestamp: timestamp,
                               speakerName: speakerName)
    }
}
```

**Step 4: Update `insertTranscript` private method signature and body**

Change the signature to add `speakerName: String? = nil`.

Change the SQL insert:
```swift
let sql = """
    INSERT INTO transcripts
        (timestamp, duration_seconds, text, audio_file_path,
         session_id, session_chunk_seq, project_id, speaker_name)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?);
"""
```

Add binding after the project_id binding (currently bind index 7), add:
```swift
if let sn = speakerName {
    sqlite3_bind_text(stmt, 8, sn, -1, SQLITE_TRANSIENT)
} else {
    sqlite3_bind_null(stmt, 8)
}
```

**Step 5: Update all three fetch queries (`ftsSearch`, `fetchRecent`, `fetchBySessionInternal`) to select `speaker_name` and update `runQuery` mapping**

In each SELECT, add `, t.speaker_name` (or just `speaker_name` for fts query). Update `runQuery` to read column 8:
```swift
let speakerName = sqlite3_column_type(stmt, 8) != SQLITE_NULL
    ? String(cString: sqlite3_column_text(stmt, 8))
    : nil
results.append(TranscriptRecord(id: id, timestamp: ts, durationSeconds: dur,
                                text: text, audioFilePath: path,
                                sessionID: sid, sessionChunkSeq: seq,
                                projectID: pid, speakerName: speakerName))
```

**Step 6: Build**
```bash
make all 2>&1 | tail -10
```

**Step 7: Commit**
```bash
git add Sources/TranscriptStore.swift
git commit -m "feat: add speaker_name column to TranscriptStore + migration"
```

---

### Task 4: Wire speaker name through `ChunkManager`

**Files:**
- Modify: `Sources/ChunkManager.swift`

**Step 1: Find the `transcriptStore?.save(...)` call (around line 382) and add `speakerName`**

The `processChunk` function already reads `currentSID` from `MainActor.run`. Add `currentSpeakerName` to that same `MainActor.run` block:

Change:
```swift
let (currentSID, ssid) = await MainActor.run { (self.currentSessionID, self.locationService.currentSSID) }
```
To:
```swift
let (currentSID, ssid, speakerName) = await MainActor.run {
    (self.currentSessionID,
     self.locationService.currentSSID,
     self.appState?.currentSpeakerName)
}
```

Then pass it to save:
```swift
transcriptStore?.save(
    text: transcript,
    durationSeconds: duration,
    audioFilePath: audioURL.path,
    sessionID: currentSID,
    sessionChunkSeq: sessionChunkSeq,
    speakerName: speakerName
)
```

Note: `appState` is already a weak reference on `ChunkManager` — check it exists (`self.appState`). If `appState` property doesn't exist on ChunkManager, check the file for how it's referenced and use the same pattern.

**Step 2: Build**
```bash
make all 2>&1 | tail -10
```

**Step 3: Commit**
```bash
git add Sources/ChunkManager.swift
git commit -m "feat: tag transcript chunks with current speaker name"
```

---

### Task 5: Create `MapEditorView`

**Files:**
- Create: `Sources/MapEditorView.swift`

**Step 1: Create the file**

```swift
// Sources/MapEditorView.swift
import SwiftUI

struct MapEditorView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────
            HStack {
                Text("EDIT ROOM")
                    .font(BrutalistTheme.monoSM)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().opacity(0.2)

            // ── Location name ─────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text("LOCATION")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                TextField("Room name", text: $appState.locationName)
                    .font(BrutalistTheme.monoSM)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().opacity(0.2)

            // ── People list ───────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text("PEOPLE")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach($appState.people) { $person in
                            PersonRowView(person: $person, appState: appState)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(maxHeight: 180)
            }

            Divider().opacity(0.2)

            // ── Add person ────────────────────────────────────────────
            HStack(spacing: 6) {
                TextField("Add person…", text: $newName)
                    .font(BrutalistTheme.monoSM)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)
                    .onSubmit { addPerson() }
                Button(action: addPerson) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(BrutalistTheme.neonGreen)
                }
                .buttonStyle(.plain)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 220)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private func addPerson() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        appState.addPerson(name: trimmed)
        newName = ""
    }
}

// MARK: - PersonRowView

private struct PersonRowView: View {
    @Binding var person: Person
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            // Color swatch
            Circle()
                .fill(person.color)
                .frame(width: 10, height: 10)

            // Name field
            TextField("Name", text: $person.name)
                .font(.system(size: 11, design: .monospaced))
                .textFieldStyle(.plain)

            Spacer()

            // Delete button (not for "You")
            if !person.isMe {
                Button {
                    appState.people.removeAll { $0.id == person.id }
                    if appState.currentSpeakerID == person.id {
                        appState.currentSpeakerID = nil
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color.white.opacity(0.04))
        .cornerRadius(5)
    }
}
```

**Step 2: Build**
```bash
make all 2>&1 | tail -10
```

**Step 3: Commit**
```bash
git add Sources/MapEditorView.swift
git commit -m "feat: add MapEditorView popover for people + location editing"
```

---

### Task 6: Update `AmbientMapView` — live data, tap-to-tag, editor button

**Files:**
- Modify: `Sources/AmbientMapView.swift`

**Step 1: Replace the entire file**

Key changes:
- `AmbientMapView` now takes `@ObservedObject var appState: AppState` instead of static `dots`/`roomName` params
- Tap dot → `appState.toggleSpeaker(dot.id)` (dot id is now the Person UUID)
- `✎` button in top-right opens `MapEditorView` as `.popover`
- `VoiceDot` helper computed from `Person`

```swift
// Sources/AmbientMapView.swift
import SwiftUI

// MARK: - AmbientMapView

struct AmbientMapView: View {
    @ObservedObject var appState: AppState
    @State private var showEditor = false

    private let mapSize: CGFloat = 200

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)

            // Grid
            Canvas { ctx, size in
                for i in 1..<5 {
                    let x = size.width / 5.0 * CGFloat(i)
                    var p = Path(); p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(p, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
                }
                for i in 1..<5 {
                    let y = size.height / 5.0 * CGFloat(i)
                    var p = Path(); p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
                }
            }

            // Room name
            Text(appState.locationName.uppercased())
                .font(BrutalistTheme.monoSM)
                .foregroundColor(.white.opacity(0.35))
                .padding(.top, 8)
                .padding(.leading, 10)

            // Edit button
            Button { showEditor.toggle() } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .popover(isPresented: $showEditor, arrowEdge: .trailing) {
                MapEditorView(appState: appState)
            }

            // Dots
            GeometryReader { geo in
                ForEach(appState.people) { person in
                    let isSpeaking = appState.currentSpeakerID == person.id
                    VoiceDotView(dot: VoiceDot(
                        id: person.id.uuidString,
                        name: person.name,
                        color: person.color,
                        position: person.mapPosition,
                        isSpeaking: isSpeaking,
                        isMe: person.isMe
                    ))
                    .position(
                        x: person.mapPosition.x * geo.size.width,
                        y: person.mapPosition.y * geo.size.height
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            appState.toggleSpeaker(person.id)
                        }
                    }
                }
            }
            .padding(16)

            // Border
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .frame(width: mapSize, height: mapSize)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
```

Keep `VoiceDotView` and `SpeechBubbleView` unchanged below.

**Step 2: Build**
```bash
make all 2>&1 | tail -10
```

**Step 3: Commit**
```bash
git add Sources/AmbientMapView.swift
git commit -m "feat: AmbientMapView reads from AppState, tap-to-tag speaker, editor popover"
```

---

### Task 7: Pass `appState` to `AmbientMapView` in `AppDelegate`

**Files:**
- Modify: `Sources/AppDelegate.swift`

**Step 1: Find the `AmbientMapView()` call in `PillContentView.body` (around line 278)**

Change:
```swift
AmbientMapView()
```
To:
```swift
AmbientMapView(appState: appState)
```

**Step 2: Build**
```bash
make all 2>&1 | tail -10
```

**Step 3: Commit**
```bash
git add Sources/AppDelegate.swift
git commit -m "feat: pass appState to AmbientMapView"
```

---

### Task 8: Show speaker chip in `TranscriptRowView`

**Files:**
- Modify: `Sources/MainPanelView.swift`

**Step 1: In `TranscriptRowView.body`, add a speaker chip just before the transcript text**

Find the `Text(expanded ? record.text : ...)` line and prepend:

```swift
// Speaker chip (shown only when speaker is known)
if let speaker = record.speakerName {
    Text(speaker.uppercased())
        .font(.system(size: 8, weight: .semibold, design: .monospaced))
        .foregroundColor(.black.opacity(0.7))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(BrutalistTheme.neonGreen.opacity(0.75))
        .clipShape(Capsule())
}
```

**Step 2: Build**
```bash
make all 2>&1 | tail -10
```

**Step 3: Commit**
```bash
git add Sources/MainPanelView.swift
git commit -m "feat: show speaker chip on transcript rows"
```

---

### Task 9: Install and smoke-test

**Step 1: Run install.sh**
```bash
~/Documents/Claude\ Code/autoclawd/install.sh
```

**Step 2: Verify**
- Ambient map shows "My Room" label and a single "You" green dot
- Tap the `✎` button → editor popover opens
- Add a person "Alex" → cyan dot appears on map
- Tap "Alex" dot → speech bubble + pulse ring appear, `currentSpeakerID` set
- Tap "Alex" again → clears speaker state
- Say something while a speaker is tagged → check Transcript tab, `[ALEX]` chip appears
- Location name change in editor → map label updates immediately
- Quit and relaunch → people list and location name preserved

**Step 3: Push**
```bash
git push origin main
```
