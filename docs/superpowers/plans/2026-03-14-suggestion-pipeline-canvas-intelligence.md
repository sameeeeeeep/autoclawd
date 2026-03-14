# Suggestion Pipeline, Canvas Intelligence & Learn Mode Monitor — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix broken capability toasts, add a unified task+capability suggestion pipeline, rebuild canvas node model with app/URL keying and Llama summarisation, and add a floating Learn Mode monitor window.

**Architecture:** A new `@MainActor SuggestionPipeline` replaces the inline `CapabilityStore.suggest()` call in AppState, adding Llama-based task extraction alongside capability scoring. `LearnSession` switches from `[LearnEvent]` to `[CanvasNode]` (keyed by app+URL, OCR-deduplicated, Llama-summarised per node). A new `LearnModeMonitorWindow` NSPanel floats when Learn Mode is active showing live node captures.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (NSPanel), Combine, `OllamaService` (local Llama 3.2 3B via `ollama.generate(prompt:numPredict:)`), Claude Code SDK, `make` build system.

**Spec:** `docs/superpowers/specs/2026-03-14-suggestion-pipeline-canvas-intelligence-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/LearnModeModels.swift` | Modify | Add `CanvasNode`, `SuggestionItem`, `TaskSuggestion`, `TaskContext`; update `LearnSession` |
| `Sources/SuggestionPipeline.swift` | **Create** | Unified capability scoring + Llama task extraction, `@MainActor` |
| `Sources/CapabilityStore.swift` | Modify | Verify/add `urls` param to `suggest()`; scoring logic stays here |
| `Sources/LearnModeService.swift` | Modify | Rewrite `recordEvent()` (node keying + OCR diff); add Llama summarisation; update `buildUserJourney()`; tighten FUCBC prompt |
| `Sources/AppState.swift` | Modify | `detectedSuggestion: SuggestionItem?`; add `suggestionPipeline`; add `executeSuggestedTask()`; update OCR callback; rename dismiss method |
| `Sources/ToastView.swift` | Modify | `CapabilityToastView` accepts `SuggestionItem`; task rendering branch; filter blank subWorkflows |
| `Sources/ToastWindow.swift` | Modify | `show(_ item: SuggestionItem, ...)` replaces `showCapability()`; update `CapabilityToastModel` |
| `Sources/AICanvasView.swift` | Modify | Render `[CanvasNode]`; node cards show `workSummary`; update `hasEnoughContext` refs |
| `Sources/LearnModeMonitorView.swift` | **Create** | SwiftUI node list view (`@ObservedObject LearnModeService`) |
| `Sources/LearnModeMonitorWindow.swift` | **Create** | NSPanel wrapper for monitor view |
| `Sources/AppDelegate.swift` | Modify | Init monitor window; `showSuggestionToast()` replaces `showCapabilityToast()`; sink for pillMode → monitor lifecycle |

---

## Chunk 1: Foundation — New Types + SuggestionPipeline

### Task 1: Add new types to LearnModeModels.swift

**Files:**
- Modify: `Sources/LearnModeModels.swift`

- [ ] **Step 1: Add SuggestionItem, TaskSuggestion, TaskContext**

Open `Sources/LearnModeModels.swift`. After the closing `}` of `SuggestionMatch` (around line 21), insert:

```swift
// MARK: - Unified Suggestion Item

enum SuggestionItem {
    case capability(SuggestionMatch)
    case task(TaskSuggestion)
}

struct TaskSuggestion: Identifiable {
    let id: String
    let title: String           // e.g. "Send quarterly report to Josh"
    let intent: String          // "email" | "hire" | "post" | "message" | "other"
    let detectedContext: TaskContext
    let executionPrompt: String // built prompt ready for Claude Code
    let confidence: Float       // 0.0–1.0
}

struct TaskContext {
    let files: [String]    // filenames from OCR (e.g. "Q4-Report.pdf")
    let contacts: [String] // names/emails from transcript or OCR
    let urls: [String]     // relevant URLs visible on screen
    let rawOCR: String     // full OCR snapshot — canvas fallback

    // Intentionally permissive: Claude Code clarifies at runtime if a piece is missing.
    var isComplete: Bool { !files.isEmpty || !contacts.isEmpty || !urls.isEmpty }
}
```

- [ ] **Step 2: Add CanvasNode struct**

In the same file, insert `CanvasNode` anywhere at file scope — Swift resolves types within the same file regardless of declaration order, so placement relative to `LearnSession` does not matter. A good location is just before `LearnSession`:

```swift
// MARK: - Canvas Node (replaces flat LearnEvent array in LearnSession)

// Codable required: LearnSession is persisted and CanvasNode travels with it.
struct CanvasNode: Identifiable, Codable {
    let id: String
    let app: String
    let url: String?
    var ocrSnapshots: [String]    // rolling OCR captures while on this app+URL
    var speechSnippets: [String]  // speech heard while here
    var workSummary: String?      // Llama-generated: "User drafted a tweet about WWDC"
    let capturedAt: Date
    var lastUpdated: Date

    var displayTitle: String {
        if let urlStr = url, let host = URL(string: urlStr)?.host { return host }
        return app
    }
    var isPending: Bool { workSummary == nil }
}
```

