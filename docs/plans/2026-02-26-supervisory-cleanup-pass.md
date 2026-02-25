# Supervisory Cleanup Pass (Pass 3) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Pass 3 — a supervisory LLM cleanup that rewrites world-model.md and todos.md (removing duplicates and generating dev todos), and collapses duplicate Intelligence DB items into canonical entries.

**Architecture:** Two-call `CleanupService` wired as a dependency of `ExtractionService` (auto-runs after every Pass 2 synthesis) and directly on `AppState` (manual "Clean Up" button in the Intelligence view header).

**Tech Stack:** Swift 5.9, SwiftUI, SQLite3 (via existing wrappers), OllamaService (already in project)

---

### Task 1: Add `collapse` method to ExtractionStore

**Files:**
- Modify: `Sources/ExtractionStore.swift`

**Step 1: Add public method stub after `markApplied`**

Add this after the `markApplied` method (around line 47):

```swift
func collapse(keepId: String, canonical: String, dropIds: [String]) {
    queue.async { [self] in
        self.updateContent(id: keepId, content: canonical)
        self.deleteItems(ids: dropIds)
    }
}
```

**Step 2: Add two private helpers after `updateApplied`**

Add these private methods after `updateApplied` (after line 178):

```swift
private func updateContent(id: String, content: String) {
    let sql = "UPDATE extraction_items SET content = ? WHERE id = ?;"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
    defer { sqlite3_finalize(stmt) }
    sqlite3_bind_text(stmt, 1, content, -1, SQLITE_TRANSIENT_ES)
    sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT_ES)
    let result = sqlite3_step(stmt)
    if result != SQLITE_DONE {
        Log.error(.system, "ExtractionStore updateContent failed: \(result)")
    }
}

private func deleteItems(ids: [String]) {
    let sql = "DELETE FROM extraction_items WHERE id = ?;"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
    defer { sqlite3_finalize(stmt) }
    for id in ids {
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT_ES)
        let result = sqlite3_step(stmt)
        if result != SQLITE_DONE {
            Log.error(.system, "ExtractionStore deleteItems failed for id \(id): \(result)")
        }
        sqlite3_reset(stmt)
    }
}
```

**Step 3: Build to verify no errors**

```bash
cd /Users/sameeprehlan/Documents/Claude\ Code/autoclawd/.claude/worktrees/pedantic-proskuriakova
swift build 2>&1 | tail -5
```
Expected: `Build complete!`

**Step 4: Commit**

```bash
git add Sources/ExtractionStore.swift
git commit -m "feat: add collapse method to ExtractionStore"
```

---

### Task 2: Add `.cleanup` log component

**Files:**
- Modify: `Sources/Logger.swift`

**Step 1: Add case to `LogComponent` enum**

In `Logger.swift`, find the `LogComponent` enum (around line 20). Add `case cleanup = "CLEANUP"` after `case qa = "QA"`:

```swift
case qa        = "QA"
case cleanup   = "CLEANUP"
```

**Step 2: Build**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`

**Step 3: Commit**

```bash
git add Sources/Logger.swift
git commit -m "feat: add cleanup log component"
```

---

### Task 3: Create CleanupService

**Files:**
- Create: `Sources/CleanupService.swift`

**Step 1: Create the file with this exact content**

```swift
import Foundation

// MARK: - CleanupService
//
// Pass 3: Supervisory cleanup — two focused LLM calls.
//   Call 1: Rewrite world-model.md + todos.md (deduplicate + generate dev todos).
//   Call 2: Collapse duplicate ExtractionItems in DB into canonical entries.

final class CleanupService: @unchecked Sendable {
    private let ollama: OllamaService
    private let worldModel: WorldModelService
    private let todos: TodoService
    private let store: ExtractionStore

    init(ollama: OllamaService,
         worldModel: WorldModelService,
         todos: TodoService,
         store: ExtractionStore) {
        self.ollama = ollama
        self.worldModel = worldModel
        self.todos = todos
        self.store = store
    }

