# Two-Pass Intelligence Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the broken single-pass Ollama extraction with a two-pass pipeline: Pass 1 classifies individual transcript ideas as relevant/non-relevant + assigns buckets; Pass 2 synthesizes accepted items into world-model.md and todos.md.

**Architecture:** Pass 1 runs per chunk after transcription (~50-200 token output, no token limit issues). Each item is stored in a new `extraction_items` SQLite table with accept/dismiss/bucket state. Pass 2 runs on demand or auto (every N items) and merges accepted items into the markdown files using a focused prompt with clean pre-classified input.

**Tech Stack:** Swift 6, SQLite3 C API (same pattern as TranscriptStore), SwiftUI, Ollama REST API (localhost:11434)

**Design doc:** `docs/plans/2026-02-25-two-pass-intelligence-pipeline-design.md`

---

## Task 1: ExtractionItem model + supporting enums

**Files:**
- Create: `Sources/ExtractionItem.swift`

**Step 1: Create the file**

```swift
import Foundation

enum ExtractionType: String, Codable, CaseIterable {
    case fact, todo
}

enum ExtractionBucket: String, Codable, CaseIterable {
    case projects, people, plans, preferences, decisions, other
    var displayName: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .projects:    return "folder"
        case .people:      return "person.2"
        case .plans:       return "calendar"
        case .preferences: return "slider.horizontal.3"
        case .decisions:   return "checkmark.seal"
        case .other:       return "tag"
        }
    }
    static func parse(_ raw: String) -> ExtractionBucket {
        ExtractionBucket(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased()) ?? .other
    }
}

struct ExtractionItem: Identifiable, Equatable {
    let id: String
    let chunkIndex: Int
    let timestamp: Date
    let sourcePhrase: String
    let content: String
    let type: ExtractionType
    var bucket: ExtractionBucket
    let priority: String?
    let modelDecision: String
    var userOverride: String?
    var applied: Bool

    var effectiveState: String  { userOverride ?? modelDecision }
    var isAccepted: Bool        { effectiveState == "relevant" || effectiveState == "accepted" }
    var isDismissed: Bool       { effectiveState == "nonrelevant" || effectiveState == "dismissed" }
    var priorityLabel: String {
        switch priority {
        case "HIGH":   return "↑H"
        case "MEDIUM": return "↑M"
        case "LOW":    return "↑L"
        default:       return ""
        }
    }
}
```

**Step 2: Build** — `make` in project root. Expected: `Built build/AutoClawd.app`

**Step 3: Commit** — `git add Sources/ExtractionItem.swift && git commit -m "feat: add ExtractionItem model + enums"`

---

## Task 2: ExtractionStore (SQLite wrapper)

**Files:**
- Create: `Sources/ExtractionStore.swift`

Full implementation — follows the same SQLite3 C API pattern as `TranscriptStore.swift`.

**Schema:**
```sql
CREATE TABLE IF NOT EXISTS extraction_items (
    id            TEXT PRIMARY KEY,
    chunk_index   INTEGER NOT NULL,
    timestamp     REAL NOT NULL,
    source_phrase TEXT NOT NULL,
    content       TEXT NOT NULL,
    type          TEXT NOT NULL,
    bucket        TEXT NOT NULL DEFAULT 'other',
    priority      TEXT,
    model_decision TEXT NOT NULL,
    user_override TEXT,
    applied       INTEGER NOT NULL DEFAULT 0,
    created_at    REAL NOT NULL
);
```

**Methods to implement:**
- `init(url: URL)` — open DB at url, run CREATE TABLE, set WAL mode
- `insert(_ item: ExtractionItem)` — INSERT OR IGNORE
- `setUserOverride(id: String, override: String?)` — UPDATE user_override
- `setBucket(id: String, bucket: ExtractionBucket)` — UPDATE bucket
- `markApplied(ids: [String])` — UPDATE applied=1 for each id
- `all(chunkIndex: Int? = nil) -> [ExtractionItem]` — SELECT all, optional filter by chunk
- `pendingAccepted() -> [ExtractionItem]` — SELECT where applied=0 AND (user_override='accepted' OR (user_override IS NULL AND model_decision='relevant'))

All methods are thread-safe via a serial `DispatchQueue`. Declare class as `@unchecked Sendable`.

