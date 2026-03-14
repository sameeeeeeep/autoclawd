# Suggestion Pipeline, Canvas Intelligence & Learn Mode Monitor — Design Spec
**Date:** 2026-03-14
**Status:** Approved

---

## Problem Statement

Three interrelated issues exist in the current Learn Mode / suggestion system:

1. **Broken capability toast** — `CapabilityToastView` renders blank sub-steps when FUCBC-built capabilities have incomplete `subWorkflows` (nil `invocation` or only 1 entry). The step count shows wrong values and the app icon strip is sparse.

2. **Suggestions are automation-only** — The system only surfaces multi-step capability automations. Simple actionable tasks detected from conversation/screen ("send the quarterly report to Josh", "post a job listing for senior designer") are never surfaced, even though they're easy to identify and execute. Context for these tasks (files, contacts, URLs) is often already visible on screen.

3. **Canvas captures the same screen repeatedly** — `recordEvent()` fires every 5 seconds regardless of whether the screen changed. The same `LearnEvent` is appended over and over when the user stays on one screen. There is no intelligence to detect "this is the same context I already have." The canvas UI also has rendering issues.

---

## Approach: Unified Suggestion Pipeline (Approach B)

A single `SuggestionPipeline` handles capability scoring and task extraction in one pass. The canvas node model is rebuilt around `(app, url)` keying with Llama summarisation. A new floating Learn Mode monitor window gives the user live visibility into what is being captured.

---

## Section 1: Unified Suggestion Pipeline

### New Data Types

```swift
// Top-level suggestion item — replaces SuggestionMatch as the AppState currency
enum SuggestionItem {
    case capability(SuggestionMatch)   // multi-step automation
    case task(TaskSuggestion)          // simple actionable task
}

struct TaskSuggestion: Identifiable {
    let id: String                     // UUID string
    let title: String                  // "Send quarterly report to Josh"
    let intent: String                 // "email" | "hire" | "post" | "message" | etc.
    let detectedContext: TaskContext
    let executionPrompt: String        // ready-to-run Claude Code prompt
    let confidence: Float              // 0.0–1.0
}

struct TaskContext {
    let files: [String]      // filenames detected in OCR (e.g. "Q4-Report.pdf")
    let contacts: [String]   // names/emails from transcript or OCR (e.g. "Josh")
    let urls: [String]       // relevant URLs visible on screen
    let rawOCR: String       // full OCR snapshot — passed to canvas if context incomplete

    var isComplete: Bool {
        // context is "complete enough" to run without user input
        !files.isEmpty || !contacts.isEmpty || !urls.isEmpty
    }
}
```

### `SuggestionPipeline` Service

New `SuggestionPipeline` class replaces the inline `CapabilityStore.suggest()` call in `AppState`.

**Inputs per frame:** `(screenText: String, transcript: String, app: String?, urls: [String])`

**Two parallel evaluations:**

1. **Capability scoring** — the existing `CapabilityStore.suggest()` logic, moved into `SuggestionPipeline`. Returns `[SuggestionMatch]` sorted by score (threshold ≥ 3).

2. **Task extraction** — a Llama 3.2 pass over the latest cleaned transcript chunk + OCR snippet. Extracts zero or more `TaskSuggestion` items. The Llama call is skipped if transcript hasn't changed since the last frame (content-hash check). Prompt instructs the model to:
   - Identify simple, immediately actionable tasks mentioned in speech or implied by screen context
   - Classify intent (email, message, post, hire, schedule, search, etc.)
   - Extract context signals (file names, person names, URLs) from OCR
   - Output structured JSON array

**Output:** `[SuggestionItem]` — capabilities and tasks merged and sorted by confidence/score. Top item is set as `AppState.detectedSuggestion: SuggestionItem?`.

### AppState Changes

- `detectedSuggestion: SuggestionMatch?` → `detectedSuggestion: SuggestionItem?`
- `dismissDetectedCapability()` → `dismissDetectedSuggestion()`
- `executeCapability(_ capability: Capability)` — unchanged
- Add `executeTask(_ task: TaskSuggestion)` — builds `PipelineTaskRecord` (id: `TASK-{8hex}`), runs Claude Code with `task.executionPrompt`
- OCR frame callback calls `suggestionPipeline.evaluate(...)` instead of `CapabilityStore.shared.suggest(...)`

---

## Section 2: Toast Fix + Unified Rendering

