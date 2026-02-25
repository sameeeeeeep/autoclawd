# Two-Pass Intelligence Pipeline Design
Date: 2026-02-25

## Problem

The current single-pass Ollama extraction asks for complete file rewrites of `world-model.md` and `todos.md` in one prompt. This hits the 1000-token output limit, truncates responses, produces poor extraction quality, and gives the user no visibility into or control over what gets added to their knowledge files.

## Solution Overview

Replace the single-pass extraction with a two-pass pipeline:

- **Pass 1** (per chunk, fast ~5-15s): Classify each idea/sentence in the transcript as relevant or non-relevant, assign a bucket, extract the normalized fact or todo
- **Pass 2** (batch, slower ~30-60s, on-demand or auto): Synthesize all accepted Pass 1 items into the world model and todo files

---

## Data Model

### New SQLite table: `extraction_items`

```sql
CREATE TABLE extraction_items (
    id              TEXT PRIMARY KEY,     -- UUID
    chunk_index     INTEGER NOT NULL,
    timestamp       REAL NOT NULL,        -- unix epoch
    source_phrase   TEXT NOT NULL,        -- fragment of transcript it came from
    content         TEXT NOT NULL,        -- normalized extracted text
    type            TEXT NOT NULL,        -- "fact" | "todo"
    bucket          TEXT NOT NULL,        -- "projects" | "people" | "plans" | "preferences" | "decisions" | "other"
    priority        TEXT,                 -- for todos: "HIGH" | "MEDIUM" | "LOW"
    model_decision  TEXT NOT NULL,        -- "relevant" | "nonrelevant" | "uncertain"
    user_override   TEXT,                 -- NULL | "accepted" | "dismissed"
    applied         INTEGER DEFAULT 0,    -- 1 = included in a Pass 2 synthesis run
    created_at      REAL NOT NULL
);
```

**Effective state** = `user_override ?? model_decision`
- Pass 2 reads items where effective state is `relevant/accepted` and `applied = 0`

---

## Pass 1: Relevance + Bucketing

**Trigger:** After every transcribed chunk (replaces current `ExtractionService.process()`)

**Prompt structure:**
```
You are classifying ideas from a spoken transcript into structured knowledge items.

TRANSCRIPT:
<transcript text>

For each distinct idea, output one line in this exact format:
<relevance> | <bucket> | <type> | <priority_if_todo> | <content>

relevance: "relevant" | "nonrelevant" | "uncertain"
bucket: "projects" | "people" | "plans" | "preferences" | "decisions" | "other"
type: "fact" | "todo"
priority (todos only): "HIGH" | "MEDIUM" | "LOW" | "-"
content: normalized one-line description

Mark as nonrelevant: filler words, incomplete sentences, social niceties, ambient noise descriptions.
Mark as uncertain: things that might be relevant but lack enough context.

Example output:
relevant | projects | fact | - | User is testing the AutoClawd macOS app
relevant | projects | todo | HIGH | Complete AutoClawd testing phase
nonrelevant | - | - | - | Filler: "so if this..."
```

**Output:** ~50–200 tokens. Never approaches the 1000-token limit.

**Parsing:** Each line is split on ` | ` into 5 fields. Lines that don't parse cleanly are logged and skipped.

**On completion:**
- Each item is inserted into `extraction_items` SQLite table
- Items with `model_decision = relevant` are auto-accepted (unless user later overrides)
- Verbose logs emit one line per item:
  ```
  [EXTRACT] ✓ relevant | projects | fact    | User is testing the AutoClawd macOS app
  [EXTRACT] ✓ relevant | projects | todo↑H  | Complete AutoClawd testing phase
  [EXTRACT] ✗ nonrelevant                   | Filler: "so if this..."
  ```

---

## Pass 2: World Model Synthesis

**Trigger options (all supported):**
- Manual: "Synthesize Now" button in Intelligence tab
- Auto: every 10 accepted items (configurable)
- Auto: on app quit (if there are pending items)

**Input:**
- All `extraction_items` where effective state = accepted and `applied = 0`, grouped by bucket
- Current contents of `world-model.md` and `todos.md`

**Prompt structure:**
```
You maintain a world model (facts about the user) and a todo list.

CURRENT WORLD MODEL:
<world-model.md>

CURRENT TODOS:
<todos.md>

NEW ACCEPTED FACTS (by bucket):
[projects]
- User is testing the AutoClawd macOS app

[people]
(none)

NEW TODOS:
- HIGH: Complete AutoClawd testing phase

Update both files. Output complete updated versions wrapped in:
<WORLD_MODEL>...</WORLD_MODEL>
<TODOS>...</TODOS>
```

