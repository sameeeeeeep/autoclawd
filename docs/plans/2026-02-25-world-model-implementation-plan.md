# World Model & Intelligence Layer — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extend AutoClawd with session-anchored memory (place, time, people), sentence-aware 10–30s chunk batching, WiFi location, glass appearance modes, global hotkeys, TTS voice output, and a world model timeline canvas.

**Architecture:** SQLite sessions table added to `~/.autoclawd/` alongside existing `transcripts.db`; `LocationService` polls CoreWLAN every 30s; `ChunkManager` switches from fixed 5-min timer to silence-aware 10–30s windows; `SpeechService` wraps AVSpeechSynthesizer trimming replies to ≤10 words.

**Tech Stack:** Swift 5.9, macOS 13+, SQLite3 (already linked), CoreWLAN, AVSpeechSynthesizer, NSEvent global monitors for hotkeys.

**Source directory:** All new files go in `/Users/sameeprehlan/Documents/Claude Code/autoclawd/Sources/`

---

## PHASE 1 — Core Features

---

### Task 1: SessionStore — SQLite schema for sessions, places, people

**Files:**
- Create: `Sources/SessionStore.swift`

**Context:**
Follow the exact same SQLite3 C-API pattern as `TranscriptStore.swift`. The store opens/creates `~/.autoclawd/sessions.db` and adds the tables from the design. `FileStorageManager` already manages `~/.autoclawd/`.

**Step 1: Add `sessionsDatabaseURL` to FileStorageManager**

In `Sources/FileStorageManager.swift`, after the `intelligenceDatabaseURL` computed property, add:

```swift
var sessionsDatabaseURL: URL {
    rootDirectory.appendingPathComponent("sessions.db")
}
```

**Step 2: Create `Sources/SessionStore.swift`**

```swift
import Foundation
import SQLite3

// MARK: - Models

struct SessionRecord: Identifiable {
    let id: String           // UUID
    let startedAt: Date
    let endedAt: Date?
    let wifiSSID: String?
    let placeID: String?
    let placeName: String?   // joined from places table
    let transcriptSnippet: String  // first 120 chars for canvas card
}

struct PlaceRecord: Identifiable {
    let id: String
    let wifiSSID: String
    let name: String
}

// MARK: - SessionStore

final class SessionStore: @unchecked Sendable {
    static let shared = SessionStore(url: FileStorageManager.shared.sessionsDatabaseURL)

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.autoclawd.sessionstore", qos: .utility)

    init(url: URL) {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            Log.error(.system, "SessionStore: failed to open \(url.lastPathComponent)")
            return
        }
        createTables()
        Log.info(.system, "SessionStore opened at \(url.lastPathComponent)")
    }

    deinit { sqlite3_close(db) }

    // MARK: - Session CRUD

    /// Create a new session row, returns the new session UUID.
    @discardableResult
    func beginSession(wifiSSID: String?) -> String {
        let id = UUID().uuidString
        let now = ISO8601DateFormatter().string(from: Date())
        let sql = """
            INSERT INTO sessions (id, started_at, wifi_ssid)
            VALUES (?, ?, ?);
        """
        execBind(sql, args: [id, now, wifiSSID ?? ""])
        Log.info(.system, "Session started: \(id)")
        return id
    }

    func endSession(id: String, transcriptSnippet: String) {
        let now = ISO8601DateFormatter().string(from: Date())
        let sql = """
            UPDATE sessions SET ended_at = ?, transcript_snippet = ?
            WHERE id = ?;
        """
        execBind(sql, args: [now, transcriptSnippet, id])
    }

    func updateSessionPlace(id: String, placeID: String) {
        execBind("UPDATE sessions SET place_id = ? WHERE id = ?;", args: [placeID, id])
    }

    // MARK: - Place CRUD

    func findPlace(wifiSSID: String) -> PlaceRecord? {
        let sql = "SELECT id, wifi_ssid, name FROM places WHERE wifi_ssid = ? LIMIT 1;"
        return queue.sync { queryPlaces(sql, args: [wifiSSID]).first }
    }

    @discardableResult
    func createPlace(wifiSSID: String, name: String) -> String {
        let id = UUID().uuidString
        let now = ISO8601DateFormatter().string(from: Date())
        execBind("INSERT INTO places (id, wifi_ssid, name, created_at) VALUES (?, ?, ?, ?);",
                 args: [id, wifiSSID, name, now])
        return id
    }

    // MARK: - Recent Sessions

    func recentSessions(limit: Int = 50) -> [SessionRecord] {
        let sql = """
            SELECT s.id, s.started_at, s.ended_at, s.wifi_ssid,
                   s.place_id, p.name, s.transcript_snippet
            FROM sessions s
            LEFT JOIN places p ON s.place_id = p.id
            ORDER BY s.started_at DESC
            LIMIT ?;
        """
        return queue.sync { querySessions(sql, args: [String(limit)]) }
    }

    // MARK: - User Profile (singleton row)

    func userContextBlob() -> String? {
        let sql = "SELECT context_blob FROM user_profile WHERE id = 1;"
        var result: String?
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW,
               let raw = sqlite3_column_text(stmt, 0) {
                result = String(cString: raw)
            }
        }
        return result
    }

    func saveUserContextBlob(_ blob: String) {
        let now = ISO8601DateFormatter().string(from: Date())
        let sql = """
            INSERT INTO user_profile (id, context_blob, updated_at)
            VALUES (1, ?, ?)
            ON CONFLICT(id) DO UPDATE SET context_blob = excluded.context_blob,
                                          updated_at = excluded.updated_at;
        """
        execBind(sql, args: [blob, now])
    }

    // MARK: - Schema

    private func createTables() {
        execSQL("""
            CREATE TABLE IF NOT EXISTS sessions (
                id               TEXT PRIMARY KEY,
                started_at       TEXT NOT NULL,
                ended_at         TEXT,
                wifi_ssid        TEXT,
                place_id         TEXT,
                transcript_snippet TEXT NOT NULL DEFAULT ''
            );
        """)
        execSQL("""
            CREATE TABLE IF NOT EXISTS places (
                id         TEXT PRIMARY KEY,
                wifi_ssid  TEXT UNIQUE NOT NULL,
                name       TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
        """)
        execSQL("""
            CREATE TABLE IF NOT EXISTS user_profile (
                id           INTEGER PRIMARY KEY CHECK (id = 1),
                context_blob TEXT,
                updated_at   TEXT
            );
        """)
    }

    // MARK: - Helpers

    private func execBind(_ sql: String, args: [String]) {
        queue.async { [weak self] in
            guard let self else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            for (i, arg) in args.enumerated() {
                sqlite3_bind_text(stmt, Int32(i + 1), arg, -1, SQLITE_TRANSIENT)
            }
            sqlite3_step(stmt)
        }
    }

    private func execSQL(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, sql, nil, nil, &err)
        if let e = err { Log.error(.system, "SessionStore SQL error: \(String(cString: e))") }
    }

    private func queryPlaces(_ sql: String, args: [String]) -> [PlaceRecord] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i, arg) in args.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), arg, -1, SQLITE_TRANSIENT)
        }
        var results: [PlaceRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id   = String(cString: sqlite3_column_text(stmt, 0))
            let ssid = String(cString: sqlite3_column_text(stmt, 1))
            let name = String(cString: sqlite3_column_text(stmt, 2))
            results.append(PlaceRecord(id: id, wifiSSID: ssid, name: name))
        }
        return results
    }

    private func querySessions(_ sql: String, args: [String]) -> [SessionRecord] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i, arg) in args.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), arg, -1, SQLITE_TRANSIENT)
        }
        var results: [SessionRecord] = []
        let iso = ISO8601DateFormatter()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id        = String(cString: sqlite3_column_text(stmt, 0))
            let startStr  = String(cString: sqlite3_column_text(stmt, 1))
            let endRaw    = sqlite3_column_text(stmt, 2)
            let ssidRaw   = sqlite3_column_text(stmt, 3)
            let placeRaw  = sqlite3_column_text(stmt, 4)
            let nameRaw   = sqlite3_column_text(stmt, 5)
            let snippet   = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
            results.append(SessionRecord(
                id: id,
                startedAt: iso.date(from: startStr) ?? Date(),
                endedAt: endRaw.flatMap { iso.date(from: String(cString: $0)) },
                wifiSSID: ssidRaw.map { String(cString: $0) },
                placeID: placeRaw.map { String(cString: $0) },
                placeName: nameRaw.map { String(cString: $0) },
                transcriptSnippet: snippet
            ))
        }
        return results
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
```

