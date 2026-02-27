import SwiftUI

// MARK: - Sub-tab

enum IntelligenceSubTab: String, CaseIterable {
    case extractions = "Extractions"
    case worldModel  = "World Model"
    case logs        = "Logs"
}

// MARK: - IntelligenceConsolidatedView

struct IntelligenceConsolidatedView: View {
    @ObservedObject var appState: AppState
    @State private var subTab: IntelligenceSubTab = .extractions
    @State private var expandedChunk: Int? = nil
    @State private var worldModelText: String = ""
    @State private var logEntries: [LogEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            // Sub-tab header + context actions
            HStack(spacing: 0) {
                ForEach(IntelligenceSubTab.allCases, id: \.self) { tab in
                    Button { subTab = tab } label: {
                        VStack(spacing: AppTheme.xs) {
                            Text(tab.rawValue)
                                .font(subTab == tab ? AppTheme.label : AppTheme.body)
                                .foregroundColor(subTab == tab ? AppTheme.textPrimary : AppTheme.textSecondary)
                                .padding(.horizontal, AppTheme.lg)
                            Rectangle()
                                .fill(subTab == tab ? AppTheme.green : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if subTab == .extractions {
                    extractionActions
                        .padding(.trailing, AppTheme.lg)
                } else if subTab == .logs {
                    Button {
                        loadLogs()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(AppTheme.caption)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .controlSize(.small)
                    .padding(.trailing, AppTheme.lg)
                }
            }
            .padding(.top, AppTheme.md)

            Divider()

            // Content pane
            Group {
                switch subTab {
                case .extractions: extractionsContent
                case .worldModel:  worldModelContent
                case .logs:        logsContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.background)
        .onAppear {
            appState.refreshExtractionItems()
            let grouped = Dictionary(grouping: appState.extractionItems, by: \.chunkIndex)
            expandedChunk = grouped.keys.max()
            worldModelText = appState.worldModelContent
            loadLogs()
        }
    }

    // MARK: - Extraction Actions

    private var extractionActions: some View {
        HStack(spacing: AppTheme.sm) {
            Text(appState.pendingExtractionCount == 0
                 ? "No pending"
                 : "\(appState.pendingExtractionCount) pending")
                .font(AppTheme.caption)
                .foregroundColor(AppTheme.textSecondary)

            Picker("", selection: $appState.synthesizeThreshold) {
                Text("Manual").tag(0)
                Text("Auto: 5").tag(5)
                Text("Auto: 10").tag(10)
                Text("Auto: 20").tag(20)
            }
            .pickerStyle(.menu)
            .frame(width: 90)

            Button("Synthesize") { Task { await appState.synthesizeNow() } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(appState.pendingExtractionCount == 0)

            Button("Clean Up") { Task { await appState.cleanupNow() } }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(appState.isCleaningUp)
        }
    }

    // MARK: - Extractions Content

    @ViewBuilder
    private var extractionsContent: some View {
        let grouped = Dictionary(grouping: appState.extractionItems, by: \.chunkIndex)
        let sortedChunks = grouped.keys.sorted(by: >)

        if sortedChunks.isEmpty {
            emptyState(icon: "brain", message: "No extraction items yet.")
        } else {
            List(sortedChunks, id: \.self) { chunkIdx in
                let items = grouped[chunkIdx] ?? []
                ChunkGroupView(
                    chunkIndex: chunkIdx,
                    items: items,
                    isExpanded: expandedChunk == chunkIdx,
                    onToggle: {
                        expandedChunk = expandedChunk == chunkIdx ? nil : chunkIdx
                    },
                    onToggleItem: { appState.toggleExtraction(id: $0) },
                    onSetBucket: { appState.setExtractionBucket(id: $0, bucket: $1) }
                )
            }
            .listStyle(.plain)
        }
    }

    // MARK: - World Model Content

    private var worldModelContent: some View {
        TextEditor(text: $worldModelText)
            .font(AppTheme.mono)
            .foregroundColor(AppTheme.textPrimary)
            .padding(AppTheme.lg)
            .onChange(of: worldModelText) { newVal in
                appState.saveWorldModel(newVal)
            }
    }

    // MARK: - Logs Content

    private var logsContent: some View {
        Group {
            if logEntries.isEmpty {
                emptyState(icon: "doc.text", message: "No logs yet.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(logEntries.indices, id: \.self) { i in
                            logRow(logEntries[i])
                            if i < logEntries.count - 1 {
                                Divider().opacity(0.4)
                            }
                        }
                    }
                    .padding(AppTheme.md)
                }
            }
        }
        .background(AppTheme.surface)
        .task {
            while true {
                try? await Task.sleep(for: .seconds(2))
                loadLogs()
            }
        }
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: AppTheme.sm) {
            Text(shortTime(entry.timestamp))
                .font(AppTheme.mono)
                .foregroundColor(AppTheme.textDisabled)
                .frame(width: 60, alignment: .leading)

            Text(entry.level.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(levelColor(entry.level))
                .frame(width: 36, alignment: .leading)

            Text("[\(entry.component.rawValue)]")
                .font(AppTheme.mono)
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 80, alignment: .leading)

            Text(entry.message)
                .font(AppTheme.mono)
                .foregroundColor(AppTheme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, AppTheme.xs)
        .padding(.horizontal, AppTheme.sm)
    }

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .error: return AppTheme.destructive
        case .warn:  return .orange
        case .info:  return AppTheme.textSecondary
        case .debug: return AppTheme.textDisabled
        }
    }

    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    private func loadLogs() {
        // 1. In-memory snapshot (always available while app is running)
        let entries = AutoClawdLogger.shared.snapshot(limit: 500)
        if !entries.isEmpty {
            logEntries = entries.reversed()
            return
        }
        // 2. Fallback: parse today's log file
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let dateStr = f.string(from: Date())
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".autoclawd/logs/autoclawd-\(dateStr).log")
        guard let raw = try? String(contentsOf: url, encoding: .utf8), !raw.isEmpty else { return }
        logEntries = raw.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .reversed()
            .map { line in
                LogEntry(timestamp: Date(), level: .info, component: .system, message: line)
            }
    }

    // MARK: - Empty State

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: AppTheme.md) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(AppTheme.border)
            Text(message)
                .font(AppTheme.body)
                .foregroundColor(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }
}