### Issue 1 Fix — Broken Capability Toast

**Root cause:** `subWorkflows` array from FUCBC sometimes contains entries with nil `invocation` and empty `name`, or Claude only outputs 1 subWorkflow. `CapabilityToastView` renders all array entries including blanks.

**Rendering fix:**
- Filter `subWorkflows` to non-empty entries (`!name.isEmpty`) before rendering step count and icon strip
- `ToolIconStrip` uses filtered list — never derives app names from blank entries
- If filtered count == 0, show a generic "1 step" fallback rather than crashing

**FUCBC prompt fix:**
- Add explicit constraint in `buildFUCBCPrompt()`: "Always output at least 2 subWorkflows. Every subWorkflow must have a non-empty `name` and a non-empty `invocation` (shell command or skill slug)."

### Unified Toast Rendering

`CapabilityToastView` accepts `SuggestionItem` instead of `SuggestionMatch`:

**`.capability(SuggestionMatch)` rendering** — unchanged layout:
- `ToolIconStrip` (app icons, up to 4)
- Contextual headline ("Launching a Threads campaign?")
- Subtitle: "X steps · Automate this?"
- Run / Snooze (X) / Irrelevant (👎) buttons

**`.task(TaskSuggestion)` rendering** — simplified layout:
- Intent chip (⚡ + intent label, e.g. "⚡ email")
- Task title ("Send quarterly report to Josh")
- Detected context chips: 📎 filename, 👤 contact name, 🔗 URL — shown inline below title
- **If context is complete:** "Run" button → `executeTask()`
- **If context incomplete:** "Run" + "Add context →" button → opens canvas panel for gap-filling

Both types share: 300px width, `.ultraThinMaterial` glass background, 12px shadow, auto-dismiss after 5s, same snooze/irrelevant callbacks.

---

## Section 3: Canvas Node Intelligence

### New `CanvasNode` Model

Replaces the flat `[LearnEvent]` array in `LearnSession`:

```swift
struct CanvasNode: Identifiable, Codable {
    let id: String                      // UUID string
    let app: String                     // frontmost app name
    let url: String?                    // detected URL (nil if no browser)
    var ocrSnapshots: [String]          // rolling OCR captures on this app+URL
    var speechSnippets: [String]        // speech heard while on this node
    var workSummary: String?            // Llama-generated: "User drafted a tweet about X"
    let capturedAt: Date
    var lastUpdated: Date

    var displayTitle: String { url.flatMap { URL(string: $0)?.host } ?? app }
    var isPending: Bool { workSummary == nil }
}
```

`LearnSession.events: [LearnEvent]` → `LearnSession.nodes: [CanvasNode]`

### `recordEvent()` Logic

Every 5 seconds in `LearnModeService`:

1. Get current `(app, url)` from `screenVisionAnalyzer`
2. Get current OCR text and speech snippet
3. **If current `(app, url)` matches last node:**
   - Compute character-level overlap between current OCR and last snapshot in node
   - If overlap < 50% (content changed meaningfully) → append snapshot + speech to existing node, update `lastUpdated`
   - If overlap ≥ 50% (same screen, nothing new) → **skip entirely**
4. **If different `(app, url)`:** → create new `CanvasNode`, append to `session.nodes`

Overlap check: `commonChars(a, b) / max(a.count, b.count)` — simple, no dependencies.

### Llama Summarisation Pass

Called once per node, just before `buildCapability()` assembles the journey:

```
Prompt per node:
"In one sentence, what was the user doing in {app} ({url})?
OCR snapshots: {snapshots joined by ' | '}
Speech: {speechSnippets joined by ' · '}"
```

Result stored as `node.workSummary`. Runs nodes in parallel (async group). Nodes without enough content (< 20 chars of OCR) get a default: `"Opened {app}"`.

`buildUserJourney()` assembles narrative from `node.workSummary` values instead of raw event lines.

### `AICanvasView` Updates

- Canvas node strip renders `[CanvasNode]` instead of `[LearnEvent]`
- Node card body shows `workSummary` if available, latest OCR snippet while summary is pending (with subtle spinner)
- Node count in header reflects `session.nodes.count`

---

## Section 4: Learn Mode Monitor Window

### `LearnModeMonitorWindow`

