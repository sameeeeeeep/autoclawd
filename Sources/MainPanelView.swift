import AppKit
import SwiftUI

// MARK: - Panel Tab

enum PanelTab: String, CaseIterable, Identifiable {
    case todos      = "To-Do"
    case worldModel = "World Model"
    case transcript = "Transcript"
    case settings   = "Settings"
    case logs         = "Logs"
    case intelligence = "Intelligence"
    case qa = "AI Search"
    case timeline = "Timeline"
    case profile = "Profile"
    case projects = "Projects"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .todos:      return "checkmark.square"
        case .worldModel: return "brain"
        case .transcript: return "text.bubble"
        case .settings:   return "gearshape"
        case .logs:         return "doc.text"
        case .intelligence: return "brain.head.profile"
        case .qa: return "magnifyingglass"
        case .timeline: return "clock"
        case .profile: return "person.crop.circle"
        case .projects: return "folder"
        }
    }
}

// MARK: - MainPanelView

struct MainPanelView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: PanelTab = .todos
    @State private var transcriptSearch = ""

    var body: some View {
        VStack(spacing: 0) {
            if let ssid = appState.pendingUnknownSSID {
                wifiLabelBanner(ssid: ssid)
            }
            HStack(spacing: 0) {
                sidebar
                Divider()
                content
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Logo
            HStack {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("AutoClawd")
                        .font(BrutalistTheme.monoLG)
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                        .font(BrutalistTheme.monoSM)
                        .foregroundColor(.white.opacity(0.35))
                }
                Spacer()
                statusDot
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ForEach(PanelTab.allCases) { tab in
                Button { selectedTab = tab } label: {
                    Label(tab.rawValue.uppercased(), systemImage: tab.icon)
                        .font(BrutalistTheme.monoMD)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 10)
                        .background(
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(selectedTab == tab
                                          ? BrutalistTheme.selectedBG
                                          : Color.clear)
                                if selectedTab == tab {
                                    Rectangle()
                                        .fill(BrutalistTheme.neonGreen)
                                        .frame(width: BrutalistTheme.selectedAccentWidth)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Status footer
            VStack(alignment: .leading, spacing: 2) {
                Divider()
                HStack {
                    Text(appState.micEnabled ? "[ON]" : "[OFF]")
                        .font(BrutalistTheme.monoSM)
                        .foregroundColor(appState.micEnabled ? BrutalistTheme.neonGreen : .white.opacity(0.4))
                    Spacer()
                    Text(appState.transcriptionMode == .groq ? "[GROQ]" : "[LOCAL]")
                        .font(BrutalistTheme.monoSM)
                        .foregroundColor(.white.opacity(0.35))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 160)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var statusDot: some View {
        Text(appState.isListening ? "[●]" : "[·]")
            .font(BrutalistTheme.monoSM)
            .foregroundColor(appState.isListening ? BrutalistTheme.neonGreen : .white.opacity(0.35))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .todos:      TodoTabView(appState: appState)
        case .worldModel: WorldModelGraphView(appState: appState)
        case .transcript: TranscriptTabView(appState: appState, search: $transcriptSearch)
        case .settings:   SettingsTabView(appState: appState)
        case .logs:         LogsTabView(appState: appState)
        case .intelligence: IntelligenceView(appState: appState)
        case .qa: QAView(store: appState.qaStore)
        case .timeline: SessionTimelineView()
        case .profile: UserProfileChatView().environmentObject(appState)
        case .projects: ProjectsTabView(appState: appState)
        }
    }

    // MARK: - WiFi Label Banner

    @ViewBuilder
    private func wifiLabelBanner(ssid: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi")
                .foregroundColor(BrutalistTheme.neonGreen)
                .font(.system(size: 11))
            Text("You're on '\(ssid)' — what should I call this place?")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
            TextField("e.g. Home, Philz Coffee", text: $appState.wifiLabelInput)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: 160)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.08))
                .cornerRadius(4)
            Button("Save") { appState.confirmWifiLabel() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(BrutalistTheme.neonGreen)
            Button("Skip") {
                appState.pendingUnknownSSID = nil
                appState.wifiLabelInput = ""
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6))
        .overlay(Rectangle().fill(BrutalistTheme.neonGreen.opacity(0.15)).frame(height: 1), alignment: .bottom)
    }
}

// MARK: - Todo Tab

private func priorityRank(_ priority: String?) -> Int {
    switch priority {
    case "HIGH":   return 0
    case "MEDIUM": return 1
    case "LOW":    return 2
    default:       return 3
    }
}

struct TodoTabView: View {
    @ObservedObject var appState: AppState
    @State private var rawContent: String = ""
    @State private var showRaw = false
    @State private var runningTodo: StructuredTodo? = nil
    @State private var selectedTodoIDs: Set<String> = []
    @State private var executionMode: ExecutionMode = .parallel

    var sortedTodos: [StructuredTodo] {
        appState.structuredTodos.sorted {
            priorityRank($0.priority) < priorityRank($1.priority)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabHeader("TO-DO LIST") {
                Button("Refresh") {
                    appState.refreshStructuredTodos()
                    rawContent = appState.todosContent
                }
                .buttonStyle(.bordered)
            }
            Divider()

            if appState.structuredTodos.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No structured todos yet.")
                        .font(BrutalistTheme.monoSM)
                        .foregroundColor(.white.opacity(0.4))
                    Text("Voice-captured todos appear here after synthesis.")
                        .font(BrutalistTheme.monoSM)
                        .foregroundColor(.white.opacity(0.25))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(sortedTodos) { todo in
                        HStack(spacing: 6) {
                            Image(systemName: selectedTodoIDs.contains(todo.id) ? "checkmark.square.fill" : "square")
                                .foregroundColor(selectedTodoIDs.contains(todo.id) ? .green : .secondary)
                                .font(.system(size: 14))
                                .onTapGesture {
                                    if selectedTodoIDs.contains(todo.id) {
                                        selectedTodoIDs.remove(todo.id)
                                    } else {
                                        selectedTodoIDs.insert(todo.id)
                                    }
                                }
                            StructuredTodoRow(todo: todo, appState: appState, onRun: { runningTodo = todo })
                        }
                    }
                }
                .listStyle(.plain)

                if !selectedTodoIDs.isEmpty {
                    Divider()
                    HStack(spacing: 12) {
                        Text("\(selectedTodoIDs.count) selected")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        Picker("", selection: $executionMode) {
                            ForEach(ExecutionMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }

            Divider()

            DisclosureGroup("Raw Notes (LLM context)", isExpanded: $showRaw) {
                TextEditor(text: $rawContent)
                    .font(.custom("JetBrains Mono", size: 11))
                    .frame(minHeight: 120)
                    .padding(4)
            }
            .font(BrutalistTheme.monoSM)
            .foregroundColor(.white.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .onAppear {
            rawContent = appState.todosContent
            appState.refreshStructuredTodos()
        }
        .onChange(of: rawContent) { newVal in appState.saveTodos(newVal) }
        .sheet(item: $runningTodo) { todo in
            ExecutionOutputView(todo: todo, appState: appState)
        }
    }
}

// MARK: - StructuredTodoRow

struct StructuredTodoRow: View {
    let todo: StructuredTodo
    @ObservedObject var appState: AppState
    let onRun: () -> Void

    private var projectName: String {
        appState.projects.first(where: { $0.id == todo.projectID })?.name ?? "No Project"
    }

    private var canRun: Bool {
        ClaudeCodeRunner.findCLI() != nil   // projectID gate removed — sheet shows "No project assigned" clearly
    }

    var body: some View {
        HStack(spacing: 8) {
            priorityBadge
            Text(todo.content)
                .font(.custom("JetBrains Mono", size: 11))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            projectMenu
            Button(action: onRun) {
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .foregroundColor(canRun ? BrutalistTheme.neonGreen : .white.opacity(0.2))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .disabled(!canRun)

            if canRun, let project = appState.projects.first(where: { $0.id == todo.projectID }) {
                Button("Open in Terminal") {
                    appState.claudeCodeRunner.openInTerminal(
                        prompt: todo.content,
                        in: project
                    )
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
            }

            if todo.isExecuted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(BrutalistTheme.neonGreen)
                    .font(.system(size: 12))
            }

            Button(action: { appState.deleteTodo(id: todo.id) }) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var priorityBadge: some View {
        let (label, color): (String, Color) = {
            switch todo.priority {
            case "HIGH":   return ("H", .red)
            case "MEDIUM": return ("M", .orange)
            case "LOW":    return ("L", Color.white.opacity(0.4))
            default:       return ("·", Color.white.opacity(0.2))
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .frame(width: 16, height: 16)
            .background(RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.15)))
    }

    private var projectMenu: some View {
        Menu {
            Button("None") { appState.setTodoProject(todoID: todo.id, projectID: nil) }
            ForEach(appState.projects) { project in
                Button(project.name) { appState.setTodoProject(todoID: todo.id, projectID: project.id) }
            }
        } label: {
            Text(todo.projectID != nil ? projectName : "—")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(todo.projectID != nil ? BrutalistTheme.neonGreen : .secondary)
                .lineLimit(1)
                .frame(maxWidth: 90, alignment: .trailing)
        }
        .menuStyle(.borderlessButton)
    }
}

// MARK: - ExecutionOutputView

struct ExecutionOutputView: View {
    let todo: StructuredTodo
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var outputLines: [String] = []
    @State private var isRunning = false
    @State private var errorMessage: String? = nil
    @State private var runTask: Task<Void, Never>? = nil

    private var project: Project? {
        appState.projects.first(where: { $0.id == todo.projectID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(todo.content)
                        .font(BrutalistTheme.monoMD)
                        .lineLimit(2)
                    if let p = project {
                        Text(p.name + " · " + p.localPath)
                            .font(BrutalistTheme.monoSM)
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                Spacer()
                if isRunning { ProgressView().controlSize(.small) }
            }
            .padding()

            Divider()

            // Output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(outputLines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.custom("JetBrains Mono", size: 11))
                                .textSelection(.enabled)
                                .id(idx)
                        }
                    }
                    .padding()
                }
                .onChange(of: outputLines.count) { _ in
                    if let last = outputLines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            .frame(minHeight: 300)

            if let err = errorMessage {
                Text("Error: \(err)")
                    .font(BrutalistTheme.monoSM)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            Divider()

            HStack {
                Button("Copy Output") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(outputLines.joined(separator: "\n"), forType: .string)
                }
                .buttonStyle(.bordered)
                .disabled(outputLines.isEmpty)

                Spacer()

                Button("Done") {
                    runTask?.cancel()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 440)
        .onAppear { startExecution() }
    }

    private func startExecution() {
        guard let proj = project else {
            errorMessage = "No project assigned."
            return
        }
        isRunning = true
        let apiKey = SettingsManager.shared.anthropicAPIKey
        let runner = ClaudeCodeRunner()
        runTask = Task {
            do {
                for try await line in runner.run(todo: todo, project: proj, apiKey: apiKey.isEmpty ? nil : apiKey) {
                    await MainActor.run { outputLines.append(line) }
                }
                let fullOutput = outputLines.joined(separator: "\n")
                await MainActor.run {
                    isRunning = false
                    appState.markTodoExecuted(id: todo.id, output: fullOutput)
                }
            } catch {
                await MainActor.run {
                    isRunning = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}


// MARK: - Projects Tab

struct ProjectsTabView: View {
    @ObservedObject var appState: AppState
    @State private var showAddSheet = false
    @State private var newName = ""
    @State private var newPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabHeader("PROJECTS") {
                Button("+ Add") { showAddSheet = true }
                    .buttonStyle(.bordered)
            }
            Divider()

            if appState.projects.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No projects yet.")
                        .font(BrutalistTheme.monoSM)
                        .foregroundColor(.white.opacity(0.4))
                    Text("Add a project folder to enable todo execution.")
                        .font(BrutalistTheme.monoSM)
                        .foregroundColor(.white.opacity(0.25))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(appState.projects) { project in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.name)
                                        .font(BrutalistTheme.monoMD)
                                    Text(project.localPath)
                                        .font(BrutalistTheme.monoSM)
                                        .foregroundColor(.white.opacity(0.4))
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button(action: { appState.deleteProject(id: project.id) }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.3))
                                }
                                .buttonStyle(.plain)
                            }
                            if !project.tags.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 4) {
                                        ForEach(project.tags, id: \.self) { tag in
                                            Text(tag)
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(.black)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(BrutalistTheme.neonGreen)
                                                .cornerRadius(4)
                                        }
                                    }
                                }
                            }
                            if !project.linkedProjectIDs.isEmpty {
                                let linkedNames = project.linkedProjectIDs.compactMap { linkedID in
                                    appState.projects.first(where: { $0.id == linkedID.uuidString })?.name
                                }
                                if !linkedNames.isEmpty {
                                    Text("Linked: \(linkedNames.joined(separator: ", "))")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddProjectSheet(isPresented: $showAddSheet, onAdd: { name, path in
                appState.addProject(name: name, path: path)
            })
        }
    }
}

struct AddProjectSheet: View {
    @Binding var isPresented: Bool
    let onAdd: (String, String) -> Void
    @State private var name = ""
    @State private var path = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ADD PROJECT").font(BrutalistTheme.monoLG)

            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption).foregroundStyle(.secondary)
                TextField("e.g. My App", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Folder").font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("Path", text: $path)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose...") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        panel.prompt = "Select Folder"
                        if panel.runModal() == .OK, let url = panel.url {
                            path = url.path
                            if name.isEmpty { name = url.lastPathComponent }
                        }
                    }
                }
            }

            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Add") {
                    guard !name.isEmpty, !path.isEmpty else { return }
                    onAdd(name, path)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || path.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

// MARK: - World Model Tab

struct WorldModelTabView: View {
    @ObservedObject var appState: AppState
    @State private var content: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabHeader("WORLD MODEL") {
                Button("Refresh") { loadContent() }
                    .buttonStyle(.bordered)
            }
            Divider()
            ScrollView {
                TextEditor(text: $content)
                    .font(.custom("JetBrains Mono", size: 12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            }
        }
        .onAppear { loadContent() }
        .onChange(of: content) { newVal in
            appState.saveWorldModel(newVal)
        }
    }

    private func loadContent() {
        content = appState.worldModelContent
    }
}

// MARK: - Transcript Tab

struct TranscriptTabView: View {
    @ObservedObject var appState: AppState
    @Binding var search: String
    @State private var transcripts: [TranscriptRecord] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabHeader("TRANSCRIPTS") {
                TextField("Search...", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onChange(of: search) { _ in loadTranscripts() }
            }
            Divider()
            List(transcripts) { record in
                TranscriptRowView(record: record, appState: appState)
            }
            .listStyle(.plain)
        }
        .onAppear { loadTranscripts() }
    }

    private func loadTranscripts() {
        if search.isEmpty {
            transcripts = appState.recentTranscripts()
        } else {
            transcripts = appState.searchTranscripts(query: search)
        }
    }
}

struct TranscriptRowView: View {
    let record: TranscriptRecord
    @ObservedObject var appState: AppState
    @State private var expanded = false

    private var assignedProjectName: String {
        guard let pid = record.projectID else { return "No Project" }
        return appState.projects.first(where: { $0.id == pid.uuidString })?.name ?? "No Project"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(record.durationSeconds)s")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(expanded ? record.text : String(record.text.prefix(120)) + "...")
                .font(.custom("JetBrains Mono", size: 11))
                .lineLimit(expanded ? nil : 3)
                .onTapGesture { expanded.toggle() }
            HStack(spacing: 8) {
                Menu {
                    Button("None") {
                        appState.setTranscriptProject(transcriptID: record.id, projectID: nil)
                    }
                    ForEach(appState.projects) { project in
                        Button(project.name) {
                            appState.setTranscriptProject(transcriptID: record.id, projectID: UUID(uuidString: project.id))
                        }
                    }
                } label: {
                    Label(assignedProjectName, systemImage: "folder")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("→ Todo") {
                    let proj = appState.projects.first(where: {
                        $0.id == record.projectID?.uuidString
                    })
                    appState.addStructuredTodo(content: record.text, priority: "MEDIUM", project: proj)
                }
                .font(.system(.caption, design: .monospaced))
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings Tab

struct SettingsTabView: View {
    @ObservedObject var appState: AppState
    @State private var groqKey = ""
    @State private var anthropicKey = ""
    @State private var isValidating = false
    @State private var validationResult: Bool? = nil
    @State private var showingAddHotWord = false
    @State private var localHotWordConfigs: [HotWordConfig] = SettingsManager.shared.hotWordConfigs

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TabHeader("SETTINGS") { EmptyView() }

                GroupBox("Display") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Show Ambient Widget", isOn: $appState.showAmbientWidget)
                            .font(BrutalistTheme.monoMD)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pill Appearance").font(.caption).foregroundStyle(.secondary)
                            Picker("", selection: $appState.appearanceMode) {
                                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .padding(8)
                }

                GroupBox("Claude Code") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Anthropic API Key").font(.caption).foregroundStyle(.secondary)
                        SecureField("sk-ant-...", text: $anthropicKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(8)
                }

                GroupBox("Transcription") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Mode", selection: $appState.transcriptionMode) {
                            ForEach(TranscriptionMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.radioGroup)

                        if appState.transcriptionMode == .groq {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Groq API Key").font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    SecureField("gsk_...", text: $groqKey)
                                        .textFieldStyle(.roundedBorder)
                                    Button(isValidating ? "..." : "Validate") {
                                        validateKey()
                                    }
                                    .disabled(isValidating || groqKey.isEmpty)
                                    if let result = validationResult {
                                        Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundColor(result ? .green : .red)
                                    }
                                }
                            }
                        }
                    }
                    .padding(8)
                }

                GroupBox("Microphone") {
                    Toggle("Always-on listening", isOn: $appState.micEnabled)
                        .padding(8)
                }

                GroupBox("Audio Retention") {
                    Picker("Delete audio after", selection: $appState.audioRetentionDays) {
                        ForEach(AudioRetention.allCases, id: \.rawValue) { r in
                            Text(r.displayName).tag(r.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(8)
                }

                GroupBox("Dependencies") {
                    HStack {
                        Button("Re-run Setup") { appState.showSetup() }
                    }
                    .padding(8)
                }

                GroupBox("Data") {
                    HStack {
                        Button("Export All") { appState.exportData() }
                        Button("Delete All", role: .destructive) { appState.confirmDeleteAll() }
                    }
                    .padding(8)
                }

                GroupBox("Hot Words") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(localHotWordConfigs) { config in
                            HStack(spacing: 8) {
                                Text("hot \(config.keyword)")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(BrutalistTheme.neonGreen)
                                Text("→ \(config.action.displayName)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                if config.action == .executeImmediately && config.skipPermissions {
                                    Text("⚡")
                                        .font(.system(.caption2, design: .monospaced))
                                }
                                Spacer()
                                Button("✕") {
                                    localHotWordConfigs.removeAll { $0.id == config.id }
                                    SettingsManager.shared.hotWordConfigs = localHotWordConfigs
                                }
                                .foregroundColor(.red)
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }
                        Button("+ Add Hot Word") {
                            showingAddHotWord = true
                        }
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(BrutalistTheme.neonGreen)
                    }
                    .padding(8)
                }
            }
            .padding()
        }
        .onAppear {
            groqKey = appState.groqAPIKey
            anthropicKey = SettingsManager.shared.anthropicAPIKey
            localHotWordConfigs = SettingsManager.shared.hotWordConfigs
        }
        .onChange(of: groqKey) { appState.groqAPIKey = $0; validationResult = nil }
        .onChange(of: anthropicKey) { SettingsManager.shared.anthropicAPIKey = $0 }
        .sheet(isPresented: $showingAddHotWord) {
            HotWordEditView(configs: Binding(
                get: { localHotWordConfigs },
                set: {
                    localHotWordConfigs = $0
                    SettingsManager.shared.hotWordConfigs = $0
                }
            ))
        }
    }

    private func validateKey() {
        isValidating = true
        Task {
            let result = await TranscriptionService.validateAPIKey(groqKey)
            await MainActor.run {
                validationResult = result
                isValidating = false
            }
        }
    }
}

// MARK: - Logs Tab

struct LogsTabView: View {
    @ObservedObject var appState: AppState
    @State private var entries: [LogEntry] = []
    @State private var filterComponent: LogComponent? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabHeader("LOGS") {
                HStack {
                    Picker("Component", selection: $filterComponent) {
                        Text("All").tag(LogComponent?.none)
                        ForEach([LogComponent.audio, .transcribe, .extract, .world, .todo, .clipboard, .paste, .qa, .system, .ui], id: \.self) { c in
                            Text(c.rawValue).tag(LogComponent?.some(c))
                        }
                    }
                    .frame(width: 140)
                    Button("Refresh") { loadLogs() }
                        .buttonStyle(.bordered)
                }
            }
            Divider()
            ScrollViewReader { proxy in
                List(entries.indices, id: \.self) { i in
                    let entry = entries[i]
                    Text(entry.formatted)
                        .font(.custom("JetBrains Mono", size: 10))
                        .foregroundColor(logColor(entry.level))
                        .id(i)
                }
                .listStyle(.plain)
                .onChange(of: entries.count) { _ in
                    if let last = entries.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
        .onAppear { loadLogs() }
        .onChange(of: filterComponent) { _ in loadLogs() }
    }

    private func loadLogs() {
        entries = Log.snapshot(limit: 200, component: filterComponent)
    }

    private func logColor(_ level: LogLevel) -> Color {
        switch level {
        case .debug: return .secondary
        case .info:  return .primary
        case .warn:  return .orange
        case .error: return .red
        }
    }
}

// MARK: - Shared Header

struct TabHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title)
                .font(BrutalistTheme.monoLG)
                .foregroundColor(.white)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - HotWordEditView

struct HotWordEditView: View {
    @Binding var configs: [HotWordConfig]
    @Environment(\.dismiss) var dismiss
    @State private var keyword = ""
    @State private var action: HotWordAction = .addTodo
    @State private var label = ""
    @State private var skipPermissions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Hot Word")
                .font(.system(.headline, design: .monospaced))
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
        .padding(20)
        .frame(width: 360)
        .font(.system(.body, design: .monospaced))
    }
}
