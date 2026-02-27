import SwiftUI

// MARK: - View Mode

private enum PipelineViewMode: String, CaseIterable {
    case pipeline = "Pipeline"
    case rawLogs  = "Raw Logs"
}

// MARK: - Status Color Helper

private func statusColor(_ status: String, theme: ThemePalette) -> Color {
    switch status {
    case "completed", "accepted", "relevant":
        return theme.accent
    case "ongoing", "pending":
        return theme.warning
    case "pending_approval":
        return theme.warning
    case "needs_input":
        return theme.secondary
    case "dismissed", "nonrelevant":
        return theme.error
    default:
        return theme.textTertiary
    }
}

// MARK: - LogsPipelineView

struct LogsPipelineView: View {
    @ObservedObject var appState: AppState

    @State private var viewMode: PipelineViewMode = .pipeline
    @State private var filterProject: String? = nil
    @State private var filterBucket: ExtractionBucket? = nil
    @State private var filterState: String? = nil
    @State private var selectedRowID: String? = nil
    @State private var expandedStage: String? = nil
    @State private var logEntries: [LogEntry] = []
    @State private var transcripts: [TranscriptRecord] = []

    // MARK: - Derived Data

    /// Build pipeline groups from real extraction items, paired with transcripts.
    private var pipelineGroups: [PipelineGroup] {
        let items = appState.extractionItems
        guard !items.isEmpty else { return [] }

        // Group extraction items by chunkIndex
        let grouped = Dictionary(grouping: items, by: \.chunkIndex)
        let sortedChunks = grouped.keys.sorted(by: >)

        return sortedChunks.compactMap { chunkIdx -> PipelineGroup? in
            guard let chunkItems = grouped[chunkIdx], !chunkItems.isEmpty else { return nil }

            // Use the first item's timestamp as representative
            let representative = chunkItems.first!
            let timeStr = Self.timeFormatter.string(from: representative.timestamp)
            let timeSeconds = Calendar.current.component(.hour, from: representative.timestamp) * 3600
                + Calendar.current.component(.minute, from: representative.timestamp) * 60

            // Find matching transcript by timestamp proximity (within 60 seconds)
            let matchingTranscripts = transcripts.filter { tr in
                abs(tr.timestamp.timeIntervalSince(representative.timestamp)) < 60
            }

            // Build raw chunks from matching transcripts
            let rawChunks: [RawChunk]
            if matchingTranscripts.isEmpty {
                // Use the source phrase from the extraction item as a fallback
                rawChunks = [
                    RawChunk(
                        id: "chunk-\(chunkIdx)",
                        duration: "",
                        text: representative.sourcePhrase
                    )
                ]
            } else {
                rawChunks = matchingTranscripts.map { tr in
                    let label = tr.sessionID.map { "\($0.prefix(6))" } ?? "t\(tr.id)"
                    let dur = tr.durationSeconds > 0 ? "\(tr.durationSeconds)s" : ""
                    return RawChunk(id: label, duration: dur, text: tr.text)
                }
            }

            // Derive cleaning info from extraction items
            let cleaningTags: [String] = {
                var tags: [String] = []
                if rawChunks.count > 1 {
                    tags.append("\(rawChunks.count) chunks merged")
                }
                let dismissed = chunkItems.filter { $0.isDismissed }
                if !dismissed.isEmpty {
                    tags.append("\(dismissed.count) filtered")
                }
                let accepted = chunkItems.filter { $0.isAccepted }
                if !accepted.isEmpty {
                    tags.append("\(accepted.count) accepted")
                }
                return tags
            }()

            // Cleaned text: combine accepted item contents
            let acceptedItems = chunkItems.filter { $0.isAccepted }
            let cleanedText = acceptedItems.isEmpty
                ? nil
                : acceptedItems.map(\.content).joined(separator: " ")

            // Analysis info from extraction items
            let analysisTags: [String] = {
                var tags: [String] = []
                let types = Set(chunkItems.map(\.type))
                for t in types { tags.append(t.rawValue) }
                let buckets = Set(chunkItems.map(\.bucket))
                for b in buckets { tags.append(b.displayName) }
                return tags
            }()

            // Try to find a project for this group
            let analysisProject: String? = {
                // Check if any matching transcript has a projectID
                if let pid = matchingTranscripts.first(where: { $0.projectID != nil })?.projectID {
                    return appState.projects.first(where: { $0.id == pid.uuidString })?.name
                }
                return nil
            }()

            let analysisText = acceptedItems.isEmpty
                ? nil
                : "\(acceptedItems.count) extraction(s): " + acceptedItems.map(\.content).prefix(2).joined(separator: "; ")

            // Build pipeline tasks from extraction items
            let tasks: [PipelineTask] = chunkItems.map { item in
                let taskStatus: TaskStatus = {
                    switch item.effectiveState {
                    case "relevant", "accepted":
                        return item.applied ? .completed : .pending_approval
                    case "nonrelevant", "dismissed":
                        return .filtered
                    default:
                        return .ongoing
                    }
                }()

                let resultSteps: [String] = {
                    var steps: [String] = []
                    steps.append("Source: \"\(String(item.sourcePhrase.prefix(60)))\"")
                    steps.append("Type: \(item.type.rawValue), Bucket: \(item.bucket.displayName)")
                    if let priority = item.priority {
                        steps.append("Priority: \(priority)")
                    }
                    steps.append("Model decision: \(item.modelDecision)")
                    if let override = item.userOverride {
                        steps.append("User override: \(override)")
                    }
                    if item.applied {
                        steps.append("Applied to world model/todos")
                    }
                    return steps
                }()

                return PipelineTask(
                    id: String(item.id.prefix(10)),
                    title: item.content,
                    prompt: item.sourcePhrase,
                    project: analysisProject ?? item.bucket.displayName,
                    mode: item.userOverride != nil ? .user : .auto,
                    status: taskStatus,
                    skill: nil,
                    workflow: nil,
                    workflowSteps: [],
                    missingConnection: nil,
                    pendingQuestion: nil,
                    result: TaskResult(
                        steps: resultSteps,
                        finalStatus: item.effectiveState,
                        duration: item.priorityLabel
                    )
                )
            }

            return PipelineGroup(
                id: "chunk-\(chunkIdx)",
                rawChunks: rawChunks,
                cleaningTags: cleaningTags,
                cleanedText: cleanedText,
                analysisTags: analysisTags,
                analysisProject: analysisProject,
                analysisText: analysisText,
                tasks: tasks,
                placeTag: nil,
                personTag: matchingTranscripts.first?.speakerName,
                time: timeStr,
                timeSeconds: timeSeconds
            )
        }
    }

