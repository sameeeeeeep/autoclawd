# Todo Framing via AI Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** When a hot-word or transcript "→ Todo" creates a task, immediately insert it as raw text, then silently rewrite it via Ollama (with project README/CLAUDE.md context) into a clean actionable title.

**Architecture:** New `TodoFramingService` actor handles context loading + LLM call. `AppState` fires framing as a background Task after insert. `StructuredTodoStore` gains `updateContent(id:content:)`. Both hot-word and transcript "→ Todo" paths are wired.

**Tech Stack:** Swift 5.9, `OllamaService` (already exists at `Sources/OllamaService.swift`), SQLite via raw C API, SwiftUI `@MainActor`. Build via `make` (swiftc, not SPM — no XCTest available). Smoke-test by running the app.

---

### Task 1: Add `updateContent(id:content:)` to `StructuredTodoStore`

**Files:**
- Modify: `Sources/StructuredTodoStore.swift` — add one method after the existing `setProject` method

**Step 1: Add the method**

In `Sources/StructuredTodoStore.swift`, find the `setProject` method (around line 61) and add directly after it:

```swift
func updateContent(id: String, content: String) {
    let sql = "UPDATE structured_todos SET content = ? WHERE id = ?;"
    queue.sync {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, content)
        bind(stmt, 2, id)
        sqlite3_step(stmt)
    }
}
```

**Step 2: Build**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd/.claire/worktrees/gracious-carson" 2>/dev/null || \
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd/.claude/worktrees/gracious-carson" && make 2>&1 | grep -E "error:|warning:|Built"
```
Expected: `Built build/AutoClawd.app` with 0 errors.

**Step 3: Commit**

```bash
git add Sources/StructuredTodoStore.swift
git commit -m "feat: add updateContent to StructuredTodoStore"
```

---

### Task 2: Create `TodoFramingService`

**Files:**
- Create: `Sources/TodoFramingService.swift`

**Step 1: Create the file**

```swift
// Sources/TodoFramingService.swift
import Foundation

/// Rewrites a raw spoken task payload into a clean, actionable title
/// using the local Ollama model with project README/CLAUDE.md as context.
actor TodoFramingService {

    private let ollama: OllamaService

    init(ollama: OllamaService) {
        self.ollama = ollama
    }

    /// Returns a framed task title, or `rawPayload` unchanged on any failure.
    func frame(rawPayload: String, for project: Project) async -> String {
        let context = loadContext(from: project.localPath)
        let prompt = buildPrompt(raw: rawPayload, projectName: project.name, context: context)

        do {
            // numPredict: 60 — title only, no long response needed
            let raw = try await withTimeout(seconds: 8) {
                try await self.ollama.generate(prompt: prompt, numPredict: 60)
            }
            let cleaned = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return cleaned.isEmpty ? rawPayload : cleaned
        } catch {
            Log.warn(.system, "TodoFramingService: framing failed — \(error). Using raw payload.")
            return rawPayload
        }
    }

    // MARK: - Private

    private func loadContext(from localPath: String) -> String {
        var parts: [String] = []
        for filename in ["README.md", "CLAUDE.md"] {
            let url = URL(fileURLWithPath: localPath).appendingPathComponent(filename)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                let truncated = String(text.prefix(1500))
                parts.append("[\(filename)]\n\(truncated)")
            }
        }
        return parts.joined(separator: "\n\n")
    }

    private func buildPrompt(raw: String, projectName: String, context: String) -> String {
        var p = """
        You are a task management assistant for a software project.
        Rewrite the raw spoken task as a single clean, actionable task title.
        Requirements: imperative mood, max 12 words, no filler words, no punctuation at end.
        Respond with ONLY the task title — no explanation, no quotes.

        Project: \(projectName)
        """
        if !context.isEmpty {
            p += "\n\nProject context:\n\(context)"
        }
        p += "\n\nRaw spoken task: \"\(raw)\""
        return p
    }
}

// MARK: - Timeout helper

/// Runs `operation` and cancels it if it takes longer than `seconds`.
private func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw CancellationError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
```

**Step 2: Build**

```bash
make 2>&1 | grep -E "error:|warning:|Built"
```
Expected: `Built build/AutoClawd.app` with 0 errors.

**Step 3: Commit**

```bash
git add Sources/TodoFramingService.swift
git commit -m "feat: add TodoFramingService for AI task framing"
```

---

### Task 3: Wire framing into `AppState` — hot-word `.addTodo` path

**Files:**
- Modify: `Sources/AppState.swift`

**Step 1: Add `todoFramingService` property**

In `Sources/AppState.swift`, find the existing line:
```swift
private let ollama = OllamaService()
```
Add immediately after it:
```swift
private lazy var todoFramingService = TodoFramingService(ollama: ollama)
```

**Step 2: Update the `.addTodo` case in `processHotWordMatches`**

Find this block (around line 536):
```swift
            case .addTodo:
                let inserted = structuredTodoStore.insert(
                    content: match.payload,
                    priority: "HIGH"
                )
                if let project = resolvedProject {
                    structuredTodoStore.setProject(id: inserted.id, projectID: project.id)
                }
                refreshStructuredTodos()
                Log.info(.todo, "Hot-word added todo: \(match.payload)")
