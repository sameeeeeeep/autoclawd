# Hot-Words, Project World Models & UX Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add configurable hot-word detection to transcripts, make the world model per-project with tags/links, merge session chunks automatically, improve transcript UX, reorganize the side panel, and add terminal escape hatch for Claude Code execution.

**Architecture:** Hybrid approach — hot-word configs in UserDefaults (Codable array), per-project world models as `~/.autoclawd/world-model-{projectID}.md` files, project tags as a column in the existing SQLite `projects.db`, transcript auto-merge triggered when a session ends in `ChunkManager`. Detection runs in `ChunkManager` post-transcription before Pass 1.

**Tech Stack:** Swift 5.9, SwiftUI, SQLite (via existing SQLiteStore pattern), UserDefaults (Codable), Ollama (local LLM for project inference), AppKit (NSWorkspace for Terminal launch)

---

## Context for Implementer

### Key files you will touch most:
- `Sources/ChunkManager.swift` — add hot-word detection + chunk auto-merge trigger
- `Sources/ProjectStore.swift` — add tags column + links table
- `Sources/WorldModelService.swift` — make project-aware
- `Sources/TranscriptStore.swift` — add projectID column + merge logic
- `Sources/SettingsManager.swift` — add HotWordConfig storage
- `Sources/MainPanelView.swift` — reorganize panels, add transcript/todo UX
- `Sources/ClaudeCodeRunner.swift` — add terminal launch option

### Existing patterns to follow:
- SQLite stores use a `db: OpaquePointer?` and raw sqlite3 C API calls — follow `ProjectStore.swift` exactly
- UserDefaults properties use `@AppStorage` or direct `UserDefaults.standard` with Codable via `JSONEncoder`
- All async work uses `Task { @MainActor in ... }` or `async/await` with `@MainActor` annotation
- Log with `Log.info(.system, "message")` — available components: audio, transcribe, extract, world, todo, clipboard, system, ui, paste, qa, cleanup
- The app uses `BrutalistTheme` — monospace fonts, neon green accents, dark background

---

## Task 1: HotWordConfig Model + UserDefaults Storage

**Files:**
- Create: `Sources/HotWordConfig.swift`
- Modify: `Sources/SettingsManager.swift`

**Step 1: Create the model**

```swift
// Sources/HotWordConfig.swift
import Foundation

enum HotWordAction: String, Codable, CaseIterable {
    case executeImmediately = "executeImmediately"
    case addTodo = "addTodo"
    case addWorldModelInfo = "addWorldModelInfo"
    case logOnly = "logOnly"

    var displayName: String {
        switch self {
        case .executeImmediately: return "Execute Immediately"
        case .addTodo:            return "Add to Project Todos"
        case .addWorldModelInfo:  return "Add to Project World Model"
        case .logOnly:            return "Log Only"
        }
    }
}

struct HotWordConfig: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var keyword: String          // e.g. "p0", "p1", "info"
    var action: HotWordAction
    var label: String            // e.g. "Critical Execute"
    var skipPermissions: Bool    // only relevant for executeImmediately

    static var defaults: [HotWordConfig] {
        [
            HotWordConfig(keyword: "p0", action: .executeImmediately, label: "Critical Execute", skipPermissions: true),
            HotWordConfig(keyword: "p1", action: .addTodo, label: "Add Todo", skipPermissions: false),
            HotWordConfig(keyword: "info", action: .addWorldModelInfo, label: "Add Info", skipPermissions: false),
        ]
    }
}
```

**Step 2: Add storage to SettingsManager**

In `Sources/SettingsManager.swift`, add after existing properties:

```swift
var hotWordConfigs: [HotWordConfig] {
    get {
        guard let data = UserDefaults.standard.data(forKey: "hotWordConfigs"),
              let configs = try? JSONDecoder().decode([HotWordConfig].self, from: data) else {
            return HotWordConfig.defaults
        }
        return configs
    }
    set {
        if let data = try? JSONEncoder().encode(newValue) {
            UserDefaults.standard.set(data, forKey: "hotWordConfigs")
        }
    }
}
```

**Step 3: Commit**

```bash
git add Sources/HotWordConfig.swift Sources/SettingsManager.swift
git commit -m "feat: add HotWordConfig model and UserDefaults storage"
```