**Step 3: Build and verify no compile errors**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

**Step 4: Commit**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
git add Sources/SessionStore.swift Sources/FileStorageManager.swift
git commit -m "feat: add SessionStore with sessions/places/user_profile tables"
```

---

### Task 2: LocationService — WiFi SSID → named place

**Files:**
- Create: `Sources/LocationService.swift`
- Modify: `Sources/AppState.swift`
- Modify: `AutoClawd.entitlements`

**Context:**
On macOS, `CWWiFiClient.shared().interface()?.ssid()` from CoreWLAN gives the current SSID — no special entitlement needed for development builds. Poll every 30s. When a new SSID is seen, call back with the SSID so `AppState` can prompt the user to label it.

**Step 1: Add CoreWLAN import and create `Sources/LocationService.swift`**

```swift
import CoreWLAN
import Foundation

@MainActor
final class LocationService: ObservableObject {
    static let shared = LocationService()

    @Published private(set) var currentSSID: String?
    @Published private(set) var currentPlaceName: String?

    /// Called when an unrecognised SSID is first seen. Arg = raw SSID.
    var onUnknownSSID: ((String) -> Void)?

    private let store = SessionStore.shared
    private var pollTimer: Timer?
    private var knownSSIDs: Set<String> = []

    private init() {}

