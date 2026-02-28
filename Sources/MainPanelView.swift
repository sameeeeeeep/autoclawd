import AppKit
import SwiftUI

// MARK: - Panel Tab

enum PanelTab: String, CaseIterable, Identifiable {
    case world    = "World"
    case logs     = "Logs"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .world:    return "globe"
        case .logs:     return "doc.text"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - World Sub-Tab

enum WorldSubTab: String, CaseIterable, Identifiable {
    case time  = "Time"
    case space = "Space"

    var id: String { rawValue }
}

// MARK: - MainPanelView

struct MainPanelView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: PanelTab = .world
    @State private var selectedWorldSubTab: WorldSubTab = .time

    var body: some View {
        NavigationSplitView {
            List(PanelTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 140, ideal: 170, max: 220)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.isListening ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(appState.isListening ? "Listening" : "Idle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        } detail: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .world:
            VStack(spacing: 0) {
                worldSubTabBar
                worldSubTabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .logs:
            LogsPipelineView(appState: appState)
        case .settings:
            SettingsConsolidatedView(appState: appState)
        }
    }

    // MARK: - World Sub-Tab Bar

    private var worldSubTabBar: some View {
        Picker("View", selection: $selectedWorldSubTab) {
            ForEach(WorldSubTab.allCases) { subTab in
                Text(subTab.rawValue).tag(subTab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - World Sub-Tab Content

    @ViewBuilder
    private var worldSubTabContent: some View {
        switch selectedWorldSubTab {
        case .time:
            WorldTimeView(appState: appState)
        case .space:
            WorldSpaceView(appState: appState)
        }
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
                        .font(AppTheme.body)
                        .lineLimit(2)
                    if let p = project {
                        Text(p.name + " · " + p.localPath)
                            .font(AppTheme.caption)
                            .foregroundColor(.secondary)
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
                                .font(.system(size: 11, design: .monospaced))
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
                    .font(AppTheme.caption)
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
        .frame(minWidth: 380, idealWidth: 540, minHeight: 360, idealHeight: 440)
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

// MARK: - AddProjectSheet

struct AddProjectSheet: View {
    @Binding var isPresented: Bool
    let onAdd: (String, String) -> Void
    @State private var name = ""
    @State private var path = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Project").font(.headline)

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
        .frame(minWidth: 300, idealWidth: 400, maxWidth: 480)
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
                .font(.headline)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