- [ ] **Step 3: Update LearnSession — replace events with nodes**

Find `struct LearnSession` in the file. Replace the `events` property and its dependents:

**Before:**
```swift
var events: [LearnEvent] = []
// ... (hasEnoughContext and eventSummary reference events.count)
var hasEnoughContext: Bool { events.count >= 3 }
var eventSummary: String { "\(events.count) event(s) ..." }
```

**After:**
```swift
var nodes: [CanvasNode] = []
var hasEnoughContext: Bool { nodes.count >= 3 }
var eventSummary: String { "\(nodes.count) node(s) captured" }
```

- [ ] **Step 4: Build — expect errors in files that reference session.events**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd" && make 2>&1 | grep -E "error:|warning:" | head -30
```

Expected: Compile errors in `LearnModeService.swift` (both `recordEvent()` which is rewritten in Task 3, and `buildUserJourney()` which still references events until Task 4) and `AICanvasView.swift` (fixed in Task 7). These are expected at this stage — the new types themselves should have no errors. Do not attempt a full clean build until Task 7 is complete.

- [ ] **Step 5: Commit**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
git add Sources/LearnModeModels.swift
git commit -m "feat: add CanvasNode, SuggestionItem, TaskSuggestion, TaskContext to LearnModeModels"
```

---

### Task 2: Create SuggestionPipeline.swift

**Files:**
- Create: `Sources/SuggestionPipeline.swift`

- [ ] **Step 1: Create the file**

```swift
// Sources/SuggestionPipeline.swift
import Foundation
import AppKit

/// Unified suggestion pipeline. Runs on every OCR+transcript frame.
/// Replaces the inline CapabilityStore.suggest() call in AppState.
/// Declared @MainActor — Llama await suspends on main actor (acceptable for periodic check).
@MainActor
final class SuggestionPipeline {

    private let ollama = OllamaService()
    private var lastTranscriptHash: Int = 0

    // MARK: - Evaluate

    /// Returns the top suggestion for the current frame, or nil if nothing is relevant.
    func evaluate(
        screenText: String,
        transcript: String,
        app: String?,
        urls: [String],
        isOllamaEnabled: Bool
    ) async -> SuggestionItem? {

        // 1. Capability scoring (synchronous)
        let capMatches = CapabilityStore.shared.suggest(
            screenText: screenText,
            app: app,
            urls: urls
        )

        // 2. Task extraction (Llama — skip if disabled or transcript unchanged)
        var taskSuggestion: TaskSuggestion?
        let hash = transcript.hashValue
        if isOllamaEnabled, !transcript.isEmpty, hash != lastTranscriptHash {
            lastTranscriptHash = hash
            taskSuggestion = await extractTask(
                transcript: transcript,
                screenText: screenText,
                urls: urls
            )
        }

        // 3. Merge: high-confidence tasks win; else capability; else low-confidence task
        if let task = taskSuggestion, task.confidence >= 0.7 {
            return .task(task)
        }
        if let top = capMatches.first {
            return .capability(top)
        }
        if let task = taskSuggestion {
            return .task(task)
        }
        return nil
    }

    // MARK: - Task Extraction

    private func extractTask(
        transcript: String,
        screenText: String,
        urls: [String]
    ) async -> TaskSuggestion? {
        let prompt = """
        Identify one simple, immediately actionable task from the user's speech and screen.

        Speech: \(transcript)
        Screen (OCR): \(String(screenText.prefix(300)))
        URLs: \(urls.joined(separator: ", "))

        If a clear task exists (e.g. "send email to Josh", "post on LinkedIn", "hire a designer"):
        Output JSON: {"title":"...","intent":"email|message|post|hire|schedule|search|other","confidence":0.0-1.0,"files":[],"contacts":[],"urls":[]}

        If NO clear task: output {}
        Output ONLY valid JSON.
        """
        do {
            let response = try await ollama.generate(prompt: prompt, numPredict: 256)
            return parseTask(from: response, screenText: screenText, fallbackURLs: urls)
        } catch {
            // Silently discard — matches existing pipeline pattern for Llama failures.
            // Capability suggestions still surface; task suggestions are dropped for this frame.
            return nil
        }
    }

    private func parseTask(
        from response: String,
        screenText: String,
        fallbackURLs: [String]
    ) -> TaskSuggestion? {
        // Extract JSON block
        let raw = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = json["title"] as? String, !title.isEmpty,
              let intent = json["intent"] as? String
        else { return nil }

        let confidence = (json["confidence"] as? Double).map { Float($0) } ?? 0.5
        let files     = json["files"]    as? [String] ?? []
        let contacts  = json["contacts"] as? [String] ?? []
        let urls      = json["urls"]     as? [String] ?? fallbackURLs

        let context = TaskContext(files: files, contacts: contacts, urls: urls, rawOCR: screenText)

        var promptParts = ["Task: \(title)"]
        if !files.isEmpty    { promptParts.append("Files: \(files.joined(separator: ", "))") }
        if !contacts.isEmpty { promptParts.append("Contacts: \(contacts.joined(separator: ", "))") }
        if !urls.isEmpty     { promptParts.append("URLs: \(urls.joined(separator: ", "))") }
        promptParts.append("Screen context: \(String(screenText.prefix(200)))")
        promptParts.append("Complete this task. Ask for any missing required information.")

        return TaskSuggestion(
            id: UUID().uuidString,
            title: title,
            intent: intent,
            detectedContext: context,
            executionPrompt: promptParts.joined(separator: "\n"),
            confidence: confidence
        )
    }
}
```