    func start() {
        pollOnce()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollOnce() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func labelCurrentSSID(_ name: String) {
        guard let ssid = currentSSID else { return }
        store.createPlace(wifiSSID: ssid, name: name)
        currentPlaceName = name
        knownSSIDs.insert(ssid)
        Log.info(.system, "Labeled '\(ssid)' as '\(name)'")
    }

    // MARK: - Private

    private func pollOnce() {
        let ssid = CWWiFiClient.shared().interface()?.ssid()
        let resolved = ssid ?? "Mobile"   // nil = no WiFi = on hotspot or offline

        guard resolved != currentSSID else { return }
        currentSSID = resolved

        if let place = store.findPlace(wifiSSID: resolved) {
            currentPlaceName = place.name
        } else if resolved == "Mobile" || resolved.lowercased().contains("iphone") {
            // Auto-label hotspot
            store.createPlace(wifiSSID: resolved, name: "Mobile")
            currentPlaceName = "Mobile"
        } else if !knownSSIDs.contains(resolved) {
            knownSSIDs.insert(resolved)
            onUnknownSSID?(resolved)   // prompt user
        }
    }
}
```

**Step 2: Add `locationService` to `AppState` and start it in `applicationDidFinishLaunching`**

In `Sources/AppState.swift`:

Add property:
```swift
let locationService = LocationService.shared
```

In `applicationDidFinishLaunching()`, add after `ClipboardMonitor.shared.start()`:
```swift
locationService.start()
locationService.onUnknownSSID = { [weak self] ssid in
    self?.pendingUnknownSSID = ssid
    // Toast prompt handled in MainPanelView
}
```

Add published property:
```swift
@Published var pendingUnknownSSID: String? = nil
```

**Step 3: Build**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
swift build 2>&1 | grep -E "error:|Build complete"
```

**Step 4: Add entitlement for CoreWLAN (access SSID)**

In `AutoClawd.entitlements`, add inside `<dict>`:
```xml
<key>com.apple.developer.networking.wifi-info</key>
<true/>
```

**Step 5: Commit**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
git add Sources/LocationService.swift Sources/AppState.swift AutoClawd.entitlements
git commit -m "feat: add LocationService with CoreWLAN SSID polling and place labeling"
```

---

### Task 3: Session lifecycle — begin/end session around chunk cycles

**Files:**
- Modify: `Sources/ChunkManager.swift`
- Modify: `Sources/AppState.swift`

**Context:**
A "session" = one continuous listening period (start→stop). When `startListening()` is called, begin a session row. When `stopListening()` or `pause()` is called, end the session with the transcript snippet.

**Step 1: Add session tracking to ChunkManager**

At the top of `ChunkManager`, add:
```swift
private var currentSessionID: String?
private let sessionStore = SessionStore.shared
private let locationService = LocationService.shared
```

In `startListening()`, after `beginChunkCycle()`:
```swift
let ssid = await MainActor.run { locationService.currentSSID }
currentSessionID = sessionStore.beginSession(wifiSSID: ssid)
```

In `stopListening()`, before `state = .stopped`:
```swift
if let sid = currentSessionID {
    let snippet = latestTranscriptSnippet()
    sessionStore.endSession(id: sid, transcriptSnippet: snippet)
    currentSessionID = nil
}
```

Add helper:
```swift
private var _transcriptBuffer: [String] = []  // accumulate chunk transcripts

private func latestTranscriptSnippet() -> String {
    let combined = _transcriptBuffer.suffix(3).joined(separator: " ")
    return String(combined.prefix(120))
}
```

In `processChunk(...)`, after saving transcript, append:
```swift
await MainActor.run { self._transcriptBuffer.append(transcript) }

// Update place_id if we now know location
if let sid = self.currentSessionID,
   let placeID = await MainActor.run(body: { LocationService.shared.currentSSID })
       .flatMap({ SessionStore.shared.findPlace(wifiSSID: $0)?.id }) {
    SessionStore.shared.updateSessionPlace(id: sid, placeID: placeID)
}
```

**Step 2: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

**Step 3: Commit**

```bash
git add Sources/ChunkManager.swift Sources/AppState.swift
git commit -m "feat: track session lifecycle with SessionStore in ChunkManager"
```

---

### Task 4: Sentence-aware 10–30s chunk batching

**Files:**
- Modify: `Sources/AudioRecorder.swift`
- Modify: `Sources/ChunkManager.swift`

**Context:**
Currently `runOneChunk()` sleeps for `chunkDuration` (5 min). Replace with a polling loop that watches `audioRecorder.audioLevel` for silence, flushes at ≥10s+silence, force-flushes at 30s.

**Step 1: Add `isSilentNow` to AudioRecorder**

In `Sources/AudioRecorder.swift`, in the `AudioRecorder` class, add a property:
```swift
/// True if the most recent audio buffer was below the silence threshold.
private(set) var isSilentNow: Bool = false
```

In the `installTap` callback, inside the buffer handler, after computing `rms`:
```swift
self.isSilentNow = rms < self.silenceThreshold
```

**Step 2: Replace `runOneChunk()` timer with silence-aware loop**

In `Sources/ChunkManager.swift`, change the `init` default:
```swift
init(chunkDuration: TimeInterval = 30) {   // was 300
```

Replace `runOneChunk()` body — the new version polls every 0.25s:
```swift
private let minChunkSeconds: TimeInterval = 10
private let maxChunkSeconds: TimeInterval = 30
private let silenceGapSeconds: TimeInterval = 0.8

private func runOneChunk() async {
    let index = chunkIndex
    chunkIndex += 1
    let fileURL = storage.audioFile(date: Date())

    do {
        try audioRecorder.startRecording(outputURL: fileURL)
    } catch {
        Log.error(.audio, "Failed to start recording chunk \(index): \(error)")
        try? await Task.sleep(for: .seconds(5))
        return
    }

    state = .listening(chunkIndex: index)
    chunkStartTime = Date()

    var silenceStart: Date? = nil
    var elapsed: TimeInterval = 0

    // Poll loop — check every 0.25s
    while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(250))
        elapsed = Date().timeIntervalSince(chunkStartTime ?? Date())

        let silent = audioRecorder.isSilentNow

        if silent {
            if silenceStart == nil { silenceStart = Date() }
        } else {
            silenceStart = nil
        }

        let silenceDuration = silenceStart.map { Date().timeIntervalSince($0) } ?? 0

        let shouldFlushForSilence = elapsed >= minChunkSeconds && silenceDuration >= silenceGapSeconds
        let shouldForceFlush = elapsed >= maxChunkSeconds

        if shouldFlushForSilence || shouldForceFlush {
            let reason = shouldForceFlush ? "force(30s)" : "silence(\(String(format:"%.1f",elapsed))s)"
            Log.info(.audio, "Chunk \(index): flushing — \(reason)")
            break
        }
    }

