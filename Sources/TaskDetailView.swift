import SwiftUI

// MARK: - TaskDetailView
//
// Full detail panel for a task. Shown as a .sheet from TasksView.
//
// For .learnSession source: embeds AICanvasView (the FUCBC event canvas).
// For .capability and .pipelineTask: shows the Cofia-style WorkflowCanvasView,
// a Run button, streaming output, and run history.

struct TaskDetailView: View {

    let record: TaskRecord
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var runHistory: [TaskExecutionStep] = []
    @State private var showSchedulePicker = false
    @State private var pendingInput: String = ""
    @State private var isRunning: Bool = false

    var body: some View {
        ZStack {
            AppTheme.glassAmbientBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                detailHeader
                GlassDivider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Learn Session → embed FUCBC canvas
                        if case .learnSession = record.source {
                            learnSessionContent
                        } else {
                            standardContent
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .onAppear { loadRunHistory() }
        .onChange(of: appState.codeTaskID) { _ in checkRunning() }
        .onChange(of: appState.codeIsStreaming) { _ in checkRunning() }
        .sheet(isPresented: $showSchedulePicker) {
            SchedulePickerView(taskID: record.id, taskTitle: record.title)
        }
    }

    // MARK: - Header

    private var detailHeader: some View {
        HStack(spacing: 12) {
            Text(record.emoji)
                .font(.system(size: 24))
                .frame(width: 44, height: 44)
                .background(Glass.backgroundDark)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Glass.textPrimary)
                HStack(spacing: 8) {
                    if let proj = record.projectName {
                        GlassChip(proj, icon: "folder.fill")
                    }
                    if record.isRecurring, let expr = record.cronExpression {
                        GlassChip(CronEvaluator.humanReadable(expr), icon: "repeat")
                            .foregroundStyle(Color.purple.opacity(0.8))
                    }
                    statusBadge(record.status)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                // Schedule button
                if case .learnSession = record.source {} else {
                    GlassButton(
                        record.cronExpression != nil ? "Reschedule" : "Schedule",
                        icon: "calendar.badge.clock",
                        tint: .purple
                    ) {
                        showSchedulePicker = true
                    }
                }
                // Close
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Glass.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.2))
    }

    // MARK: - Learn Session Content

    private var learnSessionContent: some View {
        VStack(spacing: 0) {
            AICanvasView(learnService: appState.learnModeService)
                .frame(minHeight: 400)
        }
        .cornerRadius(Glass.radiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: Glass.radiusMedium)
                .stroke(Glass.borderGradient, lineWidth: 1)
        )
    }

    // MARK: - Standard Content (Capability / PipelineTask)

    private var standardContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Workflow Canvas
            if !record.nodes.isEmpty {
                workflowSection
            }

            // Description
            if !record.description.isEmpty {
                descriptionSection
            }

            // Input field (needs_input tasks)
            if record.status == .needsInput || record.pendingQuestion != nil {
                inputSection
            }

            // Run button + live output
            runSection