New `NSPanel` subclass:
- Style: non-activating, always on top, `.titled` + `.closable` + `.resizable`, glass/blur background
- Default size: 320 × 420pt
- Default position: top-right of main screen, offset 16pt from edge, below toast zone (~y: 80pt from top)
- Lifecycle: wired in `AppDelegate` via `appState.$pillMode` Combine sink
  - `.learn` → `orderFront(nil)`
  - Any other mode → `orderOut(nil)`

### `LearnModeMonitorView`

```
┌─────────────────────────────────┐
│  ● Recording  ·  3 nodes        │  ← header: pulsing red dot + live node count
├─────────────────────────────────┤
│  🧵 Threads                     │  ← AppIconView (28px) + bold app name
│  threads.net/compose            │  ← URL host or window title (gray, small)
│  "Drafting a post about WWDC"   │  ← workSummary (gray, 2 lines max)
├─────────────────────────────────┤
│  🌐 Safari                      │
│  youtube.com/watch?v=...        │
│  "Watching Llama 3.3 demo"      │
├─────────────────────────────────┤
│  𝕏 Twitter                      │
│  x.com/compose                  │
│  ⟳ Capturing...                 │  ← spinner while Llama summarises
├─────────────────────────────────┤
│         [ Stop & Build ]        │  ← calls learnModeService.buildCapability()
└─────────────────────────────────┘
```

**Each node row:**
- `AppIconView` (28px) — existing component
- Bold app name (Glass.textPrimary)
- `displayTitle` — URL host or window title (Glass.textSecondary, `.caption`)
- `workSummary` if set, otherwise "Capturing…" with spinner (Glass.textTertiary, 2-line limit)
- Rows animate in (`.transition(.move(edge: .bottom).combined(with: .opacity))`) as new nodes are appended

**Live updates:** `LearnModeMonitorView` takes `@ObservedObject var service: LearnModeService`. SwiftUI re-renders on `session.nodes` changes — no polling needed.

**"Stop & Build" button:** `GlassButton` at bottom, calls `learnModeService.buildCapability()`. Disabled while `session.phase == .building`.

---

## Key Files Touched

| File | Change |
|------|--------|
| `LearnModeModels.swift` | Add `CanvasNode`, `TaskSuggestion`, `TaskContext`, `SuggestionItem`; update `LearnSession` |
| `LearnModeService.swift` | Rewrite `recordEvent()` with app+URL keying; add Llama summarisation pass; update `buildUserJourney()` |
| `SuggestionPipeline.swift` | **New file** — unified capability scoring + task extraction |
| `CapabilityStore.swift` | Move scoring logic to `SuggestionPipeline`; keep `save/load/delete/snooze` |
| `AppState.swift` | `detectedSuggestion: SuggestionItem?`; add `executeTask()`; wire `SuggestionPipeline` |
| `ToastView.swift` | `CapabilityToastView` accepts `SuggestionItem`; add task rendering branch; filter blank subWorkflows |
| `ToastWindow.swift` | Update to pass `SuggestionItem` to view |
| `AICanvasView.swift` | Render `[CanvasNode]` instead of `[LearnEvent]`; update node cards |
| `LearnModeMonitorWindow.swift` | **New file** — NSPanel wrapper |
| `LearnModeMonitorView.swift` | **New file** — SwiftUI node list view |
| `AppDelegate.swift` | Wire `LearnModeMonitorWindow` lifecycle to `pillMode` |
| `LearnModeService.swift` | Tighten FUCBC prompt for well-formed subWorkflows |

---

## Data Flow Summary

```
[OCR frame + transcript chunk]
        |
        v
SuggestionPipeline.evaluate()
    |                    |
    v                    v
CapabilityStore      Llama task extraction
.suggest()           (skipped if transcript unchanged)
    |                    |
    v                    v
[SuggestionMatch]   [TaskSuggestion]
        |
        v
AppState.detectedSuggestion: SuggestionItem?
        |
        v
CapabilityToastView (top-right)
    .capability → multi-step strip
    .task       → intent chip + context tags

[Learn Mode active]
        |
  Every 5s: recordEvent()
    |
    app+URL same? → OCR diff < 50%? → update node
                                    → skip (same screen)
    app+URL diff? → new CanvasNode
        |
  buildCapability() triggered
        |
  Llama summarise each node (parallel)
        |
  buildUserJourney() from workSummaries
        |
  Claude Code writes SKILL.md + JSON manifest

[LearnModeMonitorWindow]
  visible when pillMode == .learn
  observes learnModeService.session.nodes
  live node list with workSummary per node
```