- [ ] **Step 2: Check CapabilityStore.suggest signature**

Read `Sources/CapabilityStore.swift` and find the `suggest` method. Confirm it accepts `urls: [String]` (with default `= []`). If the parameter is absent, add `urls: [String] = []` to the signature and pass it into the URL-pattern scoring logic.

If a change was needed:
```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
git add Sources/CapabilityStore.swift
git commit -m "fix: add urls parameter to CapabilityStore.suggest"
```

- [ ] **Step 3: Build**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd" && make 2>&1 | grep "error:" | head -20
```

Expected: `SuggestionPipeline.swift` compiles cleanly. Outstanding errors should only be in files not yet updated (LearnModeService, AppState, etc.).

- [ ] **Step 4: Commit**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
git add Sources/SuggestionPipeline.swift
git commit -m "feat: create SuggestionPipeline with capability scoring and Llama task extraction"
```

---

## Chunk 2: Canvas Intelligence — LearnModeService

### Task 3: Rewrite recordEvent() with app+URL node keying

**Files:**
- Modify: `Sources/LearnModeService.swift`

- [ ] **Step 1: Add OCR overlap helper**

At the bottom of `LearnModeService` (before the final `}`), add:

```swift
// MARK: - OCR Deduplication

/// Returns the character-level overlap ratio between two strings (0.0–1.0).
/// Uses character counts (with duplicates), not unique-character sets, so that
/// two different screens sharing a common alphabet don't falsely score as identical.
/// Formula: common / max(a.count, b.count) where common = characters in the shorter
/// string that also appear in the longer (approximated by counting shared chars).
private func ocrOverlap(_ a: String, _ b: String) -> Double {
    guard !a.isEmpty, !b.isEmpty else { return 0 }
    // Build frequency maps and count matching characters
    var freqA = [Character: Int]()
    for ch in a { freqA[ch, default: 0] += 1 }
    var common = 0
    var freqB = [Character: Int]()
    for ch in b {
        freqB[ch, default: 0] += 1
        if let countA = freqA[ch], freqB[ch]! <= countA { common += 1 }
    }
    return Double(common) / Double(max(a.count, b.count))
}
```

- [ ] **Step 2: Rewrite recordEvent()**

Find the existing `recordEvent()` method and replace its body entirely:

```swift
private func recordEvent() async {
    guard var sess = session else { return }

    let app  = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
    let url  = screenAnalyzer?.detectedURLs.first
    let ocr  = screenAnalyzer?.recentContext() ?? ""
    let speech = latestSpeechFragment
    latestSpeechFragment = ""  // consume

    // Determine if this (app, url) matches the most recent node
    if let lastIndex = sess.nodes.indices.last,
       sess.nodes[lastIndex].app == app,
       sess.nodes[lastIndex].url == url {

        // Same app+URL — update in place if OCR changed meaningfully
        let lastOCR = sess.nodes[lastIndex].ocrSnapshots.last ?? ""
        let overlap = ocrOverlap(ocr, lastOCR)
        if overlap < 0.5, !ocr.isEmpty {
            sess.nodes[lastIndex].ocrSnapshots.append(ocr)
            sess.nodes[lastIndex].lastUpdated = Date()
        }
        if !speech.isEmpty {
            sess.nodes[lastIndex].speechSnippets.append(speech)
        }
    } else {
        // New app+URL — create a new node
        let node = CanvasNode(
            id: UUID().uuidString,
            app: app,
            url: url,
            ocrSnapshots: ocr.isEmpty ? [] : [ocr],
            speechSnippets: speech.isEmpty ? [] : [speech],
            workSummary: nil,
            capturedAt: Date(),
            lastUpdated: Date()
        )
        sess.nodes.append(node)
        Log.info(.ui, "LearnMode: new node — \(app) \(url ?? "(no URL)")")
    }

    session = sess
}
```

**Note:** `screenAnalyzer?.detectedURLs` — check if `ScreenVisionAnalyzer` exposes a `detectedURLs` property. If not, use `screenAnalyzer?.recentURLs` or derive URLs from OCR using `extractURLs(from: ocr)`. Adjust the property name to match the actual API.