---

## Task 2: Hot-Word Detection Service

**Files:**
- Create: `Sources/HotWordDetector.swift`

**Step 1: Create detector**

```swift
// Sources/HotWordDetector.swift
import Foundation

struct HotWordMatch {
    let config: HotWordConfig
    let payload: String          // everything after "hot <keyword> [for project X]"
    let explicitProjectRef: String?  // "1", "2", or project name if specified
}

struct HotWordDetector {
    // Pattern: "hot <keyword> [for project <ref>] <payload>"
    // Case-insensitive.
    private static let pattern = try! NSRegularExpression(
        pattern: #"\bhot\s+(\w+)(?:\s+for\s+project\s+(\w+))?\s+(.+)"#,
        options: [.caseInsensitive]
    )

    static func detect(in transcript: String, configs: [HotWordConfig]) -> [HotWordMatch] {
        let range = NSRange(transcript.startIndex..., in: transcript)
        let matches = pattern.matches(in: transcript, range: range)

        return matches.compactMap { match in
            guard
                let keywordRange = Range(match.range(at: 1), in: transcript),
                let payloadRange = Range(match.range(at: 3), in: transcript)
            else { return nil }

            let keyword = String(transcript[keywordRange]).lowercased()
            let payload = String(transcript[payloadRange]).trimmingCharacters(in: .whitespaces)

            let projectRef: String?
            if let projRange = Range(match.range(at: 2), in: transcript) {
                projectRef = String(transcript[projRange])
            } else {
                projectRef = nil
            }

            guard let config = configs.first(where: { $0.keyword.lowercased() == keyword }) else {
                return nil
            }

            return HotWordMatch(config: config, payload: payload, explicitProjectRef: projectRef)
        }
    }
}
```

**Step 2: Commit**

```bash
git add Sources/HotWordDetector.swift
git commit -m "feat: add HotWordDetector with regex pattern matching"
```

---

## Task 3: Project Tags + Links in ProjectStore

**Files:**
- Modify: `Sources/ProjectStore.swift`

**Step 1: Add tags column migration**

In `ProjectStore.swift`, after the CREATE TABLE call, add silent migrations:

```swift
sqlite3_exec(db, "ALTER TABLE projects ADD COLUMN tags TEXT DEFAULT ''", nil, nil, nil)
sqlite3_exec(db, "ALTER TABLE projects ADD COLUMN linked_project_ids TEXT DEFAULT ''", nil, nil, nil)
// These fail silently if columns already exist — correct behavior
```

**Step 2: Update Project struct**

```swift
var tags: [String]           // stored as comma-separated "ai,personal,work"
var linkedProjectIDs: [UUID] // stored as comma-separated UUIDs

var tagsString: String { tags.joined(separator: ",") }
var linkedIDsString: String { linkedProjectIDs.map(\.uuidString).joined(separator: ",") }

static func parseTags(_ raw: String) -> [String] {
    raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}
static func parseLinkedIDs(_ raw: String) -> [UUID] {
    raw.split(separator: ",").compactMap { UUID(uuidString: String($0).trimmingCharacters(in: .whitespaces)) }
}
```

**Step 3: Update insert/update/query methods**

Insert SQL: `INSERT INTO projects (id, name, local_path, tags, linked_project_ids, created_at) VALUES (?, ?, ?, ?, ?, ?)`
Bind tagsString at position 4, linkedIDsString at position 5.

In `all()` query, read columns 4 and 5 and construct tags + linkedIDs using parse helpers.

Add `update(project: Project)` if not present.

**Step 4: Add project inference helper**

```swift
func inferProject(for payload: String, using ollamaService: OllamaService) async -> Project? {
    let allProjects = all()
    guard !allProjects.isEmpty else { return nil }

    let projectList = allProjects.map { p in
        let tagStr = p.tags.isEmpty ? "no tags" : p.tags.joined(separator: ", ")
        return "- \(p.name): \(tagStr)"
    }.joined(separator: "\n")

    let prompt = """
    Given this text: "\(payload)"

    Pick the most relevant project from this list, or reply "none":
    \(projectList)

    Reply with ONLY the project name exactly as listed, or "none".
    """

    guard let response = try? await ollamaService.generate(prompt: prompt, maxTokens: 20) else {
        return nil
    }
    let name = response.trimmingCharacters(in: .whitespacesAndNewlines)
    return allProjects.first { $0.name.lowercased() == name.lowercased() }
}
```

