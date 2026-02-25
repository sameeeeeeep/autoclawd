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
        }
    }
}

// MARK: - MainPanelView

struct MainPanelView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: PanelTab = .todos
    @State private var transcriptSearch = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Logo
            HStack {
                Text("AutoClawd")
                    .font(BrutalistTheme.monoLG)
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
        }
    }
}

// MARK: - Todo Tab

struct TodoTabView: View {
    @ObservedObject var appState: AppState
    @State private var content: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabHeader("TO-DO LIST") {
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
            appState.saveTodos(newVal)
        }
    }

    private func loadContent() {
        content = appState.todosContent
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
                TranscriptRowView(record: record)
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
    @State private var expanded = false

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
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings Tab

struct SettingsTabView: View {
    @ObservedObject var appState: AppState
    @State private var groqKey = ""
    @State private var isValidating = false
    @State private var validationResult: Bool? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TabHeader("SETTINGS") { EmptyView() }

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

                GroupBox("Data") {
                    HStack {
                        Button("Export All") { appState.exportData() }
                        Button("Delete All", role: .destructive) { appState.confirmDeleteAll() }
                    }
                    .padding(8)
                }
            }
            .padding()
        }
        .onAppear { groqKey = appState.groqAPIKey }
        .onChange(of: groqKey) { appState.groqAPIKey = $0; validationResult = nil }
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