- [ ] **Step 3: Build**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd" && make 2>&1 | grep "error:" | head -20
```

Fix any property-name mismatches for `ScreenVisionAnalyzer`. After this step, `recordEvent()` compiles cleanly. However, `buildUserJourney()` in `LearnModeService` still references `session.events` and will produce errors until Task 4 Step 4. `AICanvasView` errors also remain until Task 7. This is expected — do not attempt a full clean build until Task 7.

- [ ] **Step 4: Commit**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
git add Sources/LearnModeService.swift
git commit -m "feat: rewrite recordEvent() with app+URL node keying and OCR deduplication"
```

---

### Task 4: Add Llama summarisation pass + update buildUserJourney()

**Files:**
- Modify: `Sources/LearnModeService.swift`

- [ ] **Step 1: Add OllamaService instance to LearnModeService**

At the top of the class body (with other properties), add:

```swift
private let ollama = OllamaService()
```

- [ ] **Step 2: Add summariseNodes() method**

Add this method before `buildCapability()`:

```swift
/// Runs a Llama pass on each node to generate a one-sentence work summary.
/// Mutations to session.nodes happen on @MainActor after the async group completes.
private func summariseNodes() async {
    guard var sess = session else { return }
    let nodes = sess.nodes

    // Separate nodes: those needing Llama vs those getting a default (too little OCR).
    // Fallback defaults are collected first; Llama results are appended after the group.
    var summaries: [(id: String, summary: String)] = []

    let nodesToSummarise = nodes.filter { $0.workSummary == nil }
    for node in nodesToSummarise {
        let combinedOCR = node.ocrSnapshots.joined(separator: " | ")
        if combinedOCR.count < 20 {
            summaries.append((node.id, "Opened \(node.app)"))  // default, no Llama needed
        }
    }
    let llamaNodes = nodesToSummarise.filter { $0.ocrSnapshots.joined(separator: " | ").count >= 20 }

    // Run Llama calls in parallel; each task returns (id, summary) — no direct struct mutation.
    // All mutations to sess.nodes happen after the group on @MainActor (avoids stale-copy trap).
    await withTaskGroup(of: (String, String).self) { group in
        for node in llamaNodes {
            let combinedOCR = node.ocrSnapshots.joined(separator: " | ")
            let appName = node.app
            let urlStr = node.url.map { " (\($0))" } ?? ""
            let speech = node.speechSnippets.joined(separator: " · ")
            let fallback = "Worked in \(appName)"
            // Capture ollama reference — do NOT use self inside the task body
            let ollamaRef = ollama
            group.addTask {
                let prompt = """
                In one sentence, what was the user doing in \(appName)\(urlStr)?
                OCR: \(String(combinedOCR.prefix(400)))
                Speech: \(speech)
                One sentence only.
                """
                do {
                    let result = try await ollamaRef.generate(prompt: prompt, numPredict: 64)
                    let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (node.id, trimmed.isEmpty ? fallback : trimmed)
                } catch {
                    return (node.id, fallback)
                }
            }
        }
        for await pair in group {
            summaries.append(pair)
        }
    }

    // Apply all summaries back on @MainActor (never mutate inside task body — stale copy trap)
    for (id, summary) in summaries {
        if let idx = sess.nodes.firstIndex(where: { $0.id == id }) {
            sess.nodes[idx].workSummary = summary
        }
    }
    session = sess
}
```

- [ ] **Step 3: Update buildCapability() to call summariseNodes() before buildUserJourney()**

In `buildCapability()`, find the call to `buildUserJourney()`. Just before it, insert:

```swift
// Summarise each node before assembling the journey narrative
await summariseNodes()
```

- [ ] **Step 4: Rewrite buildUserJourney() to use node workSummaries**

Find `buildUserJourney()` and replace its body:

```swift
private func buildUserJourney() -> String {
    guard let sess = session else { return "" }
    var lines: [String] = []
    for (i, node) in sess.nodes.enumerated() {
        let elapsed = Int(node.capturedAt.timeIntervalSince(sess.startedAt))
        let summary = node.workSummary ?? "Opened \(node.app)"
        lines.append("T+\(elapsed)s → \(summary) [\(node.displayTitle)]")
    }
    return lines.joined(separator: "\n")
}
```

- [ ] **Step 5: Tighten FUCBC prompt for well-formed subWorkflows**

Find `buildFUCBCPrompt()`. Locate the section that describes the JSON output format (where it lists `subWorkflows`). Add this constraint immediately before the closing of the JSON format description:

```
IMPORTANT: Always output at least 2 subWorkflows. Every subWorkflow must have a non-empty "name" AND a non-empty "invocation" (a shell command or skill slug). Never output a subWorkflow with blank fields.
```

- [ ] **Step 6: Build**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd" && make 2>&1 | grep "error:" | head -20
```

- [ ] **Step 7: Commit**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
git add Sources/LearnModeService.swift
git commit -m "feat: add Llama node summarisation pass and update buildUserJourney to use workSummaries"
```

---