            // Run history
            if !runHistory.isEmpty {
                runHistorySection
            }
        }
    }

    // MARK: - Workflow Section

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Workflow", icon: "arrow.right.circle.fill")

            WorkflowCanvasView(
                nodes: nodesWithRunningStatus,
                isRecurring: record.isRecurring
            )
            .frame(height: 120)
            .background(Glass.backgroundDark)
            .cornerRadius(Glass.radiusMedium)
            .overlay(
                RoundedRectangle(cornerRadius: Glass.radiusMedium)
                    .stroke(Glass.borderGradient, lineWidth: 1)
            )
        }
    }

    /// Apply running status to first idle node when task is running.
    private var nodesWithRunningStatus: [WorkflowNodeViewModel] {
        guard isRunning else { return record.nodes }
        var nodes = record.nodes
        if let idx = nodes.firstIndex(where: { $0.status == .idle }) {
            nodes[idx].status = .running
        }
        return nodes
    }

    // MARK: - Description Section

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Description", icon: "text.alignleft")
            Text(record.description)
                .font(.system(size: 13))
                .foregroundStyle(Glass.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let q = record.pendingQuestion {
                sectionHeader(q, icon: "questionmark.circle.fill")
            } else {
                sectionHeader("Input Required", icon: "questionmark.circle.fill")
            }
            HStack(spacing: 10) {
                TextField("Enter response…", text: $pendingInput)
                    .font(.system(size: 13))
                    .foregroundStyle(Glass.textPrimary)
                    .padding(10)
                    .background(Glass.backgroundDark)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                    )

                GlassButton("Send", icon: "paperplane.fill", tint: .purple) {
                    sendInput()
                }
                .disabled(pendingInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Run Section

    private var runSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                sectionHeader("Execution", icon: "play.circle.fill")
                Spacer()
                if isRunning {
                    GlassButton("Stop", icon: "stop.circle.fill", tint: .red) {
                        appState.stopCodeSession()
                    }
                } else {
                    GlassButton("Run", icon: "play.fill", tint: .cyan) {
                        runTask()
                    }
                    .disabled(isRunning)
                }
            }

            // Live streaming output
            if isRunning || !appState.codeSessionMessages.isEmpty {
                liveOutputView
            }
        }
    }

    private var liveOutputView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(appState.codeSessionMessages) { msg in
                        messageRow(msg)
                            .id(msg.id)
                    }
                    if appState.codeIsStreaming {
                        HStack(spacing: 6) {
                            CanvasPulsingDot(color: .cyan)
                            Text("Running…")
                                .font(.system(size: 11))
                                .foregroundStyle(Glass.textTertiary)
                        }
                        .id("streaming")
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 200)
            .background(Color.black.opacity(0.3))
            .cornerRadius(Glass.radiusSmall)
            .overlay(
                RoundedRectangle(cornerRadius: Glass.radiusSmall)
                    .stroke(Glass.divider, lineWidth: 1)
            )
            .onChange(of: appState.codeSessionMessages.count) { _ in
                if let last = appState.codeSessionMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ msg: CodeMessage) -> some View {
        switch msg.role {
        case .assistant:
            Text(msg.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Glass.textPrimary)
                .textSelection(.enabled)
        case .tool:
            HStack(spacing: 4) {
                Image(systemName: "wrench.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.cyan.opacity(0.6))
                Text(msg.text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.cyan.opacity(0.8))
            }
        case .status:
            Text(msg.text)
                .font(.system(size: 10))
                .foregroundStyle(Glass.textTertiary)
                .italic()
        case .error:
            Text(msg.text)
                .font(.system(size: 11))
                .foregroundStyle(Color.red.opacity(0.8))
        case .user:
            Text("> \(msg.text)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Glass.textSecondary)
        }
    }

    // MARK: - Run History Section

    private var runHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Run History", icon: "clock.fill")

            ForEach(runHistory.prefix(10)) { step in
                TaskRunStepRow(step: step)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Glass.textTertiary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Glass.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: TaskRecordStatus) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case .idle:           return ("Idle", Glass.textTertiary)
            case .running:        return ("Running", .orange)
            case .completed:      return ("Done", .green)
            case .failed:         return ("Failed", .red)
            case .needsInput:     return ("Needs Input", .purple)
            case .pendingApproval:return ("Pending", .orange)
            case .building:       return ("Building", .cyan)
            }
        }()
        GlassChip(label)
            .foregroundStyle(color)
    }

    // MARK: - Actions

    private func runTask() {
        switch record.source {
        case .capability(let cap):
            appState.executeCapability(cap)
        case .pipelineTask(let task):
            appState.runPipelineTask(id: task.id)
        case .learnSession:
            break
        }
        checkRunning()
    }

    private func sendInput() {
        let msg = pendingInput.trimmingCharacters(in: .whitespaces)
        guard !msg.isEmpty else { return }
        appState.feedVoiceToCodeSession(msg)
        pendingInput = ""
    }

    private func loadRunHistory() {
        switch record.source {
        case .pipelineTask(let task):
            runHistory = appState.pipelineStore.fetchSteps(taskID: task.id)
        case .capability(let cap):
            // Find pipeline tasks created from this capability and fetch their steps
            let capTasks = appState.pipelineTasks.filter { $0.id.hasPrefix("CAP-") && $0.title.contains(cap.name) }
            runHistory = capTasks.flatMap { appState.pipelineStore.fetchSteps(taskID: $0.id) }
                .sorted { $0.timestamp < $1.timestamp }
        case .learnSession:
            break
        }
    }

    private func checkRunning() {
        isRunning = appState.codeIsStreaming && (appState.codeTaskID == record.id ||
            appState.codeSessionMessages.first?.text.contains(record.title) == true)
    }
}

// MARK: - TaskRunStepRow

private struct TaskRunStepRow: View {
    let step: TaskExecutionStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Status icon
            Image(systemName: statusIcon)
                .font(.system(size: 11))
                .foregroundStyle(statusColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.description)
                    .font(.system(size: 12))
                    .foregroundStyle(Glass.textSecondary)
                    .lineLimit(2)
                if let output = step.output, !output.isEmpty {
                    Text(output.prefix(120))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Glass.textTertiary)
                        .lineLimit(3)
                }
            }

            Spacer()

            Text(step.timestamp.formatted(.relative(presentation: .named)))
                .font(.system(size: 9))
                .foregroundStyle(Glass.textTertiary)
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch step.status {
        case "completed": return "checkmark.circle.fill"
        case "running":   return "play.circle.fill"
        case "failed":    return "xmark.circle.fill"
        default:          return "circle"
        }
    }

    private var statusColor: Color {
        switch step.status {
        case "completed": return .green
        case "running":   return .orange
        case "failed":    return .red
        default:          return Glass.textTertiary
        }
    }
}