**Step 5: Commit**

```bash
git add Sources/ProjectStore.swift
git commit -m "feat: add tags and linked project IDs to ProjectStore"
```

---

## Task 4: Per-Project World Model

**Files:**
- Modify: `Sources/WorldModelService.swift`

**Step 1: Make WorldModelService project-aware**

```swift
// Replace current implementation preserving global read/write for backward compat:

func read(for projectID: UUID) -> String {
    let file = baseDir.appendingPathComponent("world-model-\(projectID.uuidString).md")
    return (try? String(contentsOf: file, encoding: .utf8)) ?? ""
}

func write(_ content: String, for projectID: UUID) {
    let file = baseDir.appendingPathComponent("world-model-\(projectID.uuidString).md")
    try? content.write(to: file, atomically: true, encoding: .utf8)
}

func appendInfo(_ info: String, for projectID: UUID) {
    var existing = read(for: projectID)
    if existing.isEmpty { existing = "## Notes\n\n" }
    existing += "\n- \(info)"
    write(existing, for: projectID)
}
```

Keep existing `read()` and `write(_ content: String)` (no projectID) for global/backward compat.

**Step 2: Commit**

```bash
git add Sources/WorldModelService.swift
git commit -m "feat: make WorldModelService project-aware with per-project files"
```

---

## Task 5: Hot-Word Processing in ChunkManager + AppState

**Files:**
- Modify: `Sources/AppState.swift`
- Modify: `Sources/ChunkManager.swift`
- Modify: `Sources/ClaudeCodeRunner.swift`

**Step 1: Add dangerouslySkipPermissions param to ClaudeCodeRunner.run()**

```swift
// Update run() signature:
func run(_ prompt: String, in project: Project, dangerouslySkipPermissions: Bool = false) -> AsyncThrowingStream<String, Error> {
    var args = ["--print", prompt]
    if dangerouslySkipPermissions {
        args.append("--dangerously-skip-permissions")
    }
    process.arguments = args
    // ...rest unchanged...
}
```

**Step 2: Add processHotWordMatches to AppState**

```swift
func processHotWordMatches(_ matches: [HotWordMatch]) async {
    for match in matches {
        Log.info(.system, "Hot-word: '\(match.config.keyword)' action=\(match.config.action.rawValue)")

        var resolvedProject: Project? = nil
        if let ref = match.explicitProjectRef {
            let all = projectStore.all()
            if let idx = Int(ref), idx >= 1, idx <= all.count {
                resolvedProject = all[idx - 1]
            } else {
                resolvedProject = all.first { $0.name.lowercased().contains(ref.lowercased()) }
            }
        } else {
            resolvedProject = await projectStore.inferProject(for: match.payload, using: ollamaService)
        }

        switch match.config.action {
        case .executeImmediately:
            guard let project = resolvedProject else {
                Log.warn(.system, "Hot-word executeImmediately: no project resolved, skipping")
                continue
            }
            Task { @MainActor in
                for try await line in claudeCodeRunner.run(
                    match.payload,
                    in: project,
                    dangerouslySkipPermissions: match.config.skipPermissions
                ) {
                    Log.info(.system, "[hot-exec] \(line)")
                }
            }

        case .addTodo:
            let todo = StructuredTodo(
                id: UUID(),
                content: match.payload,
                priority: .high,
                projectID: resolvedProject?.id,
                createdAt: Date(),
                isExecuted: false
            )
            structuredTodoStore.insert(todo)
            Log.info(.todo, "Hot-word added todo: \(match.payload)")

        case .addWorldModelInfo:
            if let project = resolvedProject {
                worldModelService.appendInfo(match.payload, for: project.id)
            } else {
                worldModelService.write(worldModelService.read() + "\n- \(match.payload)")
            }
            Log.info(.world, "Hot-word added to world model")

        case .logOnly:
            Log.info(.system, "Hot-word log-only: \(match.payload)")
        }
    }
}
```