    private var filteredGroups: [PipelineGroup] {
        pipelineGroups.filter { group in
            if let fp = filterProject {
                if group.analysisProject != fp { return false }
            }
            if let fb = filterBucket {
                // Check if any task in the group references this bucket
                let bucketName = fb.displayName
                let hasBucket = group.analysisTags.contains(bucketName)
                if !hasBucket { return false }
            }
            if let fs = filterState {
                let hasState = group.tasks.contains { $0.status.rawValue == fs }
                if !hasState && !group.tasks.isEmpty { return false }
                if group.tasks.isEmpty && fs != "filtered" { return false }
            }
            return true
        }
    }

    private var anyFilterActive: Bool {
        filterProject != nil || filterBucket != nil || filterState != nil
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    // MARK: - Body

    var body: some View {
        let theme = ThemeManager.shared.current
        VStack(spacing: 0) {
            filterBar
            HStack(spacing: 0) {
                Group {
                    switch viewMode {
                    case .pipeline:
                        pipelineContent
                    case .rawLogs:
                        rawLogsContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if selectedRowID != nil, viewMode == .pipeline {
                    detailSidebar
                        .frame(width: 300)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .background(theme.isDark ? Color.black.opacity(0.05) : Color.black.opacity(0.01))
        .onAppear { loadData() }
        .task {
            // Auto-refresh every 2 seconds
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                loadData()
            }
        }
    }

    private func loadData() {
        appState.refreshExtractionItems()
        transcripts = appState.recentTranscripts()
        logEntries = AutoClawdLogger.shared.snapshot(limit: 500).reversed()
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        let theme = ThemeManager.shared.current
        return VStack(alignment: .leading, spacing: 8) {
            // Title row
            HStack(spacing: 8) {
                Text("Pipeline Logs")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(theme.textPrimary)

                // View mode picker
                Picker("", selection: $viewMode) {
                    ForEach(PipelineViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                if viewMode == .pipeline {
                    TagView(type: .status, label: "\(filteredGroups.count) groups", small: true)
                } else {
                    TagView(type: .status, label: "\(logEntries.count) entries", small: true)
                }

                Spacer()

                // Extraction actions
                if viewMode == .pipeline {
                    extractionActions
                }
            }

            // Filter row (only for pipeline mode)
            if viewMode == .pipeline {
                HStack(spacing: 6) {
                    Text("Filter:")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundColor(theme.textTertiary)
                        .padding(.trailing, 2)

                    // Project filters (from real projects)
                    ForEach(appState.projects, id: \.id) { project in
                        filterChip(
                            label: project.name,
                            isActive: filterProject == project.name,
                            activeColor: theme.tagProject
                        ) {
                            filterProject = filterProject == project.name ? nil : project.name
                        }
                    }

                    if !appState.projects.isEmpty {
                        filterSeparator
                    }

                    // Bucket filters
                    ForEach(ExtractionBucket.allCases, id: \.self) { bucket in
                        filterChip(
                            label: bucket.displayName,
                            isActive: filterBucket == bucket,
                            activeColor: theme.tagAction
                        ) {
                            filterBucket = filterBucket == bucket ? nil : bucket
                        }
                    }

                    filterSeparator

                    // State filters
                    ForEach(["pending_approval", "completed", "filtered"], id: \.self) { state in
                        filterChip(
                            label: state.replacingOccurrences(of: "_", with: " "),
                            isActive: filterState == state,
                            activeColor: statusColor(state, theme: theme)
                        ) {
                            filterState = filterState == state ? nil : state
                        }
                    }

                    // Clear button
                    if anyFilterActive {
                        Button {
                            filterProject = nil
                            filterBucket = nil
                            filterState = nil
                        } label: {
                            Text("Clear")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(theme.error)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(theme.error.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .overlay(
            Rectangle()
                .fill(theme.glassBorder)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Extraction Actions

    private var extractionActions: some View {
        let theme = ThemeManager.shared.current
        return HStack(spacing: 6) {
            Text(appState.pendingExtractionCount == 0
                 ? "No pending"
                 : "\(appState.pendingExtractionCount) pending")
                .font(.system(size: 9))
                .foregroundColor(theme.textSecondary)

            Picker("", selection: $appState.synthesizeThreshold) {
                Text("Manual").tag(0)
                Text("Auto: 5").tag(5)
                Text("Auto: 10").tag(10)
                Text("Auto: 20").tag(20)
            }
            .pickerStyle(.menu)
            .frame(width: 80)

            Button {
                Task { await appState.synthesizeNow() }
            } label: {
                Text("Synthesize")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(theme.accent.opacity(0.18))
                    )
            }
            .buttonStyle(.plain)
            .disabled(appState.pendingExtractionCount == 0)

            Button {
                Task { await appState.cleanupNow() }
            } label: {
                Text(appState.isCleaningUp ? "Cleaning..." : "Clean Up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(theme.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(theme.tertiary.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .disabled(appState.isCleaningUp)
        }
    }

    private var filterSeparator: some View {
        let theme = ThemeManager.shared.current
        return Rectangle()
            .fill(theme.glassBorder)
            .frame(width: 1, height: 12)
    }

    private func filterChip(
        label: String,
        isActive: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(isActive ? activeColor : ThemeManager.shared.current.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isActive ? activeColor.opacity(0.18) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            isActive ? activeColor.opacity(0.50) : ThemeManager.shared.current.glassBorder,
                            lineWidth: 0.5
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pipeline Content

    private var pipelineContent: some View {
        let theme = ThemeManager.shared.current
        return VStack(spacing: 0) {
            if filteredGroups.isEmpty {
                emptyPipelineState
            } else {
                columnHeaderRow
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredGroups) { group in
                            pipelineRow(group: group)
                        }
                    }
                }
            }
        }
        .background(theme.isDark ? Color.clear : Color.clear)
    }

    private var emptyPipelineState: some View {
        let theme = ThemeManager.shared.current
        return VStack(spacing: 12) {
            Spacer()
            Image(systemName: "waveform.path")
                .font(.system(size: 32))
                .foregroundColor(theme.glassBorder)
            Text("No pipeline data yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.textSecondary)
            Text("Start listening to see transcripts flow through the pipeline.")
                .font(.system(size: 10))
                .foregroundColor(theme.textTertiary)
                .multilineTextAlignment(.center)
            if appState.isListening {
                LiveBadge()
                    .padding(.top, 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Raw Logs Content

    private var rawLogsContent: some View {
        let theme = ThemeManager.shared.current
        return Group {
            if logEntries.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundColor(theme.glassBorder)
                    Text("No logs yet.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .padding(8)
                }
            }
        }
    }

    private func logRow(_ entry: LogEntry) -> some View {
        let theme = ThemeManager.shared.current
        return HStack(alignment: .top, spacing: 6) {
            Text(Self.logTimeFormatter.string(from: entry.timestamp))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(theme.textTertiary)
                .frame(width: 60, alignment: .leading)

            Text(entry.level.rawValue)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(logLevelColor(entry.level))
                .frame(width: 36, alignment: .leading)

            Text("[\(entry.component.rawValue)]")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(theme.textSecondary)
                .frame(width: 80, alignment: .leading)

            Text(entry.message)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(theme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            entry.level == .error
                ? ThemeManager.shared.current.error.opacity(0.06)
                : entry.level == .warn
                    ? ThemeManager.shared.current.warning.opacity(0.04)
                    : Color.clear
        )
    }

    private func logLevelColor(_ level: LogLevel) -> Color {
        let theme = ThemeManager.shared.current
        switch level {
        case .error: return theme.error
        case .warn:  return .orange
        case .info:  return theme.textSecondary
        case .debug: return theme.textTertiary
        }
    }

    private static let logTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: - Column Header Row

    private var columnHeaderRow: some View {
        let theme = ThemeManager.shared.current
        return HStack(spacing: 0) {
            columnHeader("TIME", color: theme.textTertiary)
                .frame(width: 55)
            columnHeader("TRANSCRIPT", color: theme.textSecondary)
                .frame(maxWidth: .infinity)
                .layoutPriority(1.2)
            columnHeader("CLEANING", color: theme.tertiary)
                .frame(maxWidth: .infinity)
                .layoutPriority(1.2)
            columnHeader("ANALYSIS", color: theme.secondary)
                .frame(maxWidth: .infinity)
                .layoutPriority(1.0)
            columnHeader("TASK", color: theme.warning)
                .frame(maxWidth: .infinity)
                .layoutPriority(1.2)
            columnHeader("RESULT", color: theme.accent)
                .frame(maxWidth: .infinity)
                .layoutPriority(1.0)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 16)
        .overlay(
            Rectangle()
                .fill(theme.glassBorder)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    private func columnHeader(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold))
            .tracking(1)
            .foregroundColor(color)
    }

    // MARK: - Pipeline Row

    private func pipelineRow(group: PipelineGroup) -> some View {
        let theme = ThemeManager.shared.current
        let isSelected = selectedRowID == group.id
        let isMerged = group.rawChunks.count > 1

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedRowID = selectedRowID == group.id ? nil : group.id
                expandedStage = nil
            }
        } label: {
            HStack(spacing: 0) {
                // Left accent border
                Rectangle()
                    .fill(isSelected ? theme.accent : Color.clear)
                    .frame(width: 2)

                HStack(spacing: 0) {
                    // Time column
                    timeColumn(group: group)
                        .frame(width: 55)

                    // Transcript column
                    transcriptColumn(group: group)
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1.2)

                    // Cleaning column
                    cleaningColumn(group: group)
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1.2)

                    // Analysis column
                    analysisColumn(group: group)
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1.0)

                    // Task column
                    taskColumn(group: group)
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1.2)

                    // Result column
                    resultColumn(group: group)
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1.0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .frame(minHeight: isMerged ? 70 : 48)
            .background(isSelected ? theme.accent.opacity(0.06) : Color.clear)
            .overlay(
                Rectangle()
                    .fill(theme.isDark ? Color.white.opacity(0.02) : Color.black.opacity(0.03))
                    .frame(height: 0.5),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Time Column

    private func timeColumn(group: PipelineGroup) -> some View {
        let theme = ThemeManager.shared.current
        return VStack(alignment: .leading, spacing: 2) {
            Text(group.time)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(theme.textSecondary)
            if let firstChunk = group.rawChunks.first {
                Text(firstChunk.id.prefix(8))
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(theme.textTertiary)
            }
        }
    }

    // MARK: - Transcript Column

    private func transcriptColumn(group: PipelineGroup) -> some View {
        let theme = ThemeManager.shared.current
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(group.rawChunks) { chunk in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(chunk.id)
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(theme.textTertiary)
                        if !chunk.duration.isEmpty {
                            Text(chunk.duration)
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundColor(theme.textTertiary)
                        }
                    }
                    Text(String(chunk.text.prefix(55)))
                        .font(.system(size: 9))
                        .foregroundColor(theme.textSecondary.opacity(0.80))
                        .lineLimit(2)
                }
                .padding(4)
                .background(
                    group.rawChunks.count > 1
                        ? RoundedRectangle(cornerRadius: 4)
                            .fill(theme.glass.opacity(0.5))
                        : nil
                )
            }
        }
    }

    // MARK: - Cleaning Column

    private func cleaningColumn(group: PipelineGroup) -> some View {
        let theme = ThemeManager.shared.current
        return VStack(alignment: .leading, spacing: 3) {
            if !group.cleaningTags.isEmpty {
                HStack(spacing: 3) {
                    ForEach(group.cleaningTags, id: \.self) { tag in
                        TagView(type: .status, label: tag, small: true)
                    }
                }
            }
            if let cleaned = group.cleanedText {
                Text(String(cleaned.prefix(70)))
                    .font(.system(size: 9))
                    .foregroundColor(theme.tertiary.opacity(0.80))
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Analysis Column

    private func analysisColumn(group: PipelineGroup) -> some View {
        let theme = ThemeManager.shared.current
        return VStack(alignment: .leading, spacing: 3) {
            if !group.analysisTags.isEmpty {
                HStack(spacing: 3) {
                    ForEach(group.analysisTags, id: \.self) { tag in
                        TagView(type: .action, label: tag, small: true)
                    }
                }
            }
            if let proj = group.analysisProject {
                TagView(type: .project, label: proj, small: true)
            }
            if let text = group.analysisText {
                Text(String(text.prefix(55)))
                    .font(.system(size: 9))
                    .foregroundColor(theme.secondary.opacity(0.80))
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Task Column

    private func taskColumn(group: PipelineGroup) -> some View {
        let theme = ThemeManager.shared.current
        return VStack(alignment: .leading, spacing: 4) {
            if group.tasks.isEmpty {
                Text("\u{2014}")
                    .font(.system(size: 9))
                    .foregroundColor(theme.textTertiary)
            } else {
                ForEach(group.tasks) { task in
                    taskMiniCard(task: task, groupID: group.id)
                }
            }
        }
    }

    private func taskMiniCard(task: PipelineTask, groupID: String) -> some View {
        let theme = ThemeManager.shared.current
        let modeBadgeMode: ModeBadge.Mode = {
            switch task.mode {
            case .auto: return .auto
            case .ask:  return .ask
            case .user: return .user
            }
        }()

        // Extract the real extraction item ID from task ID
        let extractionID: String? = {
            // task.id is the first 10 chars of the extraction item ID
            // find the real ID from appState
            appState.extractionItems.first(where: { $0.id.hasPrefix(task.id) })?.id
        }()

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(task.id)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(theme.textTertiary)
                ModeBadge(mode: modeBadgeMode)
            }
            Text(String(task.title.prefix(50)))
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(theme.warning)
                .lineLimit(2)

            // Accept / Dismiss for pending tasks
            if task.status == .pending_approval || task.status == .ongoing {
                HStack(spacing: 4) {
                    Button {
                        if let eid = extractionID {
                            appState.toggleExtraction(id: eid)
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 7))
                            Text("Accept")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(theme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(theme.accent.opacity(0.18))
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        if let eid = extractionID {
                            appState.toggleExtraction(id: eid)
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "xmark")
                                .font(.system(size: 7))
                            Text("Dismiss")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(theme.error)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(theme.error.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(task.status == .filtered
                      ? theme.textTertiary.opacity(0.04)
                      : theme.warning.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(task.status == .filtered
                        ? theme.textTertiary.opacity(0.08)
                        : theme.warning.opacity(0.12),
                        lineWidth: 0.5)
        )
    }

    // MARK: - Result Column

    private func resultColumn(group: PipelineGroup) -> some View {
        let theme = ThemeManager.shared.current
        return VStack(alignment: .leading, spacing: 4) {
            if group.tasks.isEmpty {
                Text("\u{2014}")
                    .font(.system(size: 9))
                    .foregroundColor(theme.textTertiary)
            } else {
                ForEach(group.tasks) { task in
                    HStack(spacing: 4) {
                        StatusDot(status: task.status.rawValue)
                        Text(task.result.finalStatus)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(statusColor(task.status.rawValue, theme: theme))
                            .lineLimit(2)
                    }
                    if !task.result.duration.isEmpty {
                        Text(task.result.duration)
                            .font(.system(size: 7))
                            .foregroundColor(theme.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Detail Sidebar

    private var detailSidebar: some View {
        let theme = ThemeManager.shared.current
        let selectedGroup = filteredGroups.first { $0.id == selectedRowID }

        return VStack(spacing: 0) {
            if let group = selectedGroup {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        detailHeader(group: group)
                        detailTagsRow(group: group)
                        detailStageSection(
                            stage: "transcript",
                            emoji: "",
                            name: "TRANSCRIPT",
                            color: theme.textSecondary,
                            group: group
                        )
                        detailStageSection(
                            stage: "cleaning",
                            emoji: "",
                            name: "CLEANING",
                            color: theme.tertiary,
                            group: group
                        )
                        detailStageSection(
                            stage: "analysis",
                            emoji: "",
                            name: "ANALYSIS",
                            color: theme.secondary,
                            group: group
                        )
                        detailStageSection(
                            stage: "task",
                            emoji: "",
                            name: "EXTRACTION",
                            color: theme.warning,
                            group: group
                        )
                        detailStageSection(
                            stage: "result",
                            emoji: "",
                            name: "RESULT",
                            color: theme.accent,
                            group: group
                        )
                    }
                    .padding(14)
                }
            } else {
                Spacer()
                Text("Select a row to inspect")
                    .font(.system(size: 10))
                    .foregroundColor(theme.textTertiary)
                Spacer()
            }
        }
        .frame(maxHeight: .infinity)
        .background(theme.isDark ? Color.black.opacity(0.12) : Color.black.opacity(0.02))
        .overlay(
            Rectangle()
                .fill(theme.glassBorder)
                .frame(width: 0.5),
            alignment: .leading
        )
    }

    // MARK: - Detail Header

    private func detailHeader(group: PipelineGroup) -> some View {
        let theme = ThemeManager.shared.current
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.id)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.textPrimary)
                Text(group.time)
                    .font(.system(size: 9))
                    .foregroundColor(theme.textTertiary)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedRowID = nil
                    expandedStage = nil
                }
            } label: {
                Text("\u{00D7}")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(theme.glass)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(theme.glassBorder, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Detail Tags Row

    private func detailTagsRow(group: PipelineGroup) -> some View {
        HStack(spacing: 4) {
            if let person = group.personTag {
                TagView(type: .person, label: person, small: true)
            }
            if let proj = group.analysisProject {
                TagView(type: .project, label: proj, small: true)
            }
            ForEach(group.analysisTags.prefix(3), id: \.self) { tag in
                TagView(type: .action, label: tag, small: true)
            }
        }
    }

    // MARK: - Detail Stage Section

    private func detailStageSection(
        stage: String,
        emoji: String,
        name: String,
        color: Color,
        group: PipelineGroup
    ) -> some View {
        let theme = ThemeManager.shared.current
        let isExpanded = expandedStage == stage

        return VStack(alignment: .leading, spacing: 0) {
            // Clickable header
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedStage = expandedStage == stage ? nil : stage
                }
            } label: {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(1)
                        .foregroundColor(color)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundColor(color.opacity(0.6))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isExpanded ? color.opacity(0.04) : theme.glass.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isExpanded ? color.opacity(0.25) : theme.glassBorder,
                            lineWidth: 0.5
                        )
                )
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    switch stage {
                    case "transcript":
                        expandedTranscript(group: group)
                    case "cleaning":
                        expandedCleaning(group: group)
                    case "analysis":
                        expandedAnalysis(group: group)
                    case "task":
                        expandedTask(group: group)
                    case "result":
                        expandedResult(group: group)
                    default:
                        EmptyView()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }
        }
    }

    // MARK: - Expanded Transcript

    private func expandedTranscript(group: PipelineGroup) -> some View {
        let theme = ThemeManager.shared.current
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(group.rawChunks) { chunk in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(chunk.id)
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(theme.textTertiary)
                        if !chunk.duration.isEmpty {
                            Text(chunk.duration)
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundColor(theme.textTertiary)
                        }
                    }
                    Text(chunk.text)
                        .font(.system(size: 9))
                        .foregroundColor(theme.textPrimary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Expanded Cleaning

    private func expandedCleaning(group: PipelineGroup) -> some View {
        let theme = ThemeManager.shared.current
        return VStack(alignment: .leading, spacing: 6) {
            if !group.cleaningTags.isEmpty {
                HStack(spacing: 3) {
                    ForEach(group.cleaningTags, id: \.self) { tag in
                        TagView(type: .status, label: tag, small: true)
                    }
                }
            }
            if let cleaned = group.cleanedText {
                Text(cleaned)
                    .font(.system(size: 9))
                    .foregroundColor(theme.textPrimary)
                    .textSelection(.enabled)
            } else {
                Text("No accepted extractions from this chunk")
                    .font(.system(size: 9))
                    .foregroundColor(theme.textTertiary)
                    .italic()
            }
        }
    }

    // MARK: - Expanded Analysis

    private func expandedAnalysis(group: PipelineGroup) -> some View {
        let theme = ThemeManager.shared.current
        return VStack(alignment: .leading, spacing: 6) {
            if !group.analysisTags.isEmpty {
                HStack(spacing: 3) {
                    ForEach(group.analysisTags, id: \.self) { tag in
                        TagView(type: .action, label: tag, small: true)
                    }
                    if let proj = group.analysisProject {
                        TagView(type: .project, label: proj, small: true)
                    }
                }
            }
            if let text = group.analysisText {
                Text(text)
                    .font(.system(size: 9))
                    .foregroundColor(theme.textPrimary)
                    .textSelection(.enabled)
            } else {
                Text("No analysis generated")
                    .font(.system(size: 9))
                    .foregroundColor(theme.textTertiary)
                    .italic()
            }
        }
    }

    // MARK: - Expanded Task

    private func expandedTask(group: PipelineGroup) -> some View {
        let theme = ThemeManager.shared.current
        return VStack(alignment: .leading, spacing: 10) {
            if group.tasks.isEmpty {
                Text("No extraction items")
                    .font(.system(size: 9))
                    .foregroundColor(theme.textTertiary)
                    .italic()
            } else {
                ForEach(group.tasks) { task in
                    expandedTaskCard(task: task)
                }
            }
        }
    }

    private func expandedTaskCard(task: PipelineTask) -> some View {
        let theme = ThemeManager.shared.current
        let modeBadgeMode: ModeBadge.Mode = {
            switch task.mode {
            case .auto: return .auto
            case .ask:  return .ask
            case .user: return .user
            }
        }()

        // Find the real extraction item for bucket picker
        let extractionItem = appState.extractionItems.first(where: { $0.id.hasPrefix(task.id) })

        return VStack(alignment: .leading, spacing: 6) {
            // ID + project + mode
            HStack(spacing: 4) {
                Text(task.id)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(theme.textTertiary)
                TagView(type: .project, label: task.project, small: true)
                ModeBadge(mode: modeBadgeMode)
            }

            // Title (content)
            Text(task.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(theme.warning)
                .textSelection(.enabled)

            // Source phrase (prompt)
            Text(task.prompt)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(theme.textSecondary)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(theme.glass.opacity(0.5))
                )

            // Bucket picker
            if let item = extractionItem {
                HStack(spacing: 6) {
                    Text("Bucket:")
                        .font(.system(size: 8))
                        .foregroundColor(theme.textTertiary)
                    ForEach(ExtractionBucket.allCases, id: \.self) { bucket in
                        Button {
                            appState.setExtractionBucket(id: item.id, bucket: bucket)
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: bucket.icon)
                                    .font(.system(size: 7))
                                Text(bucket.displayName)
                                    .font(.system(size: 8))
                            }
                            .foregroundColor(item.bucket == bucket ? theme.accent : theme.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(item.bucket == bucket ? theme.accent.opacity(0.15) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Accept / Dismiss actions
            if let item = extractionItem {
                HStack(spacing: 6) {
                    Button {
                        appState.toggleExtraction(id: item.id)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: item.isAccepted ? "xmark" : "checkmark")
                                .font(.system(size: 8))
                            Text(item.isAccepted ? "Dismiss" : "Accept")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .foregroundColor(item.isAccepted ? theme.error : theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(item.isAccepted
                                      ? theme.error.opacity(0.12)
                                      : theme.accent.opacity(0.18))
                        )
                    }
                    .buttonStyle(.plain)

                    // Status indicator
                    HStack(spacing: 3) {
                        StatusDot(status: task.status.rawValue)
                        Text(item.effectiveState)
                            .font(.system(size: 8))
                            .foregroundColor(statusColor(item.effectiveState, theme: theme))
                    }

                    if item.applied {
                        TagView(type: .status, label: "Applied", small: true)
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.warning.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.warning.opacity(0.10), lineWidth: 0.5)
        )
    }

    // MARK: - Expanded Result

    private func expandedResult(group: PipelineGroup) -> some View {
        let theme = ThemeManager.shared.current
        return VStack(alignment: .leading, spacing: 8) {
            if group.tasks.isEmpty {
                Text("No results")
                    .font(.system(size: 9))
                    .foregroundColor(theme.textTertiary)
                    .italic()
            } else {
                ForEach(group.tasks) { task in
                    VStack(alignment: .leading, spacing: 6) {
                        // Status summary
                        HStack(spacing: 5) {
                            StatusDot(status: task.status.rawValue)
                            Text(task.result.finalStatus)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(statusColor(task.status.rawValue, theme: theme))
                            Spacer()
                            if !task.result.duration.isEmpty {
                                Text(task.result.duration)
                                    .font(.system(size: 7))
                                    .foregroundColor(theme.textTertiary)
                            }
                        }

                        // Step-by-step detail
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(task.result.steps.enumerated()), id: \.offset) { idx, step in
                                HStack(alignment: .top, spacing: 6) {
                                    Circle()
                                        .fill(theme.accent.opacity(0.60))
                                        .frame(width: 10, height: 10)
                                        .overlay(
                                            Text("\(idx + 1)")
                                                .font(.system(size: 6, weight: .bold))
                                                .foregroundColor(
                                                    theme.isDark ? Color.black : Color.white
                                                )
                                        )
                                    Text(step)
                                        .font(.system(size: 9))
                                        .foregroundColor(theme.textSecondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
