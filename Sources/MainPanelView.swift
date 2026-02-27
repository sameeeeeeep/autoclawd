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

    var label: String {
        switch self {
        case .time:  return "\u{1F550} Time"
        case .space: return "\u{1F4CD} Space"
        }
    }
}

// MARK: - MainPanelView

struct MainPanelView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: PanelTab = .world
    @State private var selectedWorldSubTab: WorldSubTab = .time

    var body: some View {
        let theme = ThemeManager.shared.current
        HStack(spacing: 0) {
            navRail
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.glass)
                .background(.ultraThinMaterial)
                .overlay(ambientGlowOverlays)
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(theme.bgGradientStops.first ?? theme.surface)
    }

    // MARK: - Ambient Glow Overlays

    private var ambientGlowOverlays: some View {
        let theme = ThemeManager.shared.current
        return ZStack {
            // Top-right radial gradient
            RadialGradient(
                colors: [theme.glow1.opacity(0.06), Color.clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 210
            )
            .frame(width: 420, height: 420)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // Bottom-left radial gradient
            RadialGradient(
                colors: [theme.glow2.opacity(0.05), Color.clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 170
            )
            .frame(width: 340, height: 340)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Nav Rail (56px)

    private var navRail: some View {
        let theme = ThemeManager.shared.current
        return VStack(spacing: 0) {
            // Glowing dot logo
            Circle()
                .fill(theme.accent)
                .frame(width: 11, height: 11)
                .shadow(color: theme.accent.opacity(0.5), radius: 12)
                .shadow(color: theme.accent.opacity(0.15), radius: 30)
                .padding(.top, 16)
                .padding(.bottom, 20)

            // Nav items
            VStack(spacing: 2) {
                ForEach(PanelTab.allCases) { tab in
                    navItem(tab: tab)
                }
            }

            Spacer()

            // Status dot
            Circle()
                .fill(appState.isListening
                    ? theme.accent
                    : theme.textSecondary.opacity(0.4))
                .frame(width: 5, height: 5)
                .padding(.bottom, 16)
        }
        .frame(width: 56)
        .background(
            theme.isDark
                ? Color.black.opacity(0.18)
                : Color.black.opacity(0.02)
        )
    }

    // MARK: - Nav Item

    private func navItem(tab: PanelTab) -> some View {
        let theme = ThemeManager.shared.current
        let isActive = selectedTab == tab

        return Button {
            selectedTab = tab
        } label: {
            ZStack(alignment: .leading) {
                // Active indicator bar
                if isActive {
                    RoundedRectangle(cornerRadius: 1.25)
                        .fill(theme.accent)
                        .frame(width: 2.5, height: 14)
                        .offset(x: -16.75) // Position at far left of the 40pt item
                }

                VStack(spacing: 2) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 16))
                        .foregroundColor(isActive ? theme.accent : theme.textTertiary)
                        .frame(width: 40, height: 28)

                    Text(tab.rawValue)
                        .font(.system(size: 7, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? theme.accent : theme.textTertiary)
                }
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isActive ? theme.accent.opacity(0.04) : Color.clear)
                )
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .frame(width: 56, height: 46) // Full rail width for centering
        .help(tab.rawValue)
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
        let theme = ThemeManager.shared.current
        return HStack(spacing: 16) {
            ForEach(WorldSubTab.allCases) { subTab in
                let isActive = selectedWorldSubTab == subTab
                Button {
                    selectedWorldSubTab = subTab
                } label: {
                    VStack(spacing: 4) {
                        Text(subTab.label)
                            .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                            .foregroundColor(isActive ? theme.accent : theme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.top, 8)
                            .padding(.bottom, 4)

                        // Underline indicator
                        Rectangle()
                            .fill(isActive ? theme.accent : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .overlay(
            Rectangle()
                .fill(theme.glassBorder)
                .frame(height: 1),
            alignment: .bottom
        )
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
                            .foregroundColor(AppTheme.textSecondary)
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

// MARK: - AddProjectSheet

struct AddProjectSheet: View {
    @Binding var isPresented: Bool
    let onAdd: (String, String) -> Void
    @State private var name = ""
    @State private var path = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ADD PROJECT").font(AppTheme.heading)

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
                .font(AppTheme.heading)
                .foregroundColor(.white)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