**Step 3: Hook detection into ChunkManager post-transcription**

Find where transcription result is available (before `onTranscriptReady` callback) and add:

```swift
let hotWordMatches = HotWordDetector.detect(
    in: transcriptText,
    configs: settingsManager.hotWordConfigs
)
if !hotWordMatches.isEmpty {
    Task { await appState.processHotWordMatches(hotWordMatches) }
}
```

**Step 4: Commit**

```bash
git add Sources/AppState.swift Sources/ChunkManager.swift Sources/ClaudeCodeRunner.swift
git commit -m "feat: hot-word detection and processing in ChunkManager"
```

---

## Task 6: Transcript Auto-Merge + projectID Column

**Files:**
- Modify: `Sources/TranscriptStore.swift`
- Modify: `Sources/ChunkManager.swift`

**Step 1: Add projectID column migration**

```swift
sqlite3_exec(db, "ALTER TABLE transcripts ADD COLUMN project_id TEXT", nil, nil, nil)
```

Update `TranscriptRecord` struct: add `var projectID: UUID?`

Update `save()` to accept optional `projectID` param and bind it.

Update `recent()` and `search()` to read the project_id column.

**Step 2: Add fetchBySession + mergeSessionChunks**

```swift
func fetchBySession(sessionID: String) -> [TranscriptRecord] {
    // SELECT * FROM transcripts WHERE session_id = ? ORDER BY session_chunk_seq ASC NULLS LAST
}

func mergeSessionChunks(sessionID: String) {
    let chunks = fetchBySession(sessionID: sessionID)
    guard chunks.count > 1 else { return }
    let mergedText = chunks.map(\.text).joined(separator: " ")
    let totalDuration = chunks.compactMap(\.durationSeconds).reduce(0, +)
    let earliest = chunks.map(\.timestamp).min() ?? Date()
    let projectID = chunks.first?.projectID
    for chunk in chunks { delete(id: chunk.id) }
    save(text: mergedText, durationSeconds: totalDuration, audioFilePath: nil,
         sessionID: sessionID, sessionChunkSeq: nil, projectID: projectID, timestamp: earliest)
    Log.info(.system, "Merged \(chunks.count) transcript chunks for session \(sessionID)")
}

func delete(id: UUID) {
    let sql = "DELETE FROM transcripts WHERE id = ?"
    var stmt: OpaquePointer?
    sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
    sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
    sqlite3_step(stmt)
    sqlite3_finalize(stmt)
}

func setProject(_ projectID: UUID?, for transcriptID: UUID) {
    let sql = "UPDATE transcripts SET project_id = ? WHERE id = ?"
    var stmt: OpaquePointer?
    sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
    if let pid = projectID {
        sqlite3_bind_text(stmt, 1, pid.uuidString, -1, SQLITE_TRANSIENT)
    } else {
        sqlite3_bind_null(stmt, 1)
    }
    sqlite3_bind_text(stmt, 2, transcriptID.uuidString, -1, SQLITE_TRANSIENT)
    sqlite3_step(stmt)
    sqlite3_finalize(stmt)
}
```

**Step 3: Trigger merge when session ends**

In `ChunkManager.swift`, find the session end/stop transition and add:

```swift
if let endedSessionID = self.currentSessionID {
    Task { transcriptStore.mergeSessionChunks(sessionID: endedSessionID) }
}
```

**Step 4: Commit**

```bash
git add Sources/TranscriptStore.swift Sources/ChunkManager.swift
git commit -m "feat: auto-merge transcript chunks on session end, add projectID to transcripts"
```

---

## Task 7: Transcript UI — Project Picker + Process as Todo

**Files:**
- Modify: `Sources/MainPanelView.swift`

**Step 1: Find transcript list row in MainPanelView.swift**

Search for the Todos/Transcripts rendering code (look for `transcriptStore.recent()` or a `ForEach` over transcript items in the `.transcript` tab section).

**Step 2: Add controls below each transcript row**