    let silenceRatio = audioRecorder.silenceRatio
    let duration = Int(elapsed)
    guard let savedURL = audioRecorder.stopRecording() else { return }

    if silenceRatio > 0.90 || duration < 2 {
        Log.info(.audio, "Chunk \(index) skipped: \(Int(silenceRatio*100))% silence")
        return
    }

    // Background process (same as before)
    let capturedIndex = index
    let capturedTranscriptionService = transcriptionService
    let capturedExtractionService = extractionService
    let capturedTranscriptStore = transcriptStore
    let capturedPillMode = pillMode
    let capturedPasteService = pasteService
    let capturedQAService = qaService
    let capturedQAStore = qaStore

    Task.detached { [weak self] in
        await self?.processChunk(
            index: capturedIndex, audioURL: savedURL, duration: duration,
            transcriptionService: capturedTranscriptionService,
            extractionService: capturedExtractionService,
            transcriptStore: capturedTranscriptStore,
            pillMode: capturedPillMode,
            pasteService: capturedPasteService,
            qaService: capturedQAService,
            qaStore: capturedQAStore
        )
    }
}
```

**Step 3: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

**Step 4: Commit**

```bash
git add Sources/AudioRecorder.swift Sources/ChunkManager.swift
git commit -m "feat: sentence-aware 10-30s chunk batching with silence detection"
```

---

### Task 5: Context injection — user profile + session context into intelligence

**Files:**
- Modify: `Sources/ExtractionService.swift`
- Modify: `Sources/QAService.swift`

**Context:**
Both `ExtractionService` (ambient mode) and `QAService` (AI Search mode) make LLM calls. Prepend the context block — user profile blob + current location + last 3 session snippets — to their system prompts.

**Step 1: Create a `ContextBlock` helper (add to SessionStore.swift)**

At the bottom of `Sources/SessionStore.swift`, add:

```swift
// MARK: - Context Block Builder

extension SessionStore {
    /// Builds the context preamble injected into every LLM system prompt.
    func buildContextBlock(currentSSID: String?) -> String {
        var lines: [String] = []

        // User profile
        if let blob = userContextBlob(), !blob.isEmpty {
            lines.append("[USER CONTEXT]\n\(blob)")
        }

        // Current session location
        let place: String
        if let ssid = currentSSID, let p = findPlace(wifiSSID: ssid) {
            place = p.name
        } else {
            place = "Unknown"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM, h:mma"
        let timeStr = formatter.string(from: Date())
        lines.append("[CURRENT SESSION]\nLocation: \(place) | Time: \(timeStr)")

        // Last 3 sessions
        let recent = recentSessions(limit: 3)
        if !recent.isEmpty {
            let sessionSummaries = recent.map { s -> String in
                let df = DateFormatter()
                df.dateFormat = "EEE"
                let day = df.string(from: s.startedAt)
                let loc = s.placeName ?? "Unknown"
                let snippet = s.transcriptSnippet.isEmpty ? "(no transcript)" : s.transcriptSnippet
                return "\(day) at \(loc) — \(snippet)"
            }.joined(separator: "\n")
            lines.append("[RECENT SESSIONS]\n\(sessionSummaries)")
        }

        return lines.joined(separator: "\n\n")
    }
}
```

**Step 2: Read ExtractionService system prompt injection point**

```bash
grep -n "system\|prompt\|messages" \
  "/Users/sameeprehlan/Documents/Claude Code/autoclawd/Sources/ExtractionService.swift" | head -30
```

Note the line numbers where the system prompt is constructed.

**Step 3: Inject context block into ExtractionService**

Find the `classifyChunk` or `synthesize` method that builds the LLM messages array. Before the existing system prompt string, prepend:

```swift
let contextBlock = SessionStore.shared.buildContextBlock(
    currentSSID: LocationService.shared.currentSSID
)
let systemPrompt = contextBlock.isEmpty
    ? existingSystemPrompt
    : "\(contextBlock)\n\n---\n\n\(existingSystemPrompt)"
```

**Step 4: Inject context block into QAService**

Open `Sources/QAService.swift`, find the `answer(question:)` method, and apply the same pattern as Step 3.

**Step 5: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

**Step 6: Commit**

```bash
git add Sources/SessionStore.swift Sources/ExtractionService.swift Sources/QAService.swift
git commit -m "feat: inject user profile + session context into LLM system prompts"
```

---

### Task 6: Glass appearance modes — frosted / transparent pill

**Files:**
- Modify: `Sources/SettingsManager.swift`
- Modify: `Sources/PillWindow.swift`
- Modify: `Sources/PillView.swift`

**Context:**
`PillWindow` is an `NSPanel`. Its background material comes from an `NSVisualEffectView`. Add an `AppearanceMode` enum and wire it so the pill window swaps material. The pill also pulses opacity during recording/processing regardless of base mode.

**Step 1: Add AppearanceMode to SettingsManager**

In `Sources/SettingsManager.swift`:

Add after the `TranscriptionMode` enum:
```swift
enum AppearanceMode: String, CaseIterable {
    case frosted     = "frosted"
    case transparent = "transparent"