**Step 1: Write the file** following the TranscriptStore pattern (sqlite3_prepare_v2 / bind / step / finalize).

**Step 2: Build** — `make`. Expected: `Built build/AutoClawd.app`

**Step 3: Commit** — `git add Sources/ExtractionStore.swift && git commit -m "feat: add ExtractionStore SQLite wrapper"`

---

## Task 3: FileStorageManager + SettingsManager additions

**Files:**
- Modify: `Sources/FileStorageManager.swift`
- Modify: `Sources/SettingsManager.swift`

**FileStorageManager — add after `transcriptsDatabaseURL`:**
```swift
var intelligenceDatabaseURL: URL {
    rootDirectory.appendingPathComponent("intelligence.db")
}
```

**SettingsManager — add after `audioRetentionDays`:**
```swift
/// Auto-synthesize after this many pending accepted items. 0 = off (manual only).
var synthesizeThreshold: Int {
    get { UserDefaults.standard.integer(forKey: "synthesizeThreshold") == 0
          ? 10
          : UserDefaults.standard.integer(forKey: "synthesizeThreshold") }
    set { UserDefaults.standard.set(newValue, forKey: "synthesizeThreshold") }
}
```

**Step 1: Make both edits.**

**Step 2: Build** — `make`. Expected: `Built build/AutoClawd.app`

**Step 3: Commit** — `git add Sources/FileStorageManager.swift Sources/SettingsManager.swift && git commit -m "feat: add intelligenceDatabaseURL and synthesizeThreshold"`

---

## Task 4: OllamaService — add num_predict parameter

**Files:**
- Modify: `Sources/OllamaService.swift`

**Change `generate` signature:**
```swift
func generate(prompt: String, numPredict: Int = 512) async throws -> String {
```

**Add to payload dict:**
```swift
"num_predict": numPredict
```

Pass 1 uses default 512. Pass 2 callers pass `numPredict: 2048`.

**Step 1: Make the edit.**

**Step 2: Build** — `make`. Expected: `Built build/AutoClawd.app`

**Step 3: Commit** — `git add Sources/OllamaService.swift && git commit -m "feat: add num_predict param to OllamaService.generate"`

---

## Task 5: ExtractionService — full rewrite with Pass 1 + Pass 2

**Files:**
- Modify: `Sources/ExtractionService.swift` — full replacement

**New init signature:**
```swift
init(ollama: OllamaService, worldModel: WorldModelService,
     todos: TodoService, store: ExtractionStore)
```

### Pass 1 method: `classifyChunk(transcript:chunkIndex:) async -> [ExtractionItem]`

**Prompt** (ask model for pipe-delimited lines, one per idea):
```
You classify spoken transcript ideas into structured knowledge items.

TRANSCRIPT:
{transcript}

Output one line per distinct idea using EXACTLY this pipe-delimited format:
<relevance>|<bucket>|<type>|<priority>|<content>

Fields:
- relevance: relevant | nonrelevant | uncertain
- bucket: projects | people | plans | preferences | decisions | other
- type: fact | todo
- priority: HIGH | MEDIUM | LOW | - (use - for facts)
- content: one normalized complete sentence

Rules:
- relevant: clear facts about the user, their work, decisions, preferences, action items
- nonrelevant: filler, incomplete sentences, ambient sound, pure small talk
- uncertain: might matter but lacks context to classify confidently
- No blank lines. No explanations. No markdown.

Example output:
relevant|projects|fact|-|User is testing the AutoClawd macOS app
relevant|projects|todo|HIGH|Complete AutoClawd testing phase
nonrelevant|-|-|-|Filler phrase
```

**Parser** — split each line on `|`, take first 5 fields (rejoin rest as content in case it contains `|`). Skip lines that don't parse. Validate relevance is one of the three valid values.

**Logging** — after parsing:
```
[EXTRACT] Pass 1 done: chunk N → X items (A relevant, B nonrelevant, C uncertain)
[EXTRACT] ✓ relevant | projects | fact | User is testing AutoClawd
[EXTRACT] ✗ nonrelevant | filler | ...
```

### Pass 2 method: `synthesize() async`

