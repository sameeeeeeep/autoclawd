import AppKit
import SwiftUI

// MARK: - Panel Tab

enum PanelTab: String, CaseIterable, Identifiable {
    case agents   = "Agents"
    case tasks    = "Tasks"
    case projects = "Projects"
    case logs     = "Logs"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .agents:   return "bolt.fill"
        case .tasks:    return "checklist"
        case .projects: return "folder"
        case .logs:     return "doc.text"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - MainPanelView

struct MainPanelView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: PanelTab = .agents

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
        .onChange(of: appState.pillMode) { newMode in
            if newMode == .learn { selectedTab = .tasks }
        }
        .onChange(of: appState.learnModeService.isActive) { active in
            if active { selectedTab = .tasks }
        }
        .onReceive(appState.$activeTab) { newTab in
            selectedTab = newTab
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ZStack {
            AgentsView(appState: appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == .agents ? 1 : 0)
                .allowsHitTesting(selectedTab == .agents)

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

            TasksView(appState: appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(selectedTab == .tasks ? 1 : 0)
                .allowsHitTesting(selectedTab == .tasks)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

// MARK: - Tab Header

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

// MARK: - Add Project Sheet

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