    var displayName: String {
        switch self {
        case .frosted:     return "Frosted"
        case .transparent: return "Transparent"
        }
    }
}
```

Add key and property to `SettingsManager`:
```swift
private let kAppearanceMode = "appearance_mode"

var appearanceMode: AppearanceMode {
    get {
        let raw = defaults.string(forKey: kAppearanceMode) ?? AppearanceMode.frosted.rawValue
        return AppearanceMode(rawValue: raw) ?? .frosted
    }
    set { defaults.set(newValue.rawValue, forKey: kAppearanceMode) }
}
```

**Step 2: Add `appearanceMode` to AppState**

In `Sources/AppState.swift`:

```swift
@Published var appearanceMode: AppearanceMode {
    didSet { SettingsManager.shared.appearanceMode = appearanceMode }
}
```

In `init()`:
```swift
appearanceMode = settings.appearanceMode
```

**Step 3: Read PillWindow to find NSVisualEffectView setup**

```bash
grep -n "NSVisualEffectView\|material\|blending\|background" \
  "/Users/sameeprehlan/Documents/Claude Code/autoclawd/Sources/PillWindow.swift"
```

**Step 4: Apply material based on appearanceMode in PillWindow**

Find where the `NSVisualEffectView` is configured. Add a method `applyAppearanceMode(_ mode: AppearanceMode)`:

```swift
func applyAppearanceMode(_ mode: AppearanceMode) {
    guard let effectView = contentView?.subviews
        .first(where: { $0 is NSVisualEffectView }) as? NSVisualEffectView
    else { return }

    switch mode {
    case .frosted:
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
    case .transparent:
        effectView.material = .underWindowBackground
        effectView.blendingMode = .behindWindow
        effectView.alphaValue = 0.6
    }
}
```

Call this whenever `appState.appearanceMode` changes — observe via `NotificationCenter` or pass the mode at creation time.

**Step 5: Add state-reactive opacity pulse to PillView**

In `Sources/PillView.swift`, find `pillBackground` or the outermost container. Add a pulse animation:

```swift
// In PillView, add:
@State private var pulseOpacity: Double = 1.0

private var pillOpacity: Double {
    switch state {
    case .processing: return pulseOpacity          // animate 0.4–0.8
    case .listening:  return pulseOpacity          // animate 0.6–1.0
    default:          return 1.0
    }
}

// In .onAppear or as a modifier on fullPillView:
.opacity(pillOpacity)
.onAppear { startPulse() }
.onChange(of: state) { _ in startPulse() }

private func startPulse() {
    switch state {
    case .processing:
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulseOpacity = 0.4
        }
    case .listening:
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulseOpacity = 0.6
        }
    default:
        withAnimation(.easeInOut(duration: 0.2)) { pulseOpacity = 1.0 }
    }
}
```

**Step 6: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

**Step 7: Commit**

```bash
git add Sources/SettingsManager.swift Sources/AppState.swift Sources/PillWindow.swift Sources/PillView.swift
git commit -m "feat: add frosted/transparent glass appearance modes with state-reactive pulse"
```

---

### Task 7: Global hotkeys — ⌃Space and ⌃R

**Files:**
- Create: `Sources/GlobalHotkeyMonitor.swift`
- Modify: `Sources/AppState.swift`
- Modify: `Sources/App.swift`

**Context:**
No hotkey system exists in the current `Sources/` codebase. Use `NSEvent.addGlobalMonitorForEvents` — no Accessibility permission required for key monitoring (only for key posting). `⌃Space` = flush current chunk (transcribe now). `⌃R` = toggle mic.

**Step 1: Create `Sources/GlobalHotkeyMonitor.swift`**

```swift
import AppKit

final class GlobalHotkeyMonitor {
    static let shared = GlobalHotkeyMonitor()

    var onTranscribeNow: (() -> Void)?  // ⌃Space
    var onToggleMic: (() -> Void)?       // ⌃R

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private init() {}

    func start() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            let ctrl = event.modifierFlags.contains(.control)
            let noOtherMods = !event.modifierFlags.contains(.option) &&
                              !event.modifierFlags.contains(.command) &&
                              !event.modifierFlags.contains(.shift)
            guard ctrl && noOtherMods else { return }

            switch event.keyCode {
            case 49:  // Space
                self?.onTranscribeNow?()
            case 15:  // R
                self?.onToggleMic?()
            default:
                break
            }
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
        localMonitor  = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event)
            return event
        }
        Log.info(.system, "GlobalHotkeyMonitor started (⌃Space, ⌃R)")
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor  { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor  = nil
    }
}
```

**Step 2: Wire up in AppState**

In `Sources/AppState.swift`, add to `applicationDidFinishLaunching()`:

```swift
let hotkeys = GlobalHotkeyMonitor.shared
hotkeys.onTranscribeNow = { [weak self] in
    Task { @MainActor in self?.chunkManager.pause() }  // flush + process current chunk
}
hotkeys.onToggleMic = { [weak self] in
    Task { @MainActor in self?.toggleListening() }
}
hotkeys.start()
```

**Step 3: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

**Step 4: Commit**

```bash
git add Sources/GlobalHotkeyMonitor.swift Sources/AppState.swift
git commit -m "feat: add global hotkeys ⌃Space (flush chunk) and ⌃R (toggle mic)"
```

---

### Task 8: SpeechService — AVSpeechSynthesizer TTS, ≤10 words

**Files:**
- Create: `Sources/SpeechService.swift`
- Modify: `Sources/ExtractionService.swift` (ambient mode responses)
- Modify: `Sources/QAService.swift` (AI search answers)

**Context:**
`AVSpeechSynthesizer` is part of `AVFoundation`. Trim the response to ≤10 words before speaking. Wire it so ambient intelligence summaries and Q&A answers are spoken aloud.

**Step 1: Create `Sources/SpeechService.swift`**

```swift
import AVFoundation
import Foundation

