# Todo Framing via AI Design

**Date:** 2026-02-26
**Status:** Approved

## Problem

Hot-word todos are stored verbatim from speech-to-text. `"hot p1 for project 2 refactor the auth flow"` stores exactly `"refactor the auth flow"` — raw, unstructured, no project context applied. The same issue affects the "→ Todo" button on transcript rows.

## Goals

1. Frame raw speech payloads into clean, actionable task titles using Ollama + project context
2. Non-blocking: todo appears immediately as raw text, updates silently once LLM responds
3. Fallback gracefully if Ollama is unavailable or times out

## Out of Scope

- Branch selection (Claude Code handles this from the project directory)
- Subtask decomposition or acceptance criteria generation
- Framing for manually typed todos

---

## Architecture

### New: `TodoFramingService`

A small, single-responsibility service (`Sources/TodoFramingService.swift`):

```swift
actor TodoFramingService {
    func frame(rawPayload: String, for project: Project) async -> String
}
```

**Internal steps:**
1. Load context from `project.localPath`:
   - Try `README.md` (truncate to 1500 chars)
   - Try `CLAUDE.md` (truncate to 1500 chars)
   - Both optional — if neither exists, context is empty
2. Call `OllamaService.generate()` with structured prompt (see below)
3. Clean the response (strip quotes, trim whitespace)
4. If Ollama throws or response is empty → return `rawPayload` unchanged

**Prompt:**
```
You are a task management assistant for a software project.
Rewrite the raw spoken task as a single clean, actionable task title.
Requirements: imperative mood, max ~12 words, no filler words.
Respond with ONLY the task title — no explanation, no quotes.

Project: <project.name>
Project context:
<README.md content, truncated to 1500 chars>
<CLAUDE.md content, truncated to 1500 chars>

Raw spoken task: "<rawPayload>"
```

**Timeout:** 8 seconds via `Task { ... }` with `.timeout` or `withThrowingTaskGroup` cancellation. Falls back to raw payload on timeout.

### Modified: `StructuredTodoStore`

Add `updateContent(id: String, content: String)`:
```swift
func updateContent(id: String, content: String)
```
Simple `UPDATE structured_todos SET content = ? WHERE id = ?`.

### Modified: `AppState`

Add `todoFramingService` property. In `processHotWordMatches`, the `.addTodo` case becomes:

```
1. Insert todo with raw payload (immediate, synchronous)
2. Assign project
3. Refresh UI (todo appears instantly)
4. Fire detached Task:
   a. Call todoFramingService.frame(rawPayload, for: project)
   b. Call structuredTodoStore.updateContent(id, framedContent)
   c. Refresh UI again (todo updates silently)
```

### Modified: `MainPanelView` (transcript "→ Todo" button)

The existing `addStructuredTodo(content:priority:)` path in `AppState` also gains framing — same pattern: insert raw → fire background frame → update.

---

## Data Flow

```
Speech → HotWordDetector → HotWordMatch.payload (raw)
  → insert raw todo (immediate UI update)
  → background Task:
      → TodoFramingService.frame()
          → read README.md + CLAUDE.md
          → OllamaService.generate()
          → returns framed title
      → StructuredTodoStore.updateContent()
      → refreshStructuredTodos() (silent UI update)
```

---

## Error Handling

| Scenario | Behaviour |
|----------|-----------|
| Ollama not running | `generate()` throws → raw payload kept |
| LLM response is empty/garbage | Cleaned response is empty → raw payload kept |
| Timeout > 8s | Task cancelled → raw payload kept |
| Context files missing | Skip gracefully, proceed with empty context |

---

## Files Changed

| File | Change |
|------|--------|
| `Sources/TodoFramingService.swift` | **New** — the framing actor |
| `Sources/StructuredTodoStore.swift` | Add `updateContent(id:content:)` |
| `Sources/AppState.swift` | Add `todoFramingService`, wire framing into `.addTodo` and `addStructuredTodo` |
