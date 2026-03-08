import AppKit
import SwiftUI

// MARK: - Panel Tab

enum PanelTab: String, CaseIterable, Identifiable {
    case world    = "World"
    case projects = "Projects"
    case logs     = "Logs"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .world:    return "globe"
        case .projects: return "folder"
        case .logs:     return "doc.text"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - MainPanelView

struct MainPanelView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: PanelTab = .world

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
    // ZStack keeps all tabs alive (not destroyed on switch) so PixelWorldView
    // retains its WKWebView and pipeline subscriptions across tab changes.

    @ViewBuilder
    private var content: some View {
        ZStack {
            // PixelWorldView is always alive to preserve WKWebView state,
            // but hidden during Call Mode (replaced by zoom-call view).
            PixelWorldView(appState: appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == .world && appState.pillMode != .callMode ? 1 : 0)
                .allowsHitTesting(selectedTab == .world && appState.pillMode != .callMode)

            // Call Mode room: replaces HQ view when Call Mode is active.
            CallModeRoomView(appState: appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == .world && appState.pillMode == .callMode ? 1 : 0)
                .allowsHitTesting(selectedTab == .world && appState.pillMode == .callMode)

            ProjectsListView(appState: appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == .projects ? 1 : 0)
                .allowsHitTesting(selectedTab == .projects)

            LogsPipelineView(appState: appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == .logs ? 1 : 0)
                .allowsHitTesting(selectedTab == .logs)

            SettingsConsolidatedView(appState: appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == .settings ? 1 : 0)
                .allowsHitTesting(selectedTab == .settings)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

// MARK: - CallModeZoomView

/// 3-panel "zoom call" layout shown in the panel's World tab when Call Mode is active.
/// Top: scrollable Claude message thread. Bottom: camera (left) + screen preview (right).
struct CallModeZoomView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 1) {
            // Top: Claude messages thread
            messagesPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom: camera + screen side by side
            HStack(spacing: 1) {
                cameraPanel
                screenPanel
            }
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 220)
        }
        .background(Color.black)
    }

    // MARK: - Messages Panel

    private var messagesPanel: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .windowBackgroundColor).opacity(0.05)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(appState.callModeSession.messages) { msg in
                            CallZoomMessageRow(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: appState.callModeSession.messages.count) { _ in
                    if let last = appState.callModeSession.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            // Processing indicator
            if appState.callModeSession.isProcessing {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini).tint(.cyan)
                        Text("Claude thinking…")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.cyan.opacity(0.7))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }

            // Empty state
            if appState.callModeSession.messages.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "phone.bubble")
                        .font(.system(size: 32))
                        .foregroundColor(.cyan.opacity(0.25))
                    Text("CALL MODE ACTIVE")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.3))
                    Text("Speak to start the call")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Camera Panel

    private var cameraPanel: some View {
        ZStack {
            Color.black
            if appState.cameraEnabled && appState.cameraService.isRunning {
                CameraPreviewView(session: appState.cameraService.captureSession)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.15))
                    Text("Camera Off")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
                }
            }
            VStack {
                Spacer()
                HStack {
                    feedBadge(label: "LIVE", color: .red)
                    Spacer()
                }
                .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }

    // MARK: - Screen Panel

    private var screenPanel: some View {
        ZStack {
            Color.black
            if let img = appState.screenPreviewImage {
                Image(decorative: img, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.15))
                    Text("No Screen")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
                }
            }
            VStack {
                Spacer()
                HStack {
                    feedBadge(label: "SCREEN", color: .cyan)
                    Spacer()
                }
                .padding(8)
            }
        }
    }

    // MARK: - Badge

    private func feedBadge(label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.black.opacity(0.6)))
    }
}

// MARK: - CallZoomMessageRow

private struct CallZoomMessageRow: View {
    let message: CallMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(roleColor)
                .frame(width: 7, height: 7)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(roleLabel)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(roleColor.opacity(0.6))
                Text(message.text)
                    .font(.system(size: 12,
                                  design: message.role == .tool ? .monospaced : .default))
                    .foregroundColor(.primary.opacity(message.role == .user ? 1.0 : 0.85))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var roleColor: Color {
        switch message.role {
        case .user:        return .white
        case .assistant:   return .cyan
        case .tool:        return .yellow
        case .error:       return .red
        case .external:    return .green
        case .participant: return .purple
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .user:        return "YOU"
        case .assistant:   return "CLAUDE"
        case .tool:        return "TOOL"
        case .error:       return "ERR"
        case .external:    return "CC"
        case .participant: return message.participantName?.uppercased() ?? "PLUGIN"
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