```swift
HStack(spacing: 8) {
    Menu {
        Button("None") { transcriptStore.setProject(nil, for: transcript.id) }
        ForEach(appState.projectStore.all()) { project in
            Button(project.name) { transcriptStore.setProject(project.id, for: transcript.id) }
        }
    } label: {
        Label(
            transcript.projectID.flatMap { id in appState.projectStore.all().first { $0.id == id }?.name } ?? "No Project",
            systemImage: "folder"
        )
        .font(.system(.caption, design: .monospaced))
        .foregroundColor(.secondary)
    }
    Spacer()
    Button("→ Todo") {
        let todo = StructuredTodo(
            id: UUID(), content: transcript.text, priority: .medium,
            projectID: transcript.projectID, createdAt: Date(), isExecuted: false
        )
        appState.structuredTodoStore.insert(todo)
    }
    .font(.system(.caption, design: .monospaced))
    .buttonStyle(.bordered)
}
```

**Step 3: Commit**

```bash
git add Sources/MainPanelView.swift
git commit -m "feat: transcript project picker and process-as-todo button"
```

---

## Task 8: Todos — Inline Project Picker

**Files:**
- Modify: `Sources/MainPanelView.swift`

**Step 1: Add project picker to each todo row**

Find the todo rows in the `.todos` tab section. Add:

```swift
Menu {
    Button("None") { appState.structuredTodoStore.setProject(nil, for: todo.id) }
    ForEach(appState.projectStore.all()) { project in
        Button(project.name) { appState.structuredTodoStore.setProject(project.id, for: todo.id) }
    }
} label: {
    Text(
        todo.projectID.flatMap { id in appState.projectStore.all().first { $0.id == id }?.name } ?? "—"
    )
    .font(.system(.caption, design: .monospaced))
    .foregroundColor(todo.projectID != nil ? .green : .secondary)
}
```

**Step 2: Commit**

```bash
git add Sources/MainPanelView.swift
git commit -m "feat: inline project picker on todo rows"
```

---

## Task 9: Settings — Project Path Config + Hot-Words UI

**Files:**
- Modify: `Sources/MainPanelView.swift`

**Step 1: Move project path config into Settings tab**

In the `.settings` tab section, add a "Projects" subsection with path editing for each project. Move any path-editing UI from the `.projects` tab here.

**Step 2: Add hot-words section to Settings**

```swift
// In SettingsView, add:
Section("Hot Words") {
    ForEach(appState.settingsManager.hotWordConfigs) { config in
        HStack(spacing: 8) {
            Text("hot \(config.keyword)")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.green)
            Text("→ \(config.action.displayName)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
            if config.action == .executeImmediately && config.skipPermissions {
                Text("⚡ skip perms")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.orange)
            }
            Spacer()
            Button("✕") {
                appState.settingsManager.hotWordConfigs.removeAll { $0.id == config.id }
            }
            .foregroundColor(.red)
        }
    }
    Button("+ Add Hot Word") { showingAddHotWord = true }
        .font(.system(.caption, design: .monospaced))
        .foregroundColor(.green)
}
.sheet(isPresented: $showingAddHotWord) {
    HotWordEditView(configs: Binding(
        get: { appState.settingsManager.hotWordConfigs },
        set: { appState.settingsManager.hotWordConfigs = $0 }
    ))
}
```

**Step 3: Create HotWordEditView**

Add to `MainPanelView.swift` (or new file `Sources/HotWordEditView.swift`):

```swift
struct HotWordEditView: View {
    @Binding var configs: [HotWordConfig]
    @Environment(\.dismiss) var dismiss
    @State private var keyword = ""
    @State private var action: HotWordAction = .addTodo
    @State private var label = ""
    @State private var skipPermissions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Hot Word").font(.system(.headline, design: .monospaced))
            TextField("keyword (e.g. p0, info)", text: $keyword)
                .textFieldStyle(.roundedBorder)
            Picker("Action", selection: $action) {
                ForEach(HotWordAction.allCases, id: \.self) { a in
                    Text(a.displayName).tag(a)
                }
            }
            if action == .executeImmediately {
                Toggle("Skip permissions (--dangerously-skip-permissions)", isOn: $skipPermissions)
            }
            TextField("label (display name)", text: $label)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Add") {
                    guard !keyword.isEmpty else { return }
                    configs.append(HotWordConfig(
                        keyword: keyword.lowercased(),
                        action: action,
                        label: label.isEmpty ? keyword : label,
                        skipPermissions: skipPermissions
                    ))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(keyword.isEmpty)
            }
        }
        .padding(20).frame(width: 360)
        .font(.system(.body, design: .monospaced))
    }
}
```