final class SpeechService: @unchecked Sendable {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()
    private let voiceID = "com.apple.voice.compact.en-US.Samantha"
    private let maxWords = 10

    private init() {}

    /// Speak up to the first `maxWords` words of `text`.
    func speak(_ text: String) {
        let words = text.split(separator: " ").prefix(maxWords)
        guard !words.isEmpty else { return }
        var trimmed = words.joined(separator: " ")

        // Clean up trailing incomplete sentence — remove trailing non-punctuation
        if let last = trimmed.last, !".,!?".contains(last) {
            // Acceptable as-is — it's a natural truncation
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceID)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52   // slightly faster than default
        utterance.volume = 0.9

        DispatchQueue.main.async { [weak self] in
            self?.synthesizer.stopSpeaking(at: .immediate)
            self?.synthesizer.speak(utterance)
        }
        Log.info(.system, "TTS: \"\(trimmed)\"")
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
```

**Step 2: Call SpeechService after ambient intelligence response**

Open `Sources/ExtractionService.swift`. Find where extracted items are returned or logged after the LLM call. After a successful synthesis or extraction, add:

```swift
// Speak a brief summary (first action item or title)
if let firstItem = items.first {
    SpeechService.shared.speak(firstItem.title)
}
```

**Step 3: Call SpeechService after Q&A answer**

In `Sources/QAService.swift`, in the `answer(question:)` method, after the LLM returns `answer`:

```swift
SpeechService.shared.speak(answer)
```

**Step 4: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

**Step 5: Commit**

```bash
git add Sources/SpeechService.swift Sources/ExtractionService.swift Sources/QAService.swift
git commit -m "feat: add SpeechService TTS - speak ≤10 word summaries after responses"
```

---

### Task 9: Session Timeline View — world model canvas Phase 1

**Files:**
- Create: `Sources/SessionTimelineView.swift`
- Modify: `Sources/MainPanelView.swift` (add tab or section)

**Context:**
The existing `WorldModelGraphView.swift` shows a graph. Add a `SessionTimelineView` that shows a vertical list of session cards sourced from `SessionStore`. Each card shows: place, time, people placeholder, first line of transcript.

**Step 1: Create `Sources/SessionTimelineView.swift`**

```swift
import SwiftUI

struct SessionTimelineView: View {
    @State private var sessions: [SessionRecord] = []
    @State private var expandedID: String? = nil

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(sessions) { session in
                    SessionCard(
                        session: session,
                        isExpanded: expandedID == session.id,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedID = expandedID == session.id ? nil : session.id
                            }
                        }
                    )
                }
            }
            .padding(16)
        }
        .onAppear { reload() }
    }

    private func reload() {
        sessions = SessionStore.shared.recentSessions(limit: 50)
    }
}

// MARK: - Session Card

struct SessionCard: View {
    let session: SessionRecord
    let isExpanded: Bool
    let onTap: () -> Void

    private var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM · h:mma"
        return f.string(from: session.startedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.placeName ?? "Unknown location")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(BrutalistTheme.neonGreen)

                    Text(timeLabel)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.white.opacity(0.3))
                    .font(.system(size: 10))
            }

            if !session.transcriptSnippet.isEmpty {
                Text(session.transcriptSnippet)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(isExpanded ? nil : 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(BrutalistTheme.neonGreen.opacity(0.15), lineWidth: 1)
                )
        )
        .onTapGesture { onTap() }
    }
}
```

**Step 2: Find where to add SessionTimelineView in MainPanelView**

```bash
grep -n "Tab\|tab\|WorldModel\|world" \
  "/Users/sameeprehlan/Documents/Claude Code/autoclawd/Sources/MainPanelView.swift" | head -20
```

**Step 3: Add Timeline tab to MainPanelView**

Find the tab bar or navigation in `MainPanelView.swift`. Add a "Timeline" tab that renders `SessionTimelineView()`. Follow the exact same pattern as existing tabs (e.g., the world model or QA tab).

**Step 4: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

**Step 5: Commit**

```bash
git add Sources/SessionTimelineView.swift Sources/MainPanelView.swift
git commit -m "feat: add session timeline canvas view to main panel"
```

---

### Task 10: WiFi place labeling toast prompt

**Files:**
- Modify: `Sources/MainPanelView.swift` or `Sources/ToastView.swift`

**Context:**
When `LocationService` fires `onUnknownSSID`, `AppState` sets `pendingUnknownSSID`. Show a small prompt in the UI: *"You're on 'BlueBotWifi' — what should I call this place?"* with a text field and confirm button.

**Step 1: Add `wifiLabelInput` state to AppState**

```swift
@Published var wifiLabelInput: String = ""