    func cleanup() async {
        Log.info(.cleanup, "Pass 3 start")
        async let call1: Void = rewriteKnowledge()
        async let call2: Void = collapseItems()
        _ = await (call1, call2)
        Log.info(.cleanup, "Pass 3 complete")
    }

    // MARK: - Call 1: Knowledge Rewrite

    private func rewriteKnowledge() async {
        let currentWorld = worldModel.read()
        let currentTodos = todos.read()

        let dateStr: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()

        let prompt = """
You are a supervisory AI managing a personal knowledge base.

TODAY: \(dateStr)

CURRENT WORLD MODEL:
\(currentWorld)

CURRENT TO-DO LIST:
\(currentTodos)

Your tasks:
1. Rewrite the world model into clean structured markdown. Use these sections: ## People, ## Projects, ## Plans, ## Preferences, ## Decisions. Merge near-duplicates into one clear fact per line. Fix any malformed lines or stray punctuation.
2. Rewrite the to-do list. Merge near-duplicate todos into one canonical entry per intent. Organize by ## HIGH, ## MEDIUM, ## LOW, ## DONE.
3. Analyze the world model and todos for gaps, missing action items, or improvements needed in the AutoClawd app. Add these as new todos under the appropriate priority section.

Output ONLY the two XML blocks below. No explanation. No markdown outside the tags. Start immediately with <WORLD_MODEL>.

<WORLD_MODEL>
[rewritten world model]
</WORLD_MODEL>
<TODOS>
[rewritten todos including new dev todos]
</TODOS>
"""

        let response: String
        do {
            response = try await ollama.generate(prompt: prompt, numPredict: 2048)
        } catch {
            Log.error(.cleanup, "Call 1 Ollama error: \(error.localizedDescription)")
            return
        }

        let updatedWorld = extract(from: response, tag: "WORLD_MODEL")
        let updatedTodos = extract(from: response, tag: "TODOS")

        if updatedWorld == nil && updatedTodos == nil {
            let preview = String(response.prefix(200)).replacingOccurrences(of: "\n", with: " ")
            Log.error(.cleanup, "Call 1: XML tags missing. Preview: \(preview)")
            return
        }

        if let w = updatedWorld, !w.isEmpty {
            worldModel.write(w)
            Log.info(.cleanup, "World model rewritten (\(w.count) chars)")
        }

        if let t = updatedTodos, !t.isEmpty {
            todos.write(t)
            Log.info(.cleanup, "Todos rewritten (\(t.count) chars)")
        }
    }

    // MARK: - Call 2: Intelligence Item Collapsing

    private func collapseItems() async {
        let all = store.all()
        guard all.count > 1 else {
            Log.info(.cleanup, "Call 2: fewer than 2 items, skipping collapse")
            return
        }

        // Feed all items as a flat list: id | bucket | type | content
        let itemList = all.map { "\($0.id) | \($0.bucket.rawValue) | \($0.type.rawValue) | \($0.content)" }
            .joined(separator: "\n")

        let prompt = """
You are deduplicating a list of extracted knowledge items.

ITEMS (format: id | bucket | type | content):
\(itemList)

Find groups of items that express the same idea (same fact or same action).
For each group of 2+ near-duplicates, output ONE line:
<canonical text> | <id to keep> | <comma-separated ids to drop>

Rules:
- Only output lines for groups that have duplicates.
- The canonical text should be the clearest, most complete version.
- If an item is unique, do NOT output anything for it.
- No header. No explanation. No blank lines.

Example:
User prefers dark mode | abc123 | def456,ghi789
"""

        let response: String
        do {
            response = try await ollama.generate(prompt: prompt, numPredict: 1024)
        } catch {
            Log.error(.cleanup, "Call 2 Ollama error: \(error.localizedDescription)")
            return
        }

        var collapseCount = 0
        let lines = response.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.components(separatedBy: " | ")
            guard parts.count >= 3 else { continue }

            let canonical = parts[0].trimmingCharacters(in: .whitespaces)
            let keepId    = parts[1].trimmingCharacters(in: .whitespaces)
            let dropIds   = parts[2].components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard !canonical.isEmpty, !keepId.isEmpty, !dropIds.isEmpty else { continue }

            // Verify keepId exists in our item list to avoid LLM hallucinations
            guard all.contains(where: { $0.id == keepId }) else {
                Log.warn(.cleanup, "Call 2: keepId \(keepId) not found, skipping")
                continue
            }

            store.collapse(keepId: keepId, canonical: canonical, dropIds: dropIds)
            collapseCount += 1
            Log.info(.cleanup, "Collapsed \(dropIds.count) → 1: \"\(String(canonical.prefix(60)))\"")
        }

