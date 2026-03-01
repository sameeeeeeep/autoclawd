import SwiftUI

// MARK: - View Mode

private enum PipelineViewMode: String, CaseIterable {
    case pipeline = "Pipeline"
    case rawLogs  = "Raw Logs"
}

// MARK: - Status Color Helper

private func statusColor(_ status: String) -> Color {
    switch status {
    case "completed", "accepted", "relevant":
        return .accentColor
    case "ongoing", "pending":
        return .orange
    case "pending_approval":
        return .orange
    case "needs_input":
        return .purple
    case "dismissed", "nonrelevant":
        return .red
    default:
        return Color(NSColor.tertiaryLabelColor)
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
    @State private var chatInput: String = ""
    @State private var showChatModal: Bool = false
    @State private var chatTaskID: String? = nil
    @State private var pendingAttachments: [Attachment] = []
    @State private var showFilePicker: Bool = false

    // Inline editing state
    @State private var editingAnalysisID: String? = nil
    @State private var editProject: String = ""
    @State private var editTags: String = ""
    @State private var editPriority: String = ""
    @State private var editSummary: String = ""
    @State private var editingTaskID: String? = nil
    @State private var editTaskTitle: String = ""
    @State private var editTaskPrompt: String = ""
    @State private var editTaskProject: String = ""

    // MARK: - Derived Data

    /// Build pipeline groups from pipeline v2 data, with legacy extraction fallback.
    private var pipelineGroups: [PipelineGroup] {
        let cleaned = appState.cleanedTranscripts
        let analyses = appState.transcriptAnalyses
        let tasks = appState.pipelineTasks

        // If pipeline v2 has data, use it
        if !cleaned.isEmpty {
            return buildPipelineV2Groups(cleaned: cleaned, analyses: analyses, tasks: tasks)
        }

        // Fallback: build from legacy extraction items
        return buildLegacyGroups()
    }

    /// Build groups from the new multi-stage pipeline data.
    private func buildPipelineV2Groups(
        cleaned: [CleanedTranscript],
        analyses: [TranscriptAnalysis],
        tasks: [PipelineTaskRecord]
    ) -> [PipelineGroup] {
        // Index analyses and tasks for fast lookup
        let analysisByCleanedID = Dictionary(grouping: analyses, by: \.cleanedTranscriptID)
        let tasksByAnalysisID = Dictionary(grouping: tasks, by: \.analysisID)
        let executionSteps = { (taskID: String) -> [TaskExecutionStep] in
            self.appState.pipelineStore.fetchSteps(taskID: taskID)
        }

        return cleaned.map { ct -> PipelineGroup in
            let timeStr = Self.timeFormatter.string(from: ct.timestamp)
            let timeSeconds = Calendar.current.component(.hour, from: ct.timestamp) * 3600
                + Calendar.current.component(.minute, from: ct.timestamp) * 60

            // Raw chunks from source transcript IDs
            let rawChunks: [RawChunk] = ct.sourceTranscriptIDs.enumerated().map { idx, tid in
                let tr = transcripts.first(where: { $0.id == tid })
                let label = tr?.sessionID.map { "\($0.prefix(6))" } ?? "t\(tid)"
                let dur = tr.map { $0.durationSeconds > 0 ? "\($0.durationSeconds)s" : "" } ?? ""
                let text = tr?.text ?? "(transcript \(tid))"
                return RawChunk(id: label, duration: dur, text: text)
            }

            // Cleaning tags
            var cleaningTags: [String] = []
            if ct.isContinued { cleaningTags.append("Continued transcript") }
            if ct.sourceChunkCount > 1 { cleaningTags.append("\(ct.sourceChunkCount) chunks merged") }
            if ct.sourceChunkCount == 1 { cleaningTags.append("Single chunk") }

            // Analysis
            let matchedAnalyses = analysisByCleanedID[ct.id] ?? []
            let analysis = matchedAnalyses.first

            let analysisTags = analysis?.tags ?? []
            let analysisProject = analysis?.projectName
            let analysisText = analysis?.summary
            let analysisID = analysis?.id
            let analysisPriority = analysis?.priority

            // Tasks
            let pipelineTasks: [PipelineTask] = matchedAnalyses.flatMap { a -> [PipelineTask] in
                let matched = tasksByAnalysisID[a.id] ?? []
                return matched.map { t -> PipelineTask in
                    let steps = executionSteps(t.id)
                    let resultSteps = steps.map { "\($0.description)" }
                    let finalStatus: String = {
                        switch t.status {
                        case .completed: return "Completed"
                        case .ongoing: return "In progress"
                        case .pending_approval: return "Pending approval"
                        case .needs_input: return t.pendingQuestion ?? "Needs input"
                        case .upcoming: return "Upcoming"
                        case .filtered: return "Dismissed"
                        }
                    }()

                    let skillName = t.skillID.flatMap { sid in
                        self.appState.skills.first(where: { $0.id == sid })?.name
                    }
                    let workflowName = t.workflowID.flatMap { wid in
                        WorkflowRegistry.shared.workflow(for: wid)?.name
                    }

                    return PipelineTask(
                        id: t.id,
                        title: t.title,
                        prompt: t.prompt,
                        project: t.projectName ?? analysisProject ?? "unknown",
                        mode: t.mode,
                        status: t.status,
                        skill: skillName ?? t.skillID,
                        workflow: workflowName,
                        workflowSteps: t.workflowSteps,
                        missingConnection: t.missingConnection,
                        pendingQuestion: t.pendingQuestion,
                        result: TaskResult(
                            steps: resultSteps.isEmpty ? ["Processing..."] : resultSteps,
                            finalStatus: finalStatus,
                            duration: formatDuration(from: t.createdAt, to: t.completedAt)
                        )
                    )
                }
            }

            return PipelineGroup(
                id: ct.id,
                rawChunks: rawChunks,
                cleaningTags: cleaningTags,
                cleanedText: ct.cleanedText,
                analysisTags: analysisTags,
                analysisProject: analysisProject,
                analysisText: analysisText,
                analysisID: analysisID,
                analysisPriority: analysisPriority,
                tasks: pipelineTasks,
                placeTag: nil,
                personTag: ct.speakerName,
                time: timeStr,
                timeSeconds: timeSeconds
            )
        }
    }

    /// Fallback: build from legacy extraction items.
    private func buildLegacyGroups() -> [PipelineGroup] {
        let items = appState.extractionItems
        guard !items.isEmpty else { return [] }

        let grouped = Dictionary(grouping: items, by: \.chunkIndex)
        let sortedChunks = grouped.keys.sorted(by: >)

        return sortedChunks.compactMap { chunkIdx -> PipelineGroup? in
            guard let chunkItems = grouped[chunkIdx], !chunkItems.isEmpty else { return nil }
            let representative = chunkItems.first!
            let timeStr = Self.timeFormatter.string(from: representative.timestamp)
            let timeSeconds = Calendar.current.component(.hour, from: representative.timestamp) * 3600
                + Calendar.current.component(.minute, from: representative.timestamp) * 60

            let matchingTranscripts = transcripts.filter { tr in
                abs(tr.timestamp.timeIntervalSince(representative.timestamp)) < 60
            }

            let rawChunks: [RawChunk] = matchingTranscripts.isEmpty
                ? [RawChunk(id: "chunk-\(chunkIdx)", duration: "", text: representative.sourcePhrase)]
                : matchingTranscripts.map { tr in
                    let label = tr.sessionID.map { "\($0.prefix(6))" } ?? "t\(tr.id)"
                    let dur = tr.durationSeconds > 0 ? "\(tr.durationSeconds)s" : ""
                    return RawChunk(id: label, duration: dur, text: tr.text)
                }

            var cleaningTags: [String] = []
            if rawChunks.count > 1 { cleaningTags.append("\(rawChunks.count) chunks merged") }
            let dismissed = chunkItems.filter { $0.isDismissed }
            if !dismissed.isEmpty { cleaningTags.append("\(dismissed.count) filtered") }
            let accepted = chunkItems.filter { $0.isAccepted }
            if !accepted.isEmpty { cleaningTags.append("\(accepted.count) accepted") }

            let acceptedItems = chunkItems.filter { $0.isAccepted }
            let cleanedText = acceptedItems.isEmpty ? nil : acceptedItems.map(\.content).joined(separator: " ")

            var analysisTags: [String] = []
            for t in Set(chunkItems.map(\.type)) { analysisTags.append(t.rawValue) }
            for b in Set(chunkItems.map(\.bucket)) { analysisTags.append(b.displayName) }

            let analysisProject: String? = {
                if let pid = matchingTranscripts.first(where: { $0.projectID != nil })?.projectID {
                    return appState.projects.first(where: { $0.id == pid.uuidString })?.name
                }
                return nil
            }()

            let analysisText = acceptedItems.isEmpty
                ? nil
                : "\(acceptedItems.count) extraction(s): " + acceptedItems.map(\.content).prefix(2).joined(separator: "; ")

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

                var resultSteps: [String] = []
                resultSteps.append("Source: \"\(String(item.sourcePhrase.prefix(60)))\"")
                resultSteps.append("Type: \(item.type.rawValue), Bucket: \(item.bucket.displayName)")
                if let priority = item.priority { resultSteps.append("Priority: \(priority)") }
                resultSteps.append("Model decision: \(item.modelDecision)")
                if let override = item.userOverride { resultSteps.append("User override: \(override)") }
                if item.applied { resultSteps.append("Applied to world model/todos") }

                return PipelineTask(
                    id: String(item.id.prefix(10)),
                    title: item.content,
                    prompt: item.sourcePhrase,
                    project: analysisProject ?? item.bucket.displayName,
                    mode: item.userOverride != nil ? .user : .auto,
                    status: taskStatus,
                    skill: nil, workflow: nil, workflowSteps: [],
                    missingConnection: nil, pendingQuestion: nil,
                    result: TaskResult(steps: resultSteps, finalStatus: item.effectiveState, duration: item.priorityLabel)
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
                analysisID: nil,
                analysisPriority: nil,
                tasks: tasks,
                placeTag: nil,
                personTag: matchingTranscripts.first?.speakerName,
                time: timeStr,
                timeSeconds: timeSeconds
            )
        }
    }

    private func formatDuration(from start: Date, to end: Date?) -> String {
        guard let end else { return "" }
        let seconds = Int(end.timeIntervalSince(start))
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    private func modeBadgeMode(_ mode: TaskMode) -> ModeBadge.Mode {
        switch mode {
        case .auto: return .auto
        case .ask: return .ask
        case .user: return .user
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
        GeometryReader { geo in
            let showDetailInline = geo.size.width >= 700

            VStack(spacing: 0) {
                filterBar
                ZStack(alignment: .trailing) {
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

                        if selectedRowID != nil, viewMode == .pipeline, showDetailInline {
                            detailSidebar
                                .frame(minWidth: 200, idealWidth: 280, maxWidth: 340)
                                .transition(.move(edge: .trailing))
                        }
                    }

                    // Overlay detail sidebar on narrow windows
                    if selectedRowID != nil, viewMode == .pipeline, !showDetailInline {
                        ZStack(alignment: .trailing) {
                            Color.black.opacity(0.3)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedRowID = nil
                                    }
                                }

                            detailSidebar
                                .frame(width: min(320, geo.size.width * 0.8))
                                .background(Color(NSColor.controlBackgroundColor))
                                .shadow(color: .black.opacity(0.2), radius: 12)
                                .transition(.move(edge: .trailing))
                        }
                    }
                }
            }
        }
        .background(Color.black.opacity(0.03))
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
        appState.refreshPipeline()
        transcripts = appState.recentTranscripts()
        logEntries = AutoClawdLogger.shared.snapshot(limit: 500).reversed()
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row — wraps extraction actions below on narrow windows
            HStack(spacing: 8) {
                Text("Pipeline Logs")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .layoutPriority(1)

                // View mode picker
                Picker("", selection: $viewMode) {
                    ForEach(PipelineViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 120, maxWidth: 160)

                if viewMode == .pipeline {
                    TagView(type: .status, label: "\(filteredGroups.count) groups", small: true)
                } else {
                    TagView(type: .status, label: "\(logEntries.count) entries", small: true)
                }

                Spacer(minLength: 4)

                // Pipeline status
                if viewMode == .pipeline {
                    pipelineStatusBar
                }
            }

            // Filter row (only for pipeline mode) — scrollable so it works on narrow windows
            if viewMode == .pipeline {
                ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("Filter:")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        .padding(.trailing, 2)

                    // Project filters (from real projects)
                    ForEach(appState.projects, id: \.id) { project in
                        filterChip(
                            label: project.name,
                            isActive: filterProject == project.name,
                            activeColor: .blue
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
                            activeColor: .orange
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
                            activeColor: statusColor(state)
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
                                .foregroundColor(.red)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.red.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                }
                } // end ScrollView
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .overlay(
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Pipeline Status Bar

    private var pipelineStatusBar: some View {
        let pendingTasks = appState.pipelineTasks.filter {
            $0.status == .pending_approval || $0.status == .needs_input
        }.count
        let activeTasks = appState.pipelineTasks.filter { $0.status == .ongoing }.count

        return HStack(spacing: 8) {
            if appState.isListening {
                LiveBadge()
            }
            if activeTasks > 0 {
                HStack(spacing: 3) {
                    StatusDot(status: "ongoing")
                    Text("\(activeTasks) running")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                }
            }
            if pendingTasks > 0 {
                HStack(spacing: 3) {
                    StatusDot(status: "pending_approval")
                    Text("\(pendingTasks) awaiting")
                        .font(.system(size: 9))
                        .foregroundColor(.purple)
                }
            }
            if activeTasks == 0 && pendingTasks == 0 && !appState.pipelineTasks.isEmpty {
                Text("All clear")
                    .font(.system(size: 9))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
            }
        }
    }

    private var filterSeparator: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
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
                .foregroundColor(isActive ? activeColor : Color(NSColor.tertiaryLabelColor))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isActive ? activeColor.opacity(0.18) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            isActive ? activeColor.opacity(0.50) : Color(NSColor.separatorColor),
                            lineWidth: 0.5
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pipeline Content

    private var pipelineContent: some View {
        VStack(spacing: 0) {
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
        .background(Color.clear)
    }

    private var emptyPipelineState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "waveform.path")
                .font(.system(size: 32))
                .foregroundColor(Color(NSColor.separatorColor))
            Text("No pipeline data yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            Text("Start listening to see transcripts flow through the pipeline.")
                .font(.system(size: 10))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
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
        Group {
            if logEntries.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundColor(Color(NSColor.separatorColor))
                    Text("No logs yet.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
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
        GeometryReader { geo in
            let isCompact = geo.size.width < 400

            HStack(alignment: .top, spacing: isCompact ? 4 : 6) {
                Text(Self.logTimeFormatter.string(from: entry.timestamp))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .frame(minWidth: 48, alignment: .leading)
                    .layoutPriority(-1)

                Text(entry.level.rawValue)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(logLevelColor(entry.level))
                    .frame(minWidth: 28, alignment: .leading)
                    .layoutPriority(-1)

                if !isCompact {
                    Text("[\(entry.component.rawValue)]")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 50, alignment: .leading)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }

                Text(entry.message)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
        }
        .frame(minHeight: 20)
        .background(
            entry.level == .error
                ? Color.red.opacity(0.06)
                : entry.level == .warn
                    ? Color.orange.opacity(0.04)
                    : Color.clear
        )
    }

    private func logLevelColor(_ level: LogLevel) -> Color {
        switch level {
        case .error: return .red
        case .warn:  return .orange
        case .info:  return .secondary
        case .debug: return Color(NSColor.tertiaryLabelColor)
        }
    }

    private static let logTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: - Column Header Row

    private var columnHeaderRow: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let compact = w < 550

            HStack(spacing: 0) {
                if !compact {
                    columnHeader("TIME", color: Color(NSColor.tertiaryLabelColor))
                        .frame(width: 56, alignment: .leading)
                }
                columnHeader("TRANSCRIPT", color: .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                columnHeader(compact ? "CLEAN" : "CLEANING", color: .cyan)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !compact {
                    columnHeader("ANALYSIS", color: .purple)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                columnHeader("TASK", color: .orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                columnHeader("RESULT", color: .accentColor)
                    .frame(width: compact ? 60 : 90, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .frame(height: 28)
            .overlay(
                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(height: 0.5),
                alignment: .bottom
            )
        }
        .frame(height: 28)
    }

    private func columnHeader(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold))
            .tracking(1)
            .foregroundColor(color)
    }

    // MARK: - Pipeline Row

    private func pipelineRow(group: PipelineGroup) -> some View {
        let isSelected = selectedRowID == group.id

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedRowID = selectedRowID == group.id ? nil : group.id
                expandedStage = nil
            }
        } label: {
            GeometryReader { geo in
                let compact = geo.size.width < 550

                HStack(spacing: 0) {
                    // Left accent border
                    Rectangle()
                        .fill(isSelected ? Color.accentColor : Color.clear)
                        .frame(width: 2)

                    HStack(alignment: .top, spacing: 0) {
                        if !compact {
                            timeColumn(group: group)
                                .frame(width: 56, alignment: .leading)
                        }

                        transcriptColumn(group: group)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        cleaningColumn(group: group)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if !compact {
                            analysisColumn(group: group)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        taskColumn(group: group)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        resultColumn(group: group)
                            .frame(width: compact ? 60 : 90, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .frame(width: geo.size.width)
                .background(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
                .overlay(
                    Rectangle()
                        .fill(Color(NSColor.separatorColor))
                        .frame(height: 0.5),
                    alignment: .bottom
                )
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Time Column

    private func timeColumn(group: PipelineGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.time)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
            if let firstChunk = group.rawChunks.first {
                Text(firstChunk.id.prefix(8))
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
            }
        }
    }

    // MARK: - Transcript Column

    private func transcriptColumn(group: PipelineGroup) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(group.rawChunks) { chunk in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(chunk.id)
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        if !chunk.duration.isEmpty {
                            Text(chunk.duration)
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        }
                    }
                    Text(String(chunk.text.prefix(55)))
                        .font(.system(size: 9))
                        .foregroundColor(Color.secondary.opacity(0.80))
                        .lineLimit(2)
                }
                .padding(4)
                .background(
                    group.rawChunks.count > 1
                        ? RoundedRectangle(cornerRadius: 4)
                            .fill(Color(NSColor.windowBackgroundColor).opacity(0.8).opacity(0.5))
                        : nil
                )
            }
        }
    }

    // MARK: - Cleaning Column

    private func cleaningColumn(group: PipelineGroup) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if !group.cleaningTags.isEmpty {
                // FlowLayout wraps tags to the next line when the column is narrow
                FlowLayout(spacing: 3) {
                    ForEach(group.cleaningTags, id: \.self) { tag in
                        TagView(type: .status, label: tag, small: true)
                    }
                }
            }
            if let cleaned = group.cleanedText {
                Text(String(cleaned.prefix(70)))
                    .font(.system(size: 9))
                    .foregroundColor(Color.cyan.opacity(0.80))
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Analysis Column

    private func analysisColumn(group: PipelineGroup) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if !group.analysisTags.isEmpty {
                FlowLayout(spacing: 3) {
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
                    .foregroundColor(Color.purple.opacity(0.80))
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Task Column

    private func taskColumn(group: PipelineGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if group.tasks.isEmpty {
                Text("\u{2014}")
                    .font(.system(size: 9))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
            } else {
                ForEach(group.tasks) { task in
                    taskMiniCard(task: task, groupID: group.id)
                }
            }
        }
    }

    private func taskMiniCard(task: PipelineTask, groupID: String) -> some View {
        let isPipelineTask = task.id.hasPrefix("T-")

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(task.id)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .fixedSize()
                ModeBadge(mode: modeBadgeMode(task.mode))
                    .fixedSize()
                ViewThatFits(in: .horizontal) {
                    // All tags
                    HStack(spacing: 4) {
                        if let skill = task.skill {
                            TagView(type: .action, label: skill, small: true)
                        }
                        if let wf = task.workflow {
                            TagView(type: .status, label: wf, small: true)
                        }
                    }
                    // Skill only (drop workflow when narrow)
                    HStack(spacing: 4) {
                        if let skill = task.skill {
                            TagView(type: .action, label: skill, small: true)
                        }
                    }
                    // Nothing (very narrow)
                    EmptyView()
                }
            }
            Text(String(task.title.prefix(50)))
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.orange)
                .lineLimit(2)

            // Run button for stuck ongoing tasks
            if isPipelineTask && task.status == .ongoing && task.result.steps == ["Processing..."] {
                Button {
                    appState.executeTask(id: task.id)
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 7))
                        Text("Run")
                            .font(.system(size: 8))
                    }
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.accentColor.opacity(0.18))
                    )
                }
                .buttonStyle(.plain)
            }

            // Accept / Dismiss for pending tasks
            if task.status == .pending_approval || task.status == .needs_input {
                HStack(spacing: 4) {
                    Button {
                        if isPipelineTask {
                            appState.acceptTask(id: task.id)
                        } else if let eid = appState.extractionItems.first(where: { $0.id.hasPrefix(task.id) })?.id {
                            appState.toggleExtraction(id: eid)
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 7))
                            Text("Accept")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.accentColor.opacity(0.18))
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        if isPipelineTask {
                            appState.dismissTask(id: task.id)
                        } else if let eid = appState.extractionItems.first(where: { $0.id.hasPrefix(task.id) })?.id {
                            appState.toggleExtraction(id: eid)
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "xmark")
                                .font(.system(size: 7))
                            Text("Dismiss")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.red.opacity(0.12))
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
                      ? Color(NSColor.tertiaryLabelColor).opacity(0.04)
                      : Color.orange.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(task.status == .filtered
                        ? Color(NSColor.tertiaryLabelColor).opacity(0.08)
                        : Color.orange.opacity(0.12),
                        lineWidth: 0.5)
        )
    }

    // MARK: - Result Column

    private func resultColumn(group: PipelineGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if group.tasks.isEmpty {
                Text("\u{2014}")
                    .font(.system(size: 9))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
            } else {
                ForEach(group.tasks) { task in
                    HStack(spacing: 4) {
                        StatusDot(status: task.status.rawValue)
                        Text(task.result.finalStatus)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(statusColor(task.status.rawValue))
                            .lineLimit(2)
                    }
                    if !task.result.duration.isEmpty {
                        Text(task.result.duration)
                            .font(.system(size: 7))
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    }
                }
            }
        }
    }

    // MARK: - Detail Sidebar

    private var detailSidebar: some View {
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
                            color: .secondary,
                            group: group
                        )
                        detailStageSection(
                            stage: "cleaning",
                            emoji: "",
                            name: "CLEANING",
                            color: .cyan,
                            group: group
                        )
                        detailStageSection(
                            stage: "analysis",
                            emoji: "",
                            name: "ANALYSIS",
                            color: .purple,
                            group: group
                        )
                        detailStageSection(
                            stage: "task",
                            emoji: "",
                            name: "TASKS",
                            color: .orange,
                            group: group
                        )
                        detailStageSection(
                            stage: "result",
                            emoji: "",
                            name: "RESULT",
                            color: .accentColor,
                            group: group
                        )
                    }
                    .padding(14)
                }
            } else {
                Spacer()
                Text("Select a row to inspect")
                    .font(.system(size: 10))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                Spacer()
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.04))
        .overlay(
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(width: 0.5),
            alignment: .leading
        )
    }

    // MARK: - Detail Header

    private func detailHeader(group: PipelineGroup) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.id)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                Text(group.time)
                    .font(.system(size: 9))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
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
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(NSColor.windowBackgroundColor).opacity(0.8))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
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
                        .fill(isExpanded ? color.opacity(0.04) : Color(NSColor.windowBackgroundColor).opacity(0.8).opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isExpanded ? color.opacity(0.25) : Color(NSColor.separatorColor),
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
        VStack(alignment: .leading, spacing: 8) {
            ForEach(group.rawChunks) { chunk in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(chunk.id)
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        if !chunk.duration.isEmpty {
                            Text(chunk.duration)
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        }
                    }
                    Text(chunk.text)
                        .font(.system(size: 9))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Expanded Cleaning

    private func expandedCleaning(group: PipelineGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            } else {
                Text("No accepted extractions from this chunk")
                    .font(.system(size: 9))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .italic()
            }
        }
    }

    // MARK: - Expanded Analysis

    private func expandedAnalysis(group: PipelineGroup) -> some View {
        let isEditing = editingAnalysisID == group.analysisID && group.analysisID != nil
        return VStack(alignment: .leading, spacing: 6) {
            if isEditing {
                // Editable mode
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Project").font(.system(size: 7, weight: .medium)).foregroundColor(Color(NSColor.tertiaryLabelColor))
                        Picker("", selection: $editProject) {
                            Text("none").tag("")
                            ForEach(appState.projects, id: \.id) { p in
                                Text(p.name).tag(p.name)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                    HStack(spacing: 4) {
                        Text("Priority").font(.system(size: 7, weight: .medium)).foregroundColor(Color(NSColor.tertiaryLabelColor))
                        Picker("", selection: $editPriority) {
                            Text("none").tag("")
                            Text("p0").tag("p0")
                            Text("p1").tag("p1")
                            Text("p2").tag("p2")
                            Text("p3").tag("p3")
                        }
                        .labelsHidden()
                        .frame(width: 70)
                    }
                    HStack(spacing: 4) {
                        Text("Tags").font(.system(size: 7, weight: .medium)).foregroundColor(Color(NSColor.tertiaryLabelColor))
                        TextField("comma-separated", text: $editTags)
                            .textFieldStyle(.plain)
                            .font(.system(size: 9))
                            .foregroundColor(.primary)
                            .padding(3)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color(NSColor.windowBackgroundColor).opacity(0.8).opacity(0.5)))
                    }
                    HStack(spacing: 4) {
                        Text("Summary").font(.system(size: 7, weight: .medium)).foregroundColor(Color(NSColor.tertiaryLabelColor))
                    }
                    TextField("Summary", text: $editSummary)
                        .textFieldStyle(.plain)
                        .font(.system(size: 9))
                        .foregroundColor(.primary)
                        .padding(3)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color(NSColor.windowBackgroundColor).opacity(0.8).opacity(0.5)))
                    HStack(spacing: 6) {
                        Button("Save") {
                            if let aid = group.analysisID {
                                let proj = editProject.isEmpty ? nil : editProject
                                let projID = appState.projects.first(where: { $0.name == editProject })?.id
                                let pri = editPriority.isEmpty ? nil : editPriority
                                let tags = editTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                                appState.updateAnalysis(id: aid, projectName: proj, projectID: projID, priority: pri, tags: tags, summary: editSummary)
                            }
                            editingAnalysisID = nil
                        }
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .buttonStyle(.plain)

                        Button("Cancel") { editingAnalysisID = nil }
                        .font(.system(size: 8))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        .buttonStyle(.plain)
                    }
                }
            } else {
                // Read-only mode with edit button
                HStack(spacing: 3) {
                    if let pri = group.analysisPriority {
                        TagView(type: .status, label: pri, small: true)
                    }
                    ForEach(group.analysisTags, id: \.self) { tag in
                        TagView(type: .action, label: tag, small: true)
                    }
                    if let proj = group.analysisProject {
                        TagView(type: .project, label: proj, small: true)
                    }
                    if group.analysisID != nil {
                        Spacer()
                        Button {
                            editProject = group.analysisProject ?? ""
                            editPriority = group.analysisPriority ?? ""
                            editTags = group.analysisTags.joined(separator: ", ")
                            editSummary = group.analysisText ?? ""
                            editingAnalysisID = group.analysisID
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 8))
                                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let text = group.analysisText {
                    Text(text)
                        .font(.system(size: 9))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                } else {
                    Text("No analysis generated")
                        .font(.system(size: 9))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        .italic()
                }
            }
        }
    }

    // MARK: - Expanded Task

    private func expandedTask(group: PipelineGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if group.tasks.isEmpty {
                Text("No extraction items")
                    .font(.system(size: 9))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .italic()
            } else {
                ForEach(group.tasks) { task in
                    expandedTaskCard(task: task)
                }
            }
        }
    }

    private func expandedTaskCard(task: PipelineTask) -> some View {
        let isPipelineTask = task.id.hasPrefix("T-")
        let isEditing = editingTaskID == task.id && isPipelineTask

        return VStack(alignment: .leading, spacing: 6) {
            if isEditing {
                // Editable mode
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(task.id)
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        Picker("", selection: $editTaskProject) {
                            Text("none").tag("")
                            ForEach(appState.projects, id: \.id) { p in
                                Text(p.name).tag(p.name)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                    Text("Title").font(.system(size: 7, weight: .medium)).foregroundColor(Color(NSColor.tertiaryLabelColor))
                    TextField("Task title", text: $editTaskTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color(NSColor.windowBackgroundColor).opacity(0.8).opacity(0.5)))
                    Text("Prompt").font(.system(size: 7, weight: .medium)).foregroundColor(Color(NSColor.tertiaryLabelColor))
                    TextEditor(text: $editTaskPrompt)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 60, maxHeight: 120)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color(NSColor.windowBackgroundColor).opacity(0.8).opacity(0.5)))
                    HStack(spacing: 6) {
                        Button("Save") {
                            let proj = editTaskProject.isEmpty ? nil : editTaskProject
                            let projID = appState.projects.first(where: { $0.name == editTaskProject })?.id
                            appState.updateTaskDetails(id: task.id, title: editTaskTitle, prompt: editTaskPrompt, projectName: proj, projectID: projID)
                            editingTaskID = nil
                        }
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .buttonStyle(.plain)

                        Button("Cancel") { editingTaskID = nil }
                        .font(.system(size: 8))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        .buttonStyle(.plain)
                    }
                }
            } else {
                // Read-only mode
                // ID + project + mode + edit button
                HStack(spacing: 4) {
                    Text(task.id)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    TagView(type: .project, label: task.project, small: true)
                    ModeBadge(mode: modeBadgeMode(task.mode))
                    if isPipelineTask {
                        Spacer()
                        Button {
                            editTaskTitle = task.title
                            editTaskPrompt = task.prompt
                            editTaskProject = task.project
                            editingTaskID = task.id
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 8))
                                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Title
                Text(task.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.orange)
                    .textSelection(.enabled)

                // Prompt
                Text(task.prompt)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(NSColor.windowBackgroundColor).opacity(0.8).opacity(0.5))
                    )

                // Skill & workflow info
                if task.skill != nil || task.workflow != nil {
                    HStack(spacing: 4) {
                        if let skill = task.skill {
                            TagView(type: .action, label: "Skill: \(skill)", small: true)
                        }
                        if let wf = task.workflow {
                            TagView(type: .status, label: wf, small: true)
                        }
                    }
                }

                // Missing connection warning
                if let missing = task.missingConnection {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 8))
                            .foregroundColor(.orange)
                        Text("Missing: \(missing)")
                            .font(.system(size: 8))
                            .foregroundColor(.orange)
                    }
                }

                // Pending question
                if let question = task.pendingQuestion {
                    Text(question)
                        .font(.system(size: 9))
                        .foregroundColor(.purple)
                        .italic()
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.purple.opacity(0.08))
                        )
                }
            }

            // Accept / Dismiss actions
            HStack(spacing: 6) {
                if isPipelineTask {
                    if task.status == .pending_approval || task.status == .needs_input {
                        Button {
                            appState.acceptTask(id: task.id)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8))
                                Text("Accept")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.accentColor.opacity(0.18))
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            appState.dismissTask(id: task.id)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8))
                                Text("Dismiss")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.red.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } else if let item = appState.extractionItems.first(where: { $0.id.hasPrefix(task.id) }) {
                    Button {
                        appState.toggleExtraction(id: item.id)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: item.isAccepted ? "xmark" : "checkmark")
                                .font(.system(size: 8))
                            Text(item.isAccepted ? "Dismiss" : "Accept")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .foregroundColor(item.isAccepted ? .red : .accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(item.isAccepted ? Color.red.opacity(0.12) : Color.accentColor.opacity(0.18))
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Status indicator
                HStack(spacing: 3) {
                    StatusDot(status: task.status.rawValue)
                    Text(task.result.finalStatus)
                        .font(.system(size: 8))
                        .foregroundColor(statusColor(task.status.rawValue))
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.orange.opacity(0.10), lineWidth: 0.5)
        )
    }

    // MARK: - Expanded Result

    private func expandedResult(group: PipelineGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if group.tasks.isEmpty {
                Text("No results")
                    .font(.system(size: 9))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .italic()
            } else {
                ForEach(group.tasks) { task in
                    VStack(alignment: .leading, spacing: 6) {
                        // Status summary + actions
                        HStack(spacing: 5) {
                            StatusDot(status: task.status.rawValue)
                            Text(task.result.finalStatus)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(statusColor(task.status.rawValue))
                            Spacer()
                            if !task.result.duration.isEmpty {
                                Text(task.result.duration)
                                    .font(.system(size: 7))
                                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                            }
                            // Chat button for active/completed sessions
                            if task.status == .ongoing || task.status == .completed {
                                Button {
                                    chatTaskID = task.id
                                    showChatModal = true
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "bubble.left.and.bubble.right.fill")
                                            .font(.system(size: 7))
                                        Text("Chat")
                                            .font(.system(size: 7, weight: .semibold))
                                    }
                                    .foregroundColor(.accentColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.accentColor.opacity(0.12))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Step-by-step detail (show last 8 steps + scrollable)
                        let steps = task.result.steps
                        let displaySteps = steps.count > 8 ? Array(steps.suffix(8)) : steps
                        let offset = steps.count > 8 ? steps.count - 8 : 0

                        VStack(alignment: .leading, spacing: 4) {
                            if steps.count > 8 {
                                Text("\(steps.count - 8) earlier steps hidden")
                                    .font(.system(size: 7))
                                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                                    .italic()
                            }
                            ForEach(Array(displaySteps.enumerated()), id: \.offset) { idx, step in
                                HStack(alignment: .top, spacing: 6) {
                                    let stepNum = offset + idx + 1
                                    Circle()
                                        .fill(stepColor(step: step))
                                        .frame(width: 10, height: 10)
                                        .overlay(
                                            Text("\(stepNum)")
                                                .font(.system(size: 6, weight: .bold))
                                                .foregroundColor(Color.white)
                                        )
                                    Text(step)
                                        .font(.system(size: 9))
                                        .foregroundColor(stepTextColor(step: step))
                                        .textSelection(.enabled)
                                        .lineLimit(3)
                                }
                            }
                        }

                        // Inline chat input for active sessions
                        if task.status == .ongoing && appState.taskHasActiveSession(id: task.id) {
                            VStack(spacing: 3) {
                                // Pending attachment chips
                                if !pendingAttachments.isEmpty {
                                    attachmentChips(compact: true)
                                }
                                HStack(spacing: 4) {
                                    // Attachment buttons
                                    attachmentMenu(compact: true)

                                    TextField("Reply to Claude...", text: $chatInput)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 9))
                                        .foregroundColor(.primary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color(NSColor.windowBackgroundColor).opacity(0.8).opacity(0.5))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                                        )
                                        .onSubmit {
                                            sendChatMessage(taskID: task.id)
                                        }
                                    Button {
                                        sendChatMessage(taskID: task.id)
                                    } label: {
                                        Image(systemName: "arrow.up.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(chatInput.isEmpty && pendingAttachments.isEmpty ? Color(NSColor.tertiaryLabelColor) : .accentColor)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(chatInput.isEmpty && pendingAttachments.isEmpty)
                                }
                            }
                            .padding(.top, 4)
                        }

                        // Follow-on actions for completed tasks
                        if task.status == .completed {
                            followOnActions(task: task, group: group)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showChatModal) {
            if let taskID = chatTaskID {
                chatModalView(taskID: taskID)
            }
        }
    }

    // MARK: - Follow-On Actions

    @ViewBuilder
    private func followOnActions(task: PipelineTask, group: PipelineGroup) -> some View {
        HStack(spacing: 6) {
            // "Update Build & Relaunch" — only for autoclawd project
            if isAutoClawdTask(task: task) {
                actionButton(
                    icon: "hammer.fill",
                    label: "Rebuild & Relaunch",
                    color: .accentColor
                ) {
                    triggerSelfRebuild(task: task)
                }
            }

            // "Raise PR"
            actionButton(
                icon: "arrow.triangle.branch",
                label: "Raise PR",
                color: .purple
            ) {
                triggerRaisePR(task: task)
            }

            // "Commit Changes"
            actionButton(
                icon: "checkmark.circle.fill",
                label: "Commit",
                color: .orange
            ) {
                triggerCommit(task: task)
            }
        }
        .padding(.top, 6)
    }

    private func actionButton(
        icon: String, label: String, color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 7))
                Text(label)
                    .font(.system(size: 7, weight: .semibold))
            }
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(color.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(color.opacity(0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func isAutoClawdTask(task: PipelineTask) -> Bool {
        task.project.lowercased().contains("autoclawd") || task.project.lowercased().contains("auto clawd")
    }

    private func triggerSelfRebuild(task: PipelineTask) {
        // Find the autoclawd project path
        guard let project = appState.projects.first(where: {
            $0.name.lowercased().contains("autoclawd") || $0.name.lowercased().contains("auto clawd")
        }) else {
            Log.warn(.pipeline, "Self-rebuild: could not find AutoClawd project")
            return
        }
        TaskExecutionService.openRebuildTerminal(projectPath: project.localPath, taskID: task.id)
    }

    private func triggerRaisePR(task: PipelineTask) {
        // Send follow-up to Claude to create a PR
        let message = "Create a pull request for the changes you just made. Use a descriptive title and summary."
        appState.sendMessageToTask(id: task.id, message: message)
    }

    private func triggerCommit(task: PipelineTask) {
        // Send follow-up to Claude to commit changes
        let message = "Commit all the changes you just made with a clear, descriptive commit message."
        appState.sendMessageToTask(id: task.id, message: message)
    }

    // MARK: - Step Color Helpers

    private func stepColor(step: String) -> Color {
        if step.hasPrefix("Using ") { return Color.orange.opacity(0.70) }
        if step.hasPrefix("Running ") { return Color.orange.opacity(0.70) }
        if step.hasPrefix("Error:") || step.contains("failed") { return Color.red.opacity(0.70) }
        if step.hasPrefix("You:") { return Color.purple.opacity(0.70) }
        if step.contains("completed successfully") { return .accentColor }
        if step.contains("thinking") || step.contains("responding") { return Color.cyan.opacity(0.70) }
        return Color.accentColor.opacity(0.60)
    }

    private func stepTextColor(step: String) -> Color {
        if step.hasPrefix("Using ") || step.hasPrefix("Running ") { return .orange }
        if step.hasPrefix("Error:") || step.contains("failed") { return .red }
        if step.hasPrefix("You:") { return .purple }
        if step.contains("thinking") || step.contains("responding") { return .cyan }
        return .secondary
    }

    // MARK: - Chat Helpers

    private func sendChatMessage(taskID: String) {
        let msg = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty || !pendingAttachments.isEmpty else { return }
        appState.sendMessageToTask(id: taskID, message: msg, attachments: pendingAttachments)
        chatInput = ""
        pendingAttachments = []
    }

    // MARK: - Chat Modal

    private func chatModalView(taskID: String) -> some View {
        let steps = appState.pipelineStore.fetchSteps(taskID: taskID)
        let task = appState.pipelineTasks.first { $0.id == taskID }
        let isActive = appState.taskHasActiveSession(id: taskID)

        return VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task?.title ?? taskID)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    HStack(spacing: 6) {
                        StatusDot(status: task?.status.rawValue ?? "ongoing")
                        Text(task?.status.rawValue ?? "ongoing")
                            .font(.system(size: 9))
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        if isActive {
                            Text("Session active")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.accentColor.opacity(0.15))
                                )
                        }
                    }
                }
                Spacer()
                if isActive {
                    Button {
                        appState.stopTaskSession(id: taskID)
                    } label: {
                        Text("Stop")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.red.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                }
                Button { showChatModal = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8).opacity(0.5))

            Divider().background(Color(NSColor.separatorColor))

            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(steps.sorted(by: { $0.stepIndex < $1.stepIndex })) { step in
                            chatBubble(step: step)
                                .id(step.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: steps.count) { _ in
                    if let last = steps.sorted(by: { $0.stepIndex < $1.stepIndex }).last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            // Input area
            if isActive {
                Divider().background(Color(NSColor.separatorColor))
                VStack(spacing: 6) {
                    // Pending attachment chips
                    if !pendingAttachments.isEmpty {
                        attachmentChips(compact: false)
                            .padding(.horizontal, 14)
                            .padding(.top, 6)
                    }
                    HStack(spacing: 8) {
                        // Attachment buttons
                        attachmentMenu(compact: false)

                        TextField("Send a message to Claude...", text: $chatInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(.primary)
                            .onSubmit { sendChatMessage(taskID: taskID) }
                        Button {
                            sendChatMessage(taskID: taskID)
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(chatInput.isEmpty && pendingAttachments.isEmpty ? Color(NSColor.tertiaryLabelColor) : .accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(chatInput.isEmpty && pendingAttachments.isEmpty)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .background(Color(NSColor.windowBackgroundColor).opacity(0.8).opacity(0.3))
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func chatBubble(step: TaskExecutionStep) -> some View {
        let isUser = step.description.hasPrefix("You:")
        let isTool = step.description.hasPrefix("Using ")
        let isToolDone = step.description.contains(" done")
        let isError = step.description.hasPrefix("Error:") || step.status == "failed"
        let isResult = step.description.contains("completed successfully")

        let bgColor: Color = {
            if isUser { return Color.purple.opacity(0.12) }
            if isTool { return Color.orange.opacity(0.08) }
            if isError { return Color.red.opacity(0.08) }
            if isResult { return Color.accentColor.opacity(0.12) }
            return Color(NSColor.windowBackgroundColor).opacity(0.8).opacity(0.4)
        }()

        let textColor: Color = {
            if isUser { return .purple }
            if isTool { return .orange }
            if isError { return .red }
            return .primary
        }()

        return HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
                if isTool || isToolDone {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.fill")
                            .font(.system(size: 7))
                            .foregroundColor(Color.orange.opacity(0.6))
                        Text(step.description)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(textColor)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(bgColor))
                } else {
                    let displayText = isUser ? String(step.description.dropFirst(4)).trimmingCharacters(in: .whitespaces) : step.description
                    let hasAttachment = isUser && displayText.contains("[") && displayText.hasSuffix("]")
                    VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
                        // Show attachment indicator if present
                        if hasAttachment, let bracketRange = displayText.range(of: " [", options: .backwards) {
                            let textPart = String(displayText[displayText.startIndex..<bracketRange.lowerBound])
                            let attachPart = String(displayText[bracketRange.upperBound..<displayText.index(before: displayText.endIndex)])
                            if !textPart.isEmpty {
                                Text(textPart)
                                    .font(.system(size: 10))
                                    .foregroundColor(textColor)
                                    .textSelection(.enabled)
                            }
                            HStack(spacing: 3) {
                                Image(systemName: "paperclip")
                                    .font(.system(size: 7))
                                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                                Text(attachPart)
                                    .font(.system(size: 8))
                                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                                    .lineLimit(1)
                            }
                        } else {
                            Text(displayText)
                                .font(.system(size: 10))
                                .foregroundColor(textColor)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(bgColor))
                }
            }
            if !isUser { Spacer(minLength: 40) }
        }
    }

    // MARK: - Attachment UI Components

    /// Menu button with screenshot, file, and paste options.
    @ViewBuilder
    private func attachmentMenu(compact: Bool) -> some View {
        let iconSize: CGFloat = compact ? 12 : 14

        Menu {
            Button {
                captureScreenshot()
            } label: {
                Label("Take Screenshot", systemImage: "camera.viewfinder")
            }

            Button {
                showFilePicker = true
            } label: {
                Label("Attach File...", systemImage: "doc.badge.plus")
            }

            if NSPasteboard.general.data(forType: .png) != nil ||
               NSPasteboard.general.data(forType: .tiff) != nil {
                Button {
                    pasteImage()
                } label: {
                    Label("Paste Image", systemImage: "doc.on.clipboard")
                }
            }
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: iconSize))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: iconSize + 4, height: iconSize + 4)
        .help("Attach image, screenshot, or file")
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: Attachment.supportedUTTypes,
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
    }

    /// Display pending attachment chips with remove buttons.
    @ViewBuilder
    private func attachmentChips(compact: Bool) -> some View {
        let chipFont: CGFloat = compact ? 8 : 9
        let thumbSize: CGFloat = compact ? 20 : 28

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(pendingAttachments) { attachment in
                    HStack(spacing: 3) {
                        // Thumbnail or icon
                        if let thumb = attachment.thumbnail {
                            Image(nsImage: thumb)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: thumbSize, height: thumbSize)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        } else {
                            Image(systemName: attachment.iconName)
                                .font(.system(size: chipFont + 1))
                                .foregroundColor(.accentColor)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(attachment.fileName)
                                .font(.system(size: chipFont))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(attachment.sizeLabel)
                                .font(.system(size: chipFont - 1))
                                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        }
                        Button {
                            pendingAttachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: chipFont + 2))
                                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor.opacity(0.2), lineWidth: 0.5))
                }
            }
        }
    }

    // MARK: - Attachment Actions

    private func captureScreenshot() {
        guard let image = ScreenshotService.captureAndResize(maxDimension: 1920) else {
            Log.warn(.system, "Failed to capture screenshot")
            return
        }
        if let attachment = Attachment.fromScreenshot(image) {
            pendingAttachments.append(attachment)
        }
    }

    private func pasteImage() {
        if let attachment = Attachment.fromPasteboardImage() {
            pendingAttachments.append(attachment)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                if let attachment = Attachment.fromFile(url: url) {
                    pendingAttachments.append(attachment)
                }
            }
        case .failure(let error):
            Log.warn(.system, "File import failed: \(error.localizedDescription)")
        }
    }
}