**Step 4: Redesign Projects tab for tags + links view**

The Projects tab now shows project cards with tags and linked projects (no path editing here):

```swift
// In .projects tab, replace path editing with:
ForEach(appState.projectStore.all()) { project in
    VStack(alignment: .leading, spacing: 4) {
        Text(project.name).font(.system(.headline, design: .monospaced))
        if !project.tags.isEmpty {
            HStack {
                ForEach(project.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(.caption2, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(3)
                }
            }
        }
        if !project.linkedProjectIDs.isEmpty {
            let linked = project.linkedProjectIDs
                .compactMap { id in appState.projectStore.all().first { $0.id == id }?.name }
            Text("Linked: " + linked.joined(separator: ", "))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
    .padding(8)
    .background(Color.white.opacity(0.04))
    .cornerRadius(6)
}
```

**Step 5: Commit**

```bash
git add Sources/MainPanelView.swift
git commit -m "feat: hot-words settings UI, project path in settings, projects tab redesign"
```

---

## Task 10: Open in Terminal for Claude Code

**Files:**
- Modify: `Sources/ClaudeCodeRunner.swift`
- Modify: `Sources/MainPanelView.swift`

**Step 1: Add openInTerminal to ClaudeCodeRunner**

```swift
func openInTerminal(prompt: String, in project: Project, dangerouslySkipPermissions: Bool = false) {
    guard let claudePath = Self.findClaudePath() else { return }
    let safePrompt = prompt.replacingOccurrences(of: "'", with: "'\\''")
    let permFlag = dangerouslySkipPermissions ? " --dangerously-skip-permissions" : ""
    let fullCmd = "cd '\(project.localPath)' && \(claudePath)\(permFlag) '\(safePrompt)'"

    let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("autoclawd-\(UUID().uuidString.prefix(8)).sh")
    let script = "#!/bin/bash\n\(fullCmd)\n"
    try? script.write(to: scriptURL, atomically: true, encoding: .utf8)
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
    NSWorkspace.shared.open(
        [scriptURL],
        withApplicationAt: terminalURL,
        configuration: NSWorkspace.OpenConfiguration()
    )
}
```

**Step 2: Add "Open in Terminal" button alongside run button**

Find where the Claude Code run button lives in the Todos or Intelligence tab and add:

```swift
Button("Open in Terminal") {
    appState.claudeCodeRunner.openInTerminal(
        prompt: todo.content,
        in: selectedProject
    )
}
.font(.system(.caption, design: .monospaced))
.foregroundColor(.secondary)
```

**Step 3: Commit**

```bash
git add Sources/ClaudeCodeRunner.swift Sources/MainPanelView.swift
git commit -m "feat: open Claude Code execution in Terminal.app"
```

---

## Task 11: Multi-Select Todos with Parallel/Series Execution

**Files:**
- Modify: `Sources/MainPanelView.swift`
- Modify: `Sources/AppState.swift`

**Step 1: Add ExecutionMode enum to AppState**

```swift
// In Sources/AppState.swift or a shared types file:
enum ExecutionMode { case parallel, series }
```

**Step 2: Add executeSelectedTodos to AppState**

```swift
func executeSelectedTodos(ids: Set<UUID>, mode: ExecutionMode) async {
    let todos = structuredTodoStore.all().filter { ids.contains($0.id) }

    switch mode {
    case .parallel:
        await withTaskGroup(of: Void.self) { group in
            for todo in todos {
                guard let project = todo.projectID.flatMap({ id in projectStore.all().first { $0.id == id } }) else {
                    Log.warn(.system, "Todo '\(todo.content.prefix(30))' has no project, skipping parallel exec")
                    continue
                }
                group.addTask {
                    for try await line in self.claudeCodeRunner.run(todo.content, in: project) {
                        Log.info(.system, "[parallel] \(line)")
                    }
                }
            }
        }
    case .series:
        for todo in todos {
            guard let project = todo.projectID.flatMap({ id in projectStore.all().first { $0.id == id } }) else {
                Log.warn(.system, "Todo '\(todo.content.prefix(30))' has no project, skipping series exec")
                continue
            }
            do {
                for try await line in claudeCodeRunner.run(todo.content, in: project) {
                    Log.info(.system, "[series] \(line)")
                }
            } catch {
                Log.warn(.system, "Series exec error: \(error)")
            }
        }
    }
}
```