## Chunk 3: Integration — AppState + Toast

### Task 5: Update AppState.swift

**Files:**
- Modify: `Sources/AppState.swift`

- [ ] **Step 1: Add SuggestionPipeline instance**

In AppState, near the other service singletons (around the line where `learnModeService` is declared), add:

```swift
let suggestionPipeline = SuggestionPipeline()
```

- [ ] **Step 2: Update detectedSuggestion type**

Find (around line 166):
```swift
@Published var detectedSuggestion: SuggestionMatch? = nil
```
Replace with:
```swift
@Published var detectedSuggestion: SuggestionItem? = nil
```

- [ ] **Step 3: Rename dismissDetectedCapability() → dismissDetectedSuggestion()**

Find:
```swift
func dismissDetectedCapability() {
    detectedSuggestion = nil
}
```
Replace with:
```swift
func dismissDetectedSuggestion() {
    detectedSuggestion = nil
}
```

Search the whole file for any other call sites of `dismissDetectedCapability()` and update them.

- [ ] **Step 4: Update detectedSuggestion = nil in executeCapability()**

Find `func executeCapability(_ capability: Capability)`. At the top of its body (line ~1275) there is:
```swift
detectedSuggestion = nil
```
This line is already typed correctly after the property type change. Verify it compiles — no logic change needed.

- [ ] **Step 5: Add executeSuggestedTask()**

After `executeCapability()`, add:

```swift
func executeSuggestedTask(_ task: TaskSuggestion) {
    detectedSuggestion = nil
    guard let project = projects.first else {
        Log.warn(.pipeline, "executeSuggestedTask: no project available")
        return
    }

    let taskID = "TASK-\(String(UUID().uuidString.prefix(8)).uppercased())"
    let record = PipelineTaskRecord(
        id: taskID,
        analysisID: "task-\(taskID)",
        title: "⚡ \(task.title)",
        prompt: task.executionPrompt,
        projectID: project.id,
        projectName: project.name,
        mode: .auto,
        status: .ongoing,
        workflowSteps: [task.intent]
    )

    pipelineTasks.insert(record, at: 0)
    resetCodeWidget()

    guard let (session, stream) = claudeCodeRunner.startSession(
        prompt: task.executionPrompt,
        in: project,
        dangerouslySkipPermissions: true
    ) else { return }

    codeSession = session
    codeSessionMessages.append(CodeMessage(role: .status, text: "⚡ \(task.title)"))
    codeStreamTask = Task { @MainActor in
        await processCodeStream(stream)
    }
    Log.info(.pipeline, "Task execution started: \(task.title) in \(project.name)")
}
```

**Note:** Match the `PipelineTaskRecord` init signature exactly to what exists in `PipelineModels.swift`. If the init has different parameter names or a different shape, adjust accordingly. `resetCodeWidget()` — if this helper doesn't exist, inline the equivalent: set `codeSessionMessages = []`, `isCodeStreaming = false`, `activeToolName = nil`.

- [ ] **Step 6: Update the OCR frame callback to use SuggestionPipeline**

Find the OCR frame callback (around line 628–644). Replace:

```swift
let matches = CapabilityStore.shared.suggest(screenText: ocrText, app: app)
self.detectedSuggestion = matches.first
```

With:

```swift
let item = await self.suggestionPipeline.evaluate(
    screenText: ocrText,
    transcript: self.liveTranscriptText,
    app: app,
    urls: self.screenVisionAnalyzer.detectedURLs,
    isOllamaEnabled: self.isOllamaEnabled
)
self.detectedSuggestion = item
```

**Note:** `self.screenVisionAnalyzer.detectedURLs` — verify this property exists on `ScreenVisionAnalyzer`. If not, use an empty array `[]` or the correct property name.

- [ ] **Step 7: Build**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd" && make 2>&1 | grep "error:" | head -30
```

Expected: Errors will point to `AppDelegate` calling the old `dismissDetectedCapability()` and `showCapabilityToast` (fixed in Task 10), and `ToastWindow` type mismatches (fixed in Task 6). AppState itself should compile.

- [ ] **Step 8: Commit**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
git add Sources/AppState.swift
git commit -m "feat: wire SuggestionPipeline into AppState, add executeSuggestedTask, update OCR callback"
```

---

### Task 6: Update ToastWindow + CapabilityToastView

**Files:**
- Modify: `Sources/ToastWindow.swift`
- Modify: `Sources/ToastView.swift`

- [ ] **Step 1: Update CapabilityToastModel in ToastWindow.swift**

Find the `CapabilityToastModel` class/struct at the top of `ToastWindow.swift`. Change:

```swift
// Before
@Published var match: SuggestionMatch? = nil

// After
@Published var item: SuggestionItem? = nil
```

Update all references to `capModel.match` → `capModel.item` within `ToastWindow`.

- [ ] **Step 2: Rename showCapability() → show()**

Find:
```swift
func showCapability(_ match: SuggestionMatch, onTap: ..., onSnooze: ..., onMarkIrrelevant: ...)
```