1. Load `store.pendingAccepted()` — if empty, log and return
2. Build prompt with current world-model.md + todos.md + accepted items grouped by bucket
3. Call `ollama.generate(prompt:, numPredict: 2048)`
4. Parse `<WORLD_MODEL>...</WORLD_MODEL>` and `<TODOS>...</TODOS>` tags (same extract() helper as before)
5. Write updated files if sections found
6. Call `store.markApplied(ids:)`

**Pass 2 prompt structure:**
```
You maintain a world model and to-do list.

CURRENT WORLD MODEL:
{world-model.md}

CURRENT TO-DO LIST:
{todos.md}

NEW ACCEPTED FACTS ({date}):
[projects]
- fact 1

NEW ACCEPTED TODOS:
- HIGH: todo 1

Update both files. Output complete updated versions:
<WORLD_MODEL>...</WORLD_MODEL>
<TODOS>...</TODOS>
```

**Step 1: Write the full rewrite.**

**Step 2: Build** — `make`. Expected: `Built build/AutoClawd.app`

**Step 3: Commit** — `git add Sources/ExtractionService.swift && git commit -m "feat: rewrite ExtractionService with two-pass pipeline"`

---

## Task 6: Wire ChunkManager + AppState

**Files:**
- Modify: `Sources/ChunkManager.swift`
- Modify: `Sources/AppState.swift`

### ChunkManager

**Add callback property** (next to `onTranscriptReady`):
```swift
var onItemsClassified: (([ExtractionItem]) -> Void)?
```

**In `processChunk()`, replace the `extractionService.process()` call with:**
```swift
Log.info(.extract, "Chunk \(index): starting extraction (Pass 1)")
let items = await extractionService.classifyChunk(
    transcript: transcript,
    chunkIndex: index
)
await MainActor.run { self.onItemsClassified?(items) }
```

### AppState

**Add to services section:**
```swift
let extractionStore: ExtractionStore
```

**Add to @Published state:**
```swift
@Published var extractionItems: [ExtractionItem] = []
@Published var pendingExtractionCount: Int = 0
@Published var synthesizeThreshold: Int {
    didSet { SettingsManager.shared.synthesizeThreshold = synthesizeThreshold }
}
```

**In init(), create store and update ExtractionService init:**
```swift
let exStore = ExtractionStore(url: FileStorageManager.shared.intelligenceDatabaseURL)
extractionStore = exStore
synthesizeThreshold = SettingsManager.shared.synthesizeThreshold
extractionService = ExtractionService(
    ollama: OllamaService(),
    worldModel: WorldModelService(),
    todos: TodoService(),
    store: exStore
)
```

**In `configureChunkManager()`, add:**
```swift
chunkManager.onItemsClassified = { [weak self] _ in
    guard let self else { return }
    self.refreshExtractionItems()
    let pending = self.extractionStore.pendingAccepted().count
    self.pendingExtractionCount = pending
    if self.synthesizeThreshold > 0, pending >= self.synthesizeThreshold {
        Task { await self.synthesizeNow() }
    }
}
```

**Add public methods:**
```swift
func refreshExtractionItems() {
    extractionItems = extractionStore.all()
    pendingExtractionCount = extractionStore.pendingAccepted().count
}

func synthesizeNow() async {
    await extractionService.synthesize()
    await MainActor.run { refreshExtractionItems() }
}

func toggleExtraction(id: String) {
    guard let item = extractionItems.first(where: { $0.id == id }) else { return }
    let newOverride: String? = item.isAccepted ? "dismissed" : "accepted"
    extractionStore.setUserOverride(id: id, override: newOverride)
    refreshExtractionItems()
}

func setExtractionBucket(id: String, bucket: ExtractionBucket) {
    extractionStore.setBucket(id: id, bucket: bucket)
    refreshExtractionItems()
}
```

**In `applicationDidFinishLaunching()`**, add at end: `refreshExtractionItems()`

**Step 1: Make all the edits.**

**Step 2: Build** — `make`. Expected: `Built build/AutoClawd.app`

**Step 3: Commit:**
```
git add Sources/ChunkManager.swift Sources/AppState.swift
git commit -m "feat: wire ExtractionStore + classifyChunk into ChunkManager and AppState"
```

---

## Task 7: IntelligenceView (new SwiftUI tab)