**Why this works better:** The model receives clean, pre-classified, pre-bucketed facts — not raw messy transcript. Quality is dramatically higher and output length is predictable.

**On completion:**
- `world-model.md` and `todos.md` are updated
- All processed items marked `applied = 1`
- Logs: `[WORLD] Synthesis complete: 3 facts applied` / `[TODO] 2 todos added`

---

## New Service: ExtractionStore

New `Sources/ExtractionStore.swift` wrapping the `extraction_items` SQLite table:

```swift
struct ExtractionItem: Identifiable {
    let id: String
    let chunkIndex: Int
    let timestamp: Date
    let sourcePhrase: String
    let content: String
    let type: ExtractionType       // .fact | .todo
    let bucket: ExtractionBucket   // .projects | .people | .plans | .preferences | .decisions | .other
    let priority: String?          // for todos
    let modelDecision: String      // "relevant" | "nonrelevant" | "uncertain"
    var userOverride: String?      // nil | "accepted" | "dismissed"
    var applied: Bool

    var effectiveState: String { userOverride ?? modelDecision }
    var isAccepted: Bool { effectiveState == "relevant" || effectiveState == "accepted" }
}
```

Methods:
- `insert(_ item: ExtractionItem)`
- `all(chunkIndex: Int?) -> [ExtractionItem]`
- `pendingAccepted() -> [ExtractionItem]` — effective state accepted, applied=0
- `setUserOverride(id: String, override: String?)`
- `setBucket(id: String, bucket: String)`
- `markApplied(ids: [String])`

---

## Updated ExtractionService

`ExtractionService` is split into two methods:

```swift
// Pass 1 — called from ChunkManager after each transcription
func classifyChunk(transcript: String, chunkIndex: Int) async -> [ExtractionItem]

// Pass 2 — called on demand or auto-triggered
func synthesize() async
```

`synthesize()` checks `extractionStore.pendingAccepted()` before running — skips if empty.

---

## UI: Intelligence Tab

New 6th tab in `MainPanelView`. Layout:

```
┌─ Intelligence ──────────────────────────────────────────────────┐
│ [● Synthesize Now]    3 items pending synthesis      [Auto: 10▾] │
├─────────────────────────────────────────────────────────────────┤
│ ▼ Chunk 5 · 10:33 · "Hi, this is something that I am doing..."  │
│   [✓] projects  fact    User is testing the AutoClawd macOS app  │
│   [✓] projects  todo↑H  Complete AutoClawd testing phase         │
│   [✗] —         filler  Filler: "so if this..."                  │
│                                                                   │
│ ▶ Chunk 3 · 10:22 · (collapsed, 2 items)                         │
└─────────────────────────────────────────────────────────────────┘
```

**Interactions:**
- `[✓]`/`[✗]` toggle → sets `user_override` in SQLite, triggers Pass 2 for that item
- Bucket tag (e.g. `projects`) → tap/click opens a picker to reassign bucket
- Chunk rows are collapsible
- Applied items shown in a slightly dimmer style with a "synced" checkmark
- `[Synthesize Now]` button → calls `ExtractionService.synthesize()`
- `[Auto: 10▾]` picker → sets the auto-synthesize threshold (5/10/20/off)

---

## Files Changed / Created

| File | Change |
|------|--------|
| `Sources/ExtractionStore.swift` | **NEW** — SQLite wrapper for `extraction_items` |
| `Sources/ExtractionService.swift` | **REWRITE** — two-pass `classifyChunk()` + `synthesize()` |
| `Sources/IntelligenceView.swift` | **NEW** — 6th tab UI |
| `Sources/AppState.swift` | Add `ExtractionStore`, wire up `synthesize()`, pending count |
| `Sources/MainPanelView.swift` | Add `.intelligence` tab |
| `Sources/ChunkManager.swift` | Call `classifyChunk()` instead of `extractionService.process()` |
| `Sources/TranscriptStore.swift` | Minor: add `ExtractionStore` to same DB file |

---

## Logging

All extraction decisions are logged at `[EXTRACT]` component with verbose detail:

```
[EXTRACT] Pass 1: chunk 5, 19 words → 3 items (2 relevant, 1 nonrelevant)
[EXTRACT] ✓ relevant | projects | fact    | User is testing the AutoClawd macOS app
[EXTRACT] ✓ relevant | projects | todo↑H  | Complete AutoClawd testing phase
[EXTRACT] ✗ nonrelevant | filler           | "so if this..."
[EXTRACT] Pass 2: synthesizing 2 accepted items
[WORLD]   Synthesis complete: 1 fact applied to world model
[TODO]    Synthesis complete: 1 todo added (HIGH)
```