**Step 3: Add multi-select UI to Todos tab**

```swift
// State vars at top of MainPanelView (or the todos tab sub-view):
@State private var selectedTodoIDs: Set<UUID> = []
@State private var executionMode: ExecutionMode = .parallel

// Each todo row: prefix with checkbox
Image(systemName: selectedTodoIDs.contains(todo.id) ? "checkmark.square.fill" : "square")
    .foregroundColor(selectedTodoIDs.contains(todo.id) ? .green : .secondary)
    .onTapGesture {
        if selectedTodoIDs.contains(todo.id) { selectedTodoIDs.remove(todo.id) }
        else { selectedTodoIDs.insert(todo.id) }
    }

// Below todo list, show execution bar when items selected:
if !selectedTodoIDs.isEmpty {
    HStack {
        Text("\(selectedTodoIDs.count) selected")
            .font(.system(.caption, design: .monospaced))
        Picker("", selection: $executionMode) {
            Text("Parallel").tag(ExecutionMode.parallel)
            Text("Series").tag(ExecutionMode.series)
        }
        .pickerStyle(.segmented)
        .frame(width: 160)
        Spacer()
        Button("Execute All") {
            Task { await appState.executeSelectedTodos(ids: selectedTodoIDs, mode: executionMode) }
        }
        .buttonStyle(.borderedProminent)
        .font(.system(.caption, design: .monospaced))
    }
    .padding(.vertical, 6)
}
```

**Step 4: Commit**

```bash
git add Sources/MainPanelView.swift Sources/AppState.swift
git commit -m "feat: multi-select todos with parallel/series execution modes"
```

---

## Task 12: Build & Smoke Test

**Step 1: Build**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd/.claude/worktrees/gracious-carson"
swift build 2>&1
```

Expected: 0 errors, 0 warnings (or only pre-existing warnings).

**Step 2: Launch and verify**

```bash
open .build/debug/AutoClawd.app
```

Smoke test checklist:
- [ ] Settings tab shows "Hot Words" section with default p0/p1/info entries
- [ ] Can add a new hot word via "+ Add Hot Word" sheet
- [ ] Can delete a hot word
- [ ] Settings tab shows project path editing
- [ ] Projects tab shows cards with tags and linked-project display
- [ ] Transcript rows show project picker + "→ Todo" button
- [ ] Todo rows show project picker
- [ ] Todo checkboxes appear; parallel/series bar shows when items selected
- [ ] "Open in Terminal" button appears on todo execution

**Step 3: Speak a hot-word test**

With mic active say: *"hot p1 for project 1 improve error handling in the transcription service"*

Verify a new todo appears in Todos tab assigned to project 1.

**Step 4: Final commit if anything was missed**

```bash
git add -A
git commit -m "chore: smoke test fixes"
```

---

## Summary of All Changed Files

| Feature | Files |
|---------|-------|
| HotWordConfig model | `Sources/HotWordConfig.swift` (new) |
| HotWordDetector | `Sources/HotWordDetector.swift` (new) |
| Project tags + links | `Sources/ProjectStore.swift` |
| Per-project world model | `Sources/WorldModelService.swift` |
| Hot-word processing | `Sources/AppState.swift`, `Sources/ChunkManager.swift` |
| --dangerously-skip-permissions | `Sources/ClaudeCodeRunner.swift` |
| Transcript merge + projectID | `Sources/TranscriptStore.swift`, `Sources/ChunkManager.swift` |
| Transcript UX | `Sources/MainPanelView.swift` |
| Todo project picker | `Sources/MainPanelView.swift` |
| Settings reorg + hot-words UI | `Sources/MainPanelView.swift` |
| Open in Terminal | `Sources/ClaudeCodeRunner.swift`, `Sources/MainPanelView.swift` |
| Parallel/series execution | `Sources/AppState.swift`, `Sources/MainPanelView.swift` |