**Files:**
- Create: `Sources/IntelligenceView.swift`

**Three views to create:**

### IntelligenceView (top-level)
- Header: "Synthesize Now" button (disabled when no pending items or synthesizing), pending count text, Auto threshold Picker (Manual/5/10/20)
- Body: grouped item list keyed by `chunkIndex`, sorted descending (newest first)
- `.onAppear { appState.refreshExtractionItems() }`
- Auto-expand the most recent chunk on appear

### ChunkGroupView
- Collapsible row showing: chevron, "Chunk N", time, source phrase preview, "X/Y accepted" count
- When expanded: list of `ExtractionItemRow`

### ExtractionItemRow
- `[✓/✗]` toggle button (green checkmark.circle.fill when accepted, secondary xmark.circle when dismissed)
- Bucket capsule tag with color coding: projects=blue, people=purple, plans=orange, preferences=teal, decisions=green, other=secondary — clicking opens a `Menu` picker to reassign
- Type+priority badge: "fact" or "todo↑H/↑M/↑L" in monospaced caption
- Content text (dimmer if `applied = true`)
- Synced indicator (checkmark.seal.fill) if `applied = true`

**Step 1: Write the view file.**

**Step 2: Build** — `make`. Expected: `Built build/AutoClawd.app`

**Step 3: Commit** — `git add Sources/IntelligenceView.swift && git commit -m "feat: add IntelligenceView with per-item controls"`

---

## Task 8: Add Intelligence tab to MainPanelView

**Files:**
- Modify: `Sources/MainPanelView.swift`

**Step 1: Add to PanelTab enum:**
```swift
case intelligence = "Intelligence"
```

**Step 2: Add icon:**
```swift
case .intelligence: return "brain.head.profile"
```

**Step 3: Add to content switch:**
```swift
case .intelligence: IntelligenceView(appState: appState)
```

**Step 4: Build** — `make`. Expected: `Built build/AutoClawd.app`

**Step 5: Commit:**
```
git add Sources/MainPanelView.swift
git commit -m "feat: add Intelligence tab to main panel"
```

---

## Task 9: Smoke Test

**Step 1: Restart app**
```bash
pkill -x AutoClawd; sleep 1
open "/Users/sameeprehlan/Documents/Claude Code/autoclawd/build/AutoClawd.app"
```

**Step 2: Speak for ~5 seconds, pause**

Check `~/.autoclawd/logs/autoclawd-*.log` — expected output:
```
[EXTRACT] Pass 1 start: chunk 0, N words
[EXTRACT] Pass 1 done: chunk 0 → N items (X relevant, Y nonrelevant, Z uncertain)
[EXTRACT] ✓ relevant | projects | fact | - | User is testing the AutoClawd macOS app
[EXTRACT] ✗ nonrelevant | - | - | - | Filler: ...
```

**Step 3: Open main panel → Intelligence tab**
- Chunk group visible and auto-expanded
- ✓/✗ toggles work
- Bucket picker works

**Step 4: Click "Synthesize Now"**

Expected log after ~30-60s:
```
[EXTRACT] Pass 2 start: N pending accepted items
[WORLD]   Synthesis complete: N facts applied to world model
[TODO]    Synthesis complete: N todos applied
```

**Step 5: Verify world-model.md has real content**
```bash
cat ~/.autoclawd/world-model.md
```

**Step 6: Final commit**
```bash
git add -A && git commit -m "feat: complete two-pass intelligence pipeline"
```

---

## Files Summary

| File | Action |
|------|--------|
| `Sources/ExtractionItem.swift` | NEW |
| `Sources/ExtractionStore.swift` | NEW |
| `Sources/IntelligenceView.swift` | NEW |
| `Sources/ExtractionService.swift` | REWRITE |
| `Sources/OllamaService.swift` | ADD numPredict param |
| `Sources/FileStorageManager.swift` | ADD intelligenceDatabaseURL |
| `Sources/SettingsManager.swift` | ADD synthesizeThreshold |
| `Sources/ChunkManager.swift` | CALL classifyChunk, ADD callback |
| `Sources/AppState.swift` | ADD store + intelligence methods |
| `Sources/MainPanelView.swift` | ADD .intelligence tab |