        Log.info(.cleanup, "Call 2 complete: \(collapseCount) groups collapsed")
    }

    // MARK: - Private Helpers

    private func extract(from text: String, tag: String) -> String? {
        let openTag  = "<\(tag)>"
        let closeTag = "</\(tag)>"
        guard let openRange  = text.range(of: openTag),
              let closeRange = text.range(of: closeTag),
              openRange.upperBound < closeRange.lowerBound
        else { return nil }
        return String(text[openRange.upperBound..<closeRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

**Step 2: Build**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`

**Step 3: Commit**

```bash
git add Sources/CleanupService.swift
git commit -m "feat: add CleanupService (Pass 3 supervisory cleanup)"
```

---

### Task 4: Wire CleanupService into ExtractionService (auto-trigger)

**Files:**
- Modify: `Sources/ExtractionService.swift`

**Step 1: Add `cleanupService` property and update init**

At the top of `ExtractionService`, the properties currently are:
```swift
private let ollama: OllamaService
private let worldModel: WorldModelService
private let todos: TodoService
private let store: ExtractionStore
```

Add `private let cleanupService: CleanupService` after `store`:
```swift
private let ollama: OllamaService
private let worldModel: WorldModelService
private let todos: TodoService
private let store: ExtractionStore
private let cleanupService: CleanupService
```

**Step 2: Update init signature**

Change the init from:
```swift
init(ollama: OllamaService, worldModel: WorldModelService, todos: TodoService, store: ExtractionStore) {
    self.ollama = ollama
    self.worldModel = worldModel
    self.todos = todos
    self.store = store
}
```

To:
```swift
init(ollama: OllamaService, worldModel: WorldModelService, todos: TodoService, store: ExtractionStore, cleanup: CleanupService) {
    self.ollama = ollama
    self.worldModel = worldModel
    self.todos = todos
    self.store = store
    self.cleanupService = cleanup
}
```

**Step 3: Call cleanup at the end of `synthesize()`**

Find the last line of `synthesize()`:
```swift
Log.info(.extract, "Pass 2 complete: \(pending.count) items applied")
```

Add the cleanup call after it:
```swift
Log.info(.extract, "Pass 2 complete: \(pending.count) items applied")
await cleanupService.cleanup()
```

**Step 4: Build — expect a compile error in AppState.swift**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: error about missing `cleanup:` argument in `AppState.swift` — that's fine, Task 5 will fix it.

**Step 5: Commit (skip build pass — AppState fix is next)**

```bash
git add Sources/ExtractionService.swift
git commit -m "feat: wire CleanupService into ExtractionService.synthesize"
```

---

### Task 5: Wire CleanupService into AppState + add cleanupNow()

**Files:**
- Modify: `Sources/AppState.swift`

**Step 1: Add `cleanupService` and `isCleaningUp` properties**

In `AppState`, find the services block (around line 69). After `private let extractionService: ExtractionService`, add:

```swift
private let cleanupService: CleanupService
```

In the `@Published` state section (around line 63), after `@Published var synthesizeThreshold`, add:

```swift
@Published var isCleaningUp = false
```

**Step 2: Update `init()` to build CleanupService and pass it to ExtractionService**

Find in `init()` (around line 107):
```swift
let exStore = ExtractionStore(url: FileStorageManager.shared.intelligenceDatabaseURL)
extractionStore = exStore
extractionService = ExtractionService(
    ollama: OllamaService(),
    worldModel: WorldModelService(),
    todos: TodoService(),
    store: exStore
)
```

Replace with:
```swift
let exStore = ExtractionStore(url: FileStorageManager.shared.intelligenceDatabaseURL)
extractionStore = exStore
let cleanupSvc = CleanupService(
    ollama: OllamaService(),
    worldModel: WorldModelService(),
    todos: TodoService(),
    store: exStore
)
cleanupService = cleanupSvc
extractionService = ExtractionService(
    ollama: OllamaService(),
    worldModel: WorldModelService(),
    todos: TodoService(),
    store: exStore,
    cleanup: cleanupSvc
)
```

**Step 3: Add `cleanupNow()` method**

Find the `synthesizeNow()` method (around line 238). Add `cleanupNow()` immediately after it:

```swift
func cleanupNow() async {
    isCleaningUp = true
    await cleanupService.cleanup()
    refreshExtractionItems()
    isCleaningUp = false
}
```

**Step 4: Build**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`

**Step 5: Commit**

```bash
git add Sources/AppState.swift
git commit -m "feat: add cleanupNow() and isCleaningUp to AppState"
```

---

### Task 6: Add "Clean Up" button to IntelligenceView

**Files:**
- Modify: `Sources/IntelligenceView.swift`

**Step 1: Add the button to the header HStack**

In `IntelligenceView.body`, find the header HStack (around line 13). It currently ends with:

```swift
Button("Synthesize Now") {
    Task { await appState.synthesizeNow() }
}
.disabled(appState.pendingExtractionCount == 0)
.buttonStyle(.bordered)
```

Add the "Clean Up" button right after (before the closing `}` of the HStack):

```swift
Button("Synthesize Now") {
    Task { await appState.synthesizeNow() }
}
.disabled(appState.pendingExtractionCount == 0)
.buttonStyle(.bordered)

Button("Clean Up") {
    Task { await appState.cleanupNow() }
}
.disabled(appState.isCleaningUp)
.buttonStyle(.bordered)
```

**Step 2: Build**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`

**Step 3: Commit**

```bash
git add Sources/IntelligenceView.swift
git commit -m "feat: add Clean Up button to IntelligenceView header"
```

---

### Task 7: Smoke test

**Step 1: Run the app**

```bash
open /Users/sameeprehlan/Documents/Claude\ Code/autoclawd/.claude/worktrees/pedantic-proskuriakova/build/autoclawd.app
```
Or build + run via Xcode.

**Step 2: Verify the button appears**

Open the main panel → Intelligence tab. Confirm "Clean Up" button is visible in the header next to "Synthesize Now".

**Step 3: Trigger manual cleanup**

Click "Clean Up". Wait ~10-30 seconds (two Ollama calls). Then:
```bash
cat ~/.autoclawd/world-model.md
cat ~/.autoclawd/todos.md
```
Expected: Clean structured markdown with no duplicates; todos deduplicated; new AutoClawd dev todos appended.

**Step 4: Verify logs**

```bash
tail -50 ~/.autoclawd/logs/autoclawd-$(date +%Y-%m-%d).log | grep CLEANUP
```
Expected lines like:
```
[CLEANUP] Pass 3 start
[CLEANUP] World model rewritten (N chars)
[CLEANUP] Todos rewritten (N chars)
[CLEANUP] Collapsed N → 1: "..."
[CLEANUP] Pass 3 complete
```

**Step 5: Final commit if any minor fixes needed, then done**

```bash
git log --oneline -8
```