func confirmWifiLabel() {
    guard let ssid = pendingUnknownSSID, !wifiLabelInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    locationService.labelCurrentSSID(wifiLabelInput)
    pendingUnknownSSID = nil
    wifiLabelInput = ""
}
```

**Step 2: Add inline prompt to MainPanelView**

In the panel body, add conditionally (when `appState.pendingUnknownSSID != nil`):

```swift
if let ssid = appState.pendingUnknownSSID {
    VStack(alignment: .leading, spacing: 6) {
        Text("You're on '\(ssid)' — what should I call this place?")
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(BrutalistTheme.neonGreen)

        HStack {
            TextField("e.g. Philz Coffee", text: $appState.wifiLabelInput)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))

            Button("Save") { appState.confirmWifiLabel() }
                .buttonStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(BrutalistTheme.neonGreen)
        }
    }
    .padding(10)
    .background(Color.white.opacity(0.04))
}
```

**Step 3: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

**Step 4: Commit**

```bash
git add Sources/AppState.swift Sources/MainPanelView.swift
git commit -m "feat: add WiFi place labeling prompt in main panel"
```

---

## PHASE 2 — World Model Depth

---

### Task 11: User Profile Chat — conversational context builder

**Files:**
- Create: `Sources/UserProfileChatView.swift`
- Create: `Sources/UserProfileService.swift`
- Modify: `Sources/MainPanelView.swift` (add Profile tab)

**Context:**
A chat UI in Settings where the user types free-form context. The LLM asks up to 3 follow-up questions, then synthesises a `context_blob` saved to `user_profile` in SQLite via `SessionStore`.

**Step 1: Create `Sources/UserProfileService.swift`**

```swift
import Foundation

final class UserProfileService: @unchecked Sendable {
    private let sessionStore = SessionStore.shared
    private var conversationTurns: [(role: String, content: String)] = []
    private let maxFollowUps = 3
    private var followUpCount = 0

    var apiKey: String = ""
    var baseURL: String = "https://api.groq.com/openai/v1"
    let model = "meta-llama/llama-4-scout-17b-16e-instruct"

    /// Start or reset the profile chat. Returns the opening question.
    func startChat() -> String {
        conversationTurns = []
        followUpCount = 0
        return "Tell me about yourself — what do you do, where do you work, and who do you work with most?"
    }

    /// Submit a user message. Returns the assistant reply (follow-up question or final summary cue).
    func submitMessage(_ message: String) async throws -> (reply: String, isDone: Bool) {
        conversationTurns.append((role: "user", content: message))

        if followUpCount >= maxFollowUps {
            let blob = try await synthesiseBlob()
            sessionStore.saveUserContextBlob(blob)
            return ("Got it — your context is saved.", true)
        }

        let reply = try await callLLM(followingUp: followUpCount < maxFollowUps)
        conversationTurns.append((role: "assistant", content: reply))
        followUpCount += 1
        return (reply, false)
    }

    // MARK: - Private

    private func callLLM(followingUp: Bool) async throws -> String {
        let systemPrompt = followingUp
            ? """
              You are building a compact personal context profile.
              Ask ONE short follow-up question to learn more about the user.
              Focus on role, workplace, projects, or frequent collaborators.
              Keep question under 15 words.
              """
            : """
              Summarise what you know about the user in a compact paragraph (max 200 words).
              """

        var messages: [[String: String]] = [["role": "system", "content": systemPrompt]]
        messages += conversationTurns.map { ["role": $0.role, "content": $0.content] }

        return try await callGroq(messages: messages)
    }

    private func synthesiseBlob() async throws -> String {
        let conversation = conversationTurns
            .map { "\($0.role): \($0.content)" }
            .joined(separator: "\n")

        let systemPrompt = """
            Synthesise the following conversation into a compact personal context profile (max 300 words).
            Write in third-person present tense. Include: name, role, workplace, key collaborators, current projects.
            """
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": conversation]
        ]
        return try await callGroq(messages: messages)
    }

    private func callGroq(messages: [[String: String]]) async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["model": model, "messages": messages, "max_tokens": 400]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String
        else { throw URLError(.badServerResponse) }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

**Step 2: Create `Sources/UserProfileChatView.swift`**

```swift
import SwiftUI

struct UserProfileChatView: View {
    @EnvironmentObject var appState: AppState

    @State private var messages: [(role: String, text: String)] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var isDone = false
    private let service = UserProfileService()

    var body: some View {
        VStack(spacing: 0) {
            // Chat history
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                            ChatBubble(role: msg.role, text: msg.text)
                                .id(msg.offset)
                        }
                        if isLoading {
                            ChatBubble(role: "assistant", text: "…")
                        }
                    }
                    .padding(12)
                }
                .onChange(of: messages.count) { _ in
                    proxy.scrollTo(messages.count - 1)
                }
            }

            Divider()

            // Input
            HStack {
                TextField("Type here…", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .disabled(isLoading || isDone)
                    .onSubmit { sendMessage() }

                Button(isDone ? "Done" : "Send") { sendMessage() }
                    .buttonStyle(.plain)
                    .foregroundColor(BrutalistTheme.neonGreen)
                    .disabled(inputText.isEmpty || isLoading)
            }
            .padding(10)
        }
        .onAppear { startChat() }
    }

    private func startChat() {
        service.apiKey = appState.groqAPIKey
        let opening = service.startChat()
        messages = [("assistant", opening)]
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        messages.append(("user", text))
        inputText = ""
        isLoading = true
        Task {
            do {
                let (reply, done) = try await service.submitMessage(text)
                await MainActor.run {
                    messages.append(("assistant", reply))
                    isLoading = false
                    isDone = done
                }
            } catch {
                await MainActor.run {
                    messages.append(("assistant", "Error: \(error.localizedDescription)"))
                    isLoading = false
                }
            }
        }
    }
}

struct ChatBubble: View {
    let role: String
    let text: String

    var body: some View {
        HStack {
            if role == "user" { Spacer() }
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .padding(8)
                .background(role == "user"
                    ? BrutalistTheme.neonGreen.opacity(0.15)
                    : Color.white.opacity(0.05))
                .cornerRadius(6)
                .foregroundColor(.white.opacity(0.9))
            if role == "assistant" { Spacer() }
        }
    }
}
```

