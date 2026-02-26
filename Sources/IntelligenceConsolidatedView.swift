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
    @State private var logContent: String = ""

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
        ScrollView {
            Text(logContent.isEmpty ? "No logs yet." : logContent)
                .font(AppTheme.mono)
                .foregroundColor(logContent.isEmpty ? AppTheme.textSecondary : AppTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.lg)
                .textSelection(.enabled)
        }
        .background(AppTheme.surface)
    }

    private func loadLogs() {
        // Try common AutoClawd log paths
        let candidates: [URL] = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".autoclawd/autoclawd.log"),
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?.appendingPathComponent("AutoClawd/autoclawd.log") ?? URL(fileURLWithPath: "/dev/null")
        ]
        for url in candidates {
            if let content = try? String(contentsOf: url, encoding: .utf8), !content.isEmpty {
                logContent = content
                return
            }
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