```

Replace with:
```swift
            case .addTodo:
                let inserted = structuredTodoStore.insert(
                    content: match.payload,
                    priority: "HIGH"
                )
                if let project = resolvedProject {
                    structuredTodoStore.setProject(id: inserted.id, projectID: project.id)
                }
                refreshStructuredTodos()
                Log.info(.todo, "Hot-word added todo (raw): \(match.payload)")

                // Frame the task in background — updates content silently when done
                if let project = resolvedProject {
                    let todoID = inserted.id
                    let raw = match.payload
                    Task { [weak self] in
                        guard let self else { return }
                        let framed = await todoFramingService.frame(rawPayload: raw, for: project)
                        guard framed != raw else { return }
                        structuredTodoStore.updateContent(id: todoID, content: framed)
                        await MainActor.run { refreshStructuredTodos() }
                        Log.info(.todo, "Hot-word todo framed: \(framed)")
                    }
                }
```

**Step 3: Build**

```bash
make 2>&1 | grep -E "error:|warning:|Built"
```
Expected: `Built build/AutoClawd.app` with 0 errors.

**Step 4: Commit**

```bash
git add Sources/AppState.swift
git commit -m "feat: wire AI framing into hot-word addTodo path"
```

---

### Task 4: Wire framing into `AppState` — transcript "→ Todo" path

**Files:**
- Modify: `Sources/AppState.swift`

**Step 1: Update `addStructuredTodo`**

Find this method (around line 361):
```swift
    func addStructuredTodo(content: String, priority: String?) {
        _ = structuredTodoStore.insert(content: content, priority: priority)
        refreshStructuredTodos()
    }
```

Replace with:
```swift
    func addStructuredTodo(content: String, priority: String?, project: Project? = nil) {
        let inserted = structuredTodoStore.insert(content: content, priority: priority)
        if let project {
            structuredTodoStore.setProject(id: inserted.id, projectID: project.id)
        }
        refreshStructuredTodos()

        // Frame in background if we have a project for context
        guard let project else { return }
        let todoID = inserted.id
        Task { [weak self] in
            guard let self else { return }
            let framed = await todoFramingService.frame(rawPayload: content, for: project)
            guard framed != content else { return }
            structuredTodoStore.updateContent(id: todoID, content: framed)
            await MainActor.run { refreshStructuredTodos() }
        }
    }
```

**Step 2: Update the call site in `MainPanelView`**

In `Sources/MainPanelView.swift`, find the "→ Todo" button (around line 756):
```swift
                Button("→ Todo") {
                    appState.addStructuredTodo(content: record.text, priority: "MEDIUM")
                }
```

The transcript row has access to its assigned project. Find the `TranscriptRow` view — it already has a project picker. Pass the assigned project:

```swift
                Button("→ Todo") {
                    let proj = appState.projects.first(where: {
                        $0.id == record.projectID?.uuidString
                    })
                    appState.addStructuredTodo(content: record.text, priority: "MEDIUM", project: proj)
                }
```

**Step 3: Build**

```bash
make 2>&1 | grep -E "error:|warning:|Built"
```
Expected: `Built build/AutoClawd.app` with 0 errors.

**Step 4: Commit**

```bash
git add Sources/AppState.swift Sources/MainPanelView.swift
git commit -m "feat: wire AI framing into transcript → Todo path"
```

---

### Task 5: Smoke test

**Start the app:**
```bash
open "/Users/sameeprehlan/Documents/Claude Code/autoclawd/.claude/worktrees/gracious-carson/build/AutoClawd.app"
# or double-click launch.command if open fails
```

**Test 1 — Hot-word framing:**
1. Make sure Ollama is running (`ollama serve`)
2. Speak: `"hot p1 for project 1 uh basically we need to like make the login thing work better"`
3. Open the Todos tab
4. Within ~3s the todo should update from the raw text to something like: `"Improve login flow reliability"`

**Test 2 — Ollama down fallback:**
1. Stop Ollama (`pkill ollama`)
2. Speak another hot-word todo
3. Todo should appear immediately as raw text and stay that way (no crash)

**Test 3 — Transcript "→ Todo":**
1. Go to Transcripts tab, assign a transcript to a project
2. Click "→ Todo"
3. Todo appears raw, frames after ~3s

**Step: Commit** (if any smoke-test fixes needed, fix + commit before this)

```bash
git add -A
git commit -m "feat: AI todo framing complete"
```