**Step 3: Add Profile tab to MainPanelView**

Following the same tab pattern used for other views, add a "Profile" tab rendering `UserProfileChatView()`.

**Step 4: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

**Step 5: Commit**

```bash
git add Sources/UserProfileChatView.swift Sources/UserProfileService.swift Sources/MainPanelView.swift
git commit -m "feat: add user profile chat for building context blob"
```

---

### Task 12: People tagging — post-session LLM name extraction

**Files:**
- Create: `Sources/PeopleTaggingService.swift`
- Modify: `Sources/SessionStore.swift` (add people/session_people tables)
- Modify: `Sources/ChunkManager.swift` (call after session ends)

**Step 1: Add people tables to SessionStore schema**

In `SessionStore.createTables()`, add:

```swift
execSQL("""
    CREATE TABLE IF NOT EXISTS people (
        id      TEXT PRIMARY KEY,
        name    TEXT NOT NULL,
        aliases TEXT NOT NULL DEFAULT '[]'
    );
""")
execSQL("""
    CREATE TABLE IF NOT EXISTS session_people (
        session_id TEXT NOT NULL,
        person_id  TEXT NOT NULL,
        source     TEXT NOT NULL DEFAULT 'inferred',
        PRIMARY KEY (session_id, person_id)
    );
""")
```

**Step 2: Create `Sources/PeopleTaggingService.swift`**

```swift
import Foundation

final class PeopleTaggingService: @unchecked Sendable {
    private let store = SessionStore.shared
    var apiKey: String = ""
    var baseURL: String = "https://api.groq.com/openai/v1"

    func tagPeople(sessionID: String, transcript: String) async {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let prompt = """
            Extract the proper names of PEOPLE mentioned in this transcript.
            Return only a JSON array of strings, e.g. ["Alice", "Bob"].
            If no names, return [].
            Transcript:
            \(transcript.prefix(2000))
            """

        guard let names = try? await callGroq(prompt: prompt),
              !names.isEmpty else { return }

        for name in names {
            let personID: String
            // Try to match existing person (simple name equality for now)
            if let existing = findPerson(name: name) {
                personID = existing
            } else {
                personID = UUID().uuidString
                store.execBind(
                    "INSERT OR IGNORE INTO people (id, name) VALUES (?, ?);",
                    args: [personID, name]
                )
            }
            store.execBind(
                "INSERT OR IGNORE INTO session_people (session_id, person_id) VALUES (?, ?);",
                args: [sessionID, personID]
            )
        }
        Log.info(.system, "Tagged \(names.count) people for session \(sessionID): \(names)")
    }

    private func findPerson(name: String) -> String? {
        // NOTE: execBind is private — expose a query method in SessionStore or inline here
        return nil  // simplified for now; extend SessionStore.querySessions pattern
    }

    private func callGroq(prompt: String) async throws -> [String] {
        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "meta-llama/llama-4-scout-17b-16e-instruct",
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 200
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String
        else { return [] }

        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let jsonData = cleaned.data(using: .utf8),
           let names = try? JSONDecoder().decode([String].self, from: jsonData) {
            return names
        }
        return []
    }
}
```

**Step 3: Call after session ends in ChunkManager**

In `ChunkManager.stopListening()` or `pause()`, after `sessionStore.endSession(...)`:

```swift
let taggingService = PeopleTaggingService()
taggingService.apiKey = SettingsManager.shared.groqAPIKey
let fullTranscript = _transcriptBuffer.joined(separator: " ")
let sid = currentSessionID // capture before nil
Task.detached {
    if let sid {
        await taggingService.tagPeople(sessionID: sid, transcript: fullTranscript)
    }
}
_transcriptBuffer.removeAll()
```

**Step 4: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

**Step 5: Commit**

```bash
git add Sources/PeopleTaggingService.swift Sources/SessionStore.swift Sources/ChunkManager.swift
git commit -m "feat: add post-session people tagging via LLM name extraction"
```

---

## Build and Run Verification

After all Phase 1 tasks complete, do a full build and smoke test:

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
swift build -c release 2>&1 | grep -E "error:|warning:|Build complete"
```

Start the app:
```bash
./run.sh
```

Verify:
- [ ] Pill still appears and audio level waveform works
- [ ] ⌃R toggles listening (mic indicator on/off)
- [ ] ⌃Space flushes current chunk (check logs for "flushing — silence" or "force")
- [ ] Chunk durations are 10–30s (check log: "Chunk N: flushing")
- [ ] Session Timeline tab shows cards when sessions accumulate
- [ ] After recording on a known WiFi, session card shows place name
- [ ] AVSpeechSynthesizer speaks briefly after AI Search answers
- [ ] Appearance mode toggle in Settings changes pill material

---

## Notes for Implementer

- All file paths are relative to `/Users/sameeprehlan/Documents/Claude Code/autoclawd/`
- SQLite3 is already linked — no new Package.swift changes needed
- The `SQLITE_TRANSIENT` constant must be redeclared in `SessionStore.swift` (or import it once and share)
- `execBind` is `private` in `SessionStore` — `PeopleTaggingService` will need a thin public wrapper method added to `SessionStore` for the insert operations
- `CoreWLAN` framework: add `.linkedFramework("CoreWLAN")` to `Package.swift` linkerSettings if the build fails with CoreWLAN missing
- `BrutalistTheme.neonGreen` is already defined in `Sources/BrutalistTheme.swift` — use it for all UI accents