Replace with:
```swift
func show(_ item: SuggestionItem, onTap: @escaping () -> Void, onSnooze: @escaping () -> Void, onMarkIrrelevant: @escaping () -> Void) {
    capModel.item = item
    // ... rest of existing body, replacing `match` with `item`
}
```

- [ ] **Step 3: Update CapabilityToastView in ToastView.swift to accept SuggestionItem**

Find `struct CapabilityToastView`. Change its input from `SuggestionMatch` to `SuggestionItem`.

The view currently takes a `SuggestionMatch`. Replace the input property and add branching:

```swift
struct CapabilityToastView: View {
    let item: SuggestionItem
    let onTap: () -> Void
    let onSnooze: () -> Void
    let onMarkIrrelevant: () -> Void

    var body: some View {
        switch item {
        case .capability(let match):
            capabilityBody(match: match)
        case .task(let task):
            taskBody(task: task)
        }
    }

    // MARK: Capability rendering (existing layout, with blank-subWorkflow fix)
    private func capabilityBody(match: SuggestionMatch) -> some View {
        let capability = match.capability
        // Filter blank subWorkflows before rendering
        let steps = capability.subWorkflows.filter { !$0.name.isEmpty }
        let stepCount = steps.isEmpty ? 1 : steps.count

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                ToolIconStrip(triggers: capability.triggers, subWorkflows: steps)
                Spacer()
                Button(action: onSnooze) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
            }
            Text(match.contextualHeadline)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Glass.textPrimary)
            Text("AutoClawd can automate this · \(stepCount) step\(stepCount == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundColor(Glass.textSecondary)
            HStack {
                Button("Run now", action: onTap)
                    .buttonStyle(GlassButton())
                Spacer()
                Button(action: onMarkIrrelevant) { Text("👎") }
                    .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.25), radius: 12)
    }

    // MARK: Task rendering (new)
    private func taskBody(task: TaskSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Intent chip
                Label(task.intent, systemImage: "bolt.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.blue.opacity(0.18))
                    .clipShape(Capsule())
                    .foregroundColor(.blue)
                Spacer()
                Button(action: onSnooze) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
            }
            Text(task.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Glass.textPrimary)
            // Context chips
            if task.detectedContext.isComplete {
                contextChips(task.detectedContext)
            }
            HStack(spacing: 8) {
                Button("Run", action: onTap)
                    .buttonStyle(GlassButton())
                if !task.detectedContext.isComplete {
                    Button("Add context →") { onTap() } // opens canvas — handled by caller
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(Glass.textSecondary)
                }
                Spacer()
                Button(action: onMarkIrrelevant) { Text("👎") }
                    .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.25), radius: 12)
    }

    @ViewBuilder
    private func contextChips(_ context: TaskContext) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(context.files, id: \.self) { f in
                    GlassChip(label: "📎 \(f)")
                }
                ForEach(context.contacts, id: \.self) { c in
                    GlassChip(label: "👤 \(c)")
                }
                ForEach(context.urls.prefix(2), id: \.self) { u in
                    GlassChip(label: "🔗 \(URL(string: u)?.host ?? u)")
                }
            }
        }
    }
}
```

**Note:** Preserve the existing `ToolIconStrip` and `AppIconView` components unchanged. The `GlassChip` and `GlassButton` components exist in `LiquidGlass.swift`. If `GlassButton` requires a different init, use the existing pattern from other views.

**Note on "Add context →":** The `onTap` callback in `AppDelegate` will be updated in Task 10 to check the suggestion type — for tasks with incomplete context it will open the Canvas panel instead of executing directly.

- [ ] **Step 4: Build**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd" && make 2>&1 | grep "error:" | head -30
```

Expected: Toast files compile. Remaining errors in AppDelegate (Task 10).

- [ ] **Step 5: Commit**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
git add Sources/ToastWindow.swift Sources/ToastView.swift
git commit -m "feat: update toast to render SuggestionItem (capability + task); fix blank subWorkflow rendering"
```

---

## Chunk 4: UI — AICanvasView + Monitor Window + AppDelegate

### Task 7: Update AICanvasView.swift

**Files:**
- Modify: `Sources/AICanvasView.swift`

- [ ] **Step 1: Replace all session.events references with session.nodes**

Search for every occurrence of `session.events` in `AICanvasView.swift` and replace with `session.nodes`. Do the same for `event` (singular) loop variables where they refer to `LearnEvent` — rename to `node` and update property accesses:

Key replacements:
- `session.events.count` → `session.nodes.count`
- `session.hasEnoughContext` — already correct (updated in LearnModeModels)
- Loop `for event in session.events` → `for node in session.nodes`
- `event.appName` → `node.app`
- `event.ocrSnippet` → `node.ocrSnapshots.last ?? ""`
- `event.speechSnippet` → `node.speechSnippets.last ?? ""`
- `event.detectedURLs.first` → `node.url`
- `event.timestamp` → `node.capturedAt`

- [ ] **Step 2: Update node card body to show workSummary**

In the `eventNode()` or equivalent function that renders a single node card, find where it displays OCR/speech text. Replace the body text with:

```swift
// Show Llama summary if available; else latest OCR snippet with spinner
if let summary = node.workSummary {
    Text(summary)
        .font(.system(size: 11))
        .foregroundColor(Glass.textSecondary)
        .lineLimit(2)
} else {
    HStack(spacing: 4) {
        ProgressView().scaleEffect(0.6)
        Text(node.ocrSnapshots.last.map { String($0.prefix(60)) } ?? "Capturing…")
            .font(.system(size: 11))
            .foregroundColor(Glass.textTertiary)
            .lineLimit(1)
    }
}
```

- [ ] **Step 3: Build**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd" && make 2>&1 | grep "error:" | head -30
```

Expected: AICanvasView compiles. Remaining errors should only be in AppDelegate.

- [ ] **Step 4: Commit**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
git add Sources/AICanvasView.swift
git commit -m "feat: update AICanvasView to render CanvasNode list with workSummary"
```

---

### Task 8: Create LearnModeMonitorView.swift + LearnModeMonitorWindow.swift

**Files:**
- Create: `Sources/LearnModeMonitorView.swift`
- Create: `Sources/LearnModeMonitorWindow.swift`

- [ ] **Step 1: Create LearnModeMonitorView.swift**

```swift
// Sources/LearnModeMonitorView.swift
import SwiftUI

struct LearnModeMonitorView: View {
    @ObservedObject var service: LearnModeService

    var body: some View {
        VStack(spacing: 0) {
            header
            GlassDivider()
            nodeList
            GlassDivider()
            buildButton
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            CanvasPulsingDot()
            Text("Recording")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Glass.textPrimary)
            Text("·")
                .foregroundColor(Glass.textTertiary)
            Text("\(service.session?.nodes.count ?? 0) node\(nodeCount == 1 ? "" : "s")")
                .font(.system(size: 12))
                .foregroundColor(Glass.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var nodeCount: Int { service.session?.nodes.count ?? 0 }

    // MARK: - Node List

    private var nodeList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let nodes = service.session?.nodes, !nodes.isEmpty {
                    ForEach(nodes) { node in
                        nodeRow(node)
                        GlassDivider()
                    }
                } else {
                    Text("Watching your screen…")
                        .font(.system(size: 12))
                        .foregroundColor(Glass.textTertiary)
                        .padding(20)
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private func nodeRow(_ node: CanvasNode) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AppIconView(appName: node.app, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.app)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Glass.textPrimary)
                Text(node.displayTitle)
                    .font(.system(size: 10))
                    .foregroundColor(Glass.textSecondary)
                    .lineLimit(1)
                if let summary = node.workSummary {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundColor(Glass.textTertiary)
                        .lineLimit(2)
                } else {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.55)
                        Text("Capturing…")
                            .font(.system(size: 11))
                            .foregroundColor(Glass.textTertiary)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Build Button

    private var buildButton: some View {
        Button {
            Task { await service.buildCapability() }
        } label: {
            Text("Stop & Build")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassButton())
        .disabled(service.session?.phase == .building)
        .padding(12)
    }
}
```

**Note:** `CanvasPulsingDot` and `AppIconView` already exist in `AICanvasView.swift`. If `CanvasPulsingDot` is defined inside `AICanvasView` as a private struct, move it to its own file or make it `internal` so `LearnModeMonitorView` can use it. Alternatively, inline a simple pulsing dot: `Circle().fill(Color.red).frame(width: 8, height: 8)` with a `@State` animation.

**Note:** `LearnPhase.building` — check the exact enum case name in `LearnModeModels.swift`. If it's `.building`, the comparison `service.session?.phase == .building` works directly. If `LearnPhase` isn't `Equatable`, add `Equatable` conformance or compare via pattern matching.

- [ ] **Step 2: Create LearnModeMonitorWindow.swift**

```swift
// Sources/LearnModeMonitorWindow.swift
import AppKit
import SwiftUI

final class LearnModeMonitorWindow: NSPanel {

    init(service: LearnModeService) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 420),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true

        let view = LearnModeMonitorView(service: service)
        contentView = NSHostingView(rootView: view)

        positionTopRight()
    }

    private func positionTopRight() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let windowWidth: CGFloat = 320
        let windowHeight: CGFloat = 420
        let x = screenFrame.maxX - windowWidth - 16
        let y = screenFrame.maxY - windowHeight - 80  // below toast zone
        setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: false)
    }
}
```

- [ ] **Step 3: Build**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd" && make 2>&1 | grep "error:" | head -30
```

Fix any missing symbol errors (e.g. `CanvasPulsingDot` visibility, `LearnPhase` equatability).

- [ ] **Step 4: Commit**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
git add Sources/LearnModeMonitorView.swift Sources/LearnModeMonitorWindow.swift
git commit -m "feat: add LearnModeMonitorView and LearnModeMonitorWindow for live node capture display"
```

---

### Task 9: Wire AppDelegate.swift

**Files:**
- Modify: `Sources/AppDelegate.swift`

- [ ] **Step 1: Add monitorWindow property**

Near the other window properties at the top of `AppDelegate`, add:

```swift
private var monitorWindow: LearnModeMonitorWindow?
```

- [ ] **Step 2: Initialise monitorWindow in applicationDidFinishLaunching**

After the existing window initialisations (e.g. after `mainPanelWindow = MainPanelWindow(appState: appState)`), add:

```swift
monitorWindow = LearnModeMonitorWindow(service: appState.learnModeService)
```

- [ ] **Step 3: Wire pillMode Combine sink to show/hide monitor window**

Find the existing `appState.$pillMode` Combine sink in `AppDelegate` (or `applicationDidFinishLaunching`). Inside it, add the monitor window toggle:

```swift
appState.$pillMode
    .receive(on: DispatchQueue.main)
    .sink { [weak self] mode in
        guard let self else { return }
        if mode == .learn {
            self.monitorWindow?.orderFront(nil)
        } else {
            self.monitorWindow?.orderOut(nil)
        }
    }
    .store(in: &cancellables)
```

If no existing `pillMode` sink exists, add this as a new sink alongside others.

- [ ] **Step 4: Rename showCapabilityToast → showSuggestionToast**

Find:
```swift
private func showCapabilityToast(_ match: SuggestionMatch) { ... }
```

Replace with:
```swift
private func showSuggestionToast(_ item: SuggestionItem) {
    toastWindow.show(item,
        onTap: { [weak self] in
            guard let self else { return }
            switch item {
            case .capability(let match):
                self.appState.executeCapability(match.capability)
                self.mainPanelWindow.orderFront(nil)
            case .task(let task):
                if task.detectedContext.isComplete {
                    self.appState.executeSuggestedTask(task)
                } else {
                    // Open canvas panel for context gap-filling
                    self.appState.selectedTab = .canvas
                    self.mainPanelWindow.orderFront(nil)
                }
            }
        },
        onSnooze: { [weak self] in
            if case .capability(let match) = item {
                CapabilityStore.shared.snooze(capabilityID: match.capability.id)
            }
            self?.appState.dismissDetectedSuggestion()
        },
        onMarkIrrelevant: { [weak self] in
            if case .capability(let match) = item {
                CapabilityStore.shared.markIrrelevant(capabilityID: match.capability.id)
            }
            self?.appState.dismissDetectedSuggestion()
        }
    )
}
```

- [ ] **Step 5: Update the detectedSuggestion sink to call showSuggestionToast**

Find the existing Combine sink that observes `appState.$detectedSuggestion` (or `appState.$detectedCapability`). Update it:

```swift
appState.$detectedSuggestion
    .receive(on: DispatchQueue.main)
    .sink { [weak self] item in
        guard let self else { return }
        if let item = item {
            self.showSuggestionToast(item)
        } else {
            self.toastWindow.dismiss()
        }
    }
    .store(in: &cancellables)
```

- [ ] **Step 6: Update any remaining call sites**

Search `AppDelegate.swift` for `showCapabilityToast`, `dismissDetectedCapability`, and `detectedCapability`. Update all occurrences to the new names.

- [ ] **Step 7: Full build — expect clean compile**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd" && make 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **` with no errors. If there are remaining type errors, they are in the files touched above — resolve them before committing.

- [ ] **Step 8: Commit**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
git add Sources/AppDelegate.swift
git commit -m "feat: wire LearnModeMonitorWindow lifecycle, showSuggestionToast, task/capability dispatch in AppDelegate"
```

---

### Task 10: Smoke test

- [ ] **Step 1: Run the app**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd" && make run
```

- [ ] **Step 2: Verify capability toast fix**

If any FUCBC-built capabilities exist in `~/.autoclawd/capabilities/index.json`, navigate to an app that triggers one. Confirm:
- Toast appears with correct step count (no blanks)
- App icon strip shows real icons (not empty slots)

- [ ] **Step 3: Verify Learn Mode monitor window**

Switch pill to Learn Mode. Confirm:
- `LearnModeMonitorWindow` appears in the top-right corner
- It shows "● Recording · 0 nodes" initially
- After ~10s of using different apps/URLs, nodes appear in the list
- Nodes do NOT duplicate when staying on the same screen
- "Stop & Build" button is enabled and calls buildCapability()

Switch out of Learn Mode. Confirm monitor window hides.

- [ ] **Step 4: Verify task suggestions appear in toast**

Speak a clear task aloud while the app is running (e.g. "I need to send the report to Josh"). Within the next OCR frame cycle, confirm:
- Toast appears with ⚡ intent chip instead of the capability multi-step layout
- Task title is extracted correctly
- "Run" and/or "Add context →" buttons are present

- [ ] **Step 5: Final commit if any fixes were needed**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
git add -p  # stage only intentional changes
git commit -m "fix: smoke test fixes"
```
