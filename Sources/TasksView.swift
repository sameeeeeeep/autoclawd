import SwiftUI

// MARK: - TasksView
//
// Main Tasks panel. Replaces the Canvas tab.
//
// Lists:
//  • Active Learn Mode session (if any) — always at top
//  • Capabilities from CapabilityStore (recurring, on-demand)
//  • Pipeline tasks from appState.pipelineTasks (one-time)
//
// Tapping a row opens TaskDetailView as a .sheet.
// "Build" button enters Learn Mode and opens the active session detail.

// MARK: - Filter

enum TaskFilter: String, CaseIterable, Identifiable {
    case all       = "All"
    case recurring = "Recurring"
    case active    = "Active"
    case completed = "Completed"
    var id: String { rawValue }
}

// MARK: - TasksView

struct TasksView: View {

    @ObservedObject var appState: AppState

    @State private var selectedFilter: TaskFilter = .all
    @State private var selectedProjectID: String? = nil
    @State private var taskRecords: [TaskRecord] = []
    @State private var selectedRecord: TaskRecord? = nil
    @State private var showDetail = false
    @State private var showLearnSession = false

    var body: some View {
        ZStack {
            AppTheme.glassAmbientBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                GlassDivider()
                filterBar
                GlassDivider()
                taskList
            }
        }
        .onAppear { reload() }
        .onChange(of: appState.pipelineTasks.count) { _ in reload() }
        .onChange(of: appState.learnModeService.session?.phase) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .capabilityStoreDidChange)) { _ in reload() }
        .sheet(isPresented: $showDetail) {
            if let record = selectedRecord {
                TaskDetailView(record: record, appState: appState)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tasks")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Glass.textPrimary)
                Text("\(taskRecords.count) task\(taskRecords.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(Glass.textSecondary)
            }

            Spacer()

            // Project picker
            if appState.projects.count > 1 {
                Picker("Project", selection: $selectedProjectID) {
                    Text("All Projects").tag(nil as String?)
                    ForEach(appState.projects) { proj in
                        Text(proj.name).tag(proj.id as String?)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 11))
                .foregroundStyle(Glass.textSecondary)
                .onChange(of: selectedProjectID) { _ in reload() }
            }

            // Build / Learn Mode button
            buildButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.25))
    }

    @ViewBuilder
    private var buildButton: some View {
        if appState.pillMode == .learn {
            Button {
                // Open the active learn session detail
                if let session = appState.learnModeService.session {
                    selectedRecord = TaskRecord.fromLearnSession(session)
                    showDetail = true
                }
            } label: {
                HStack(spacing: 6) {
                    CanvasPulsingDot(color: .red)
                    Text("Learning…")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.1))
                .overlay(Capsule().stroke(Color.red.opacity(0.3), lineWidth: 1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        } else {
            GlassButton("Build", icon: "brain.head.profile", tint: .cyan) {
                appState.pillMode = .learn
                // Give the session time to start, then open its detail
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let session = appState.learnModeService.session {
                        selectedRecord = TaskRecord.fromLearnSession(session)
                        showDetail = true
                    }
                }
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TaskFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedFilter = filter
                            reload()
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 12, weight: selectedFilter == filter ? .semibold : .regular))
                            .foregroundStyle(selectedFilter == filter ? Glass.textPrimary : Glass.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(selectedFilter == filter ? Color.cyan.opacity(0.15) : Color.clear)
                                    .overlay(
                                        Capsule()
                                            .stroke(selectedFilter == filter ? Color.cyan.opacity(0.35) : Color.clear, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.black.opacity(0.1))
    }

    // MARK: - Task List

    @ViewBuilder
    private var taskList: some View {
        if taskRecords.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(taskRecords) { record in
                        TaskRowView(
                            record: record,
                            isRunning: isTaskRunning(record),
                            onTap: {
                                selectedRecord = record
                                showDetail = true
                            }
                        )
                        GlassDivider().padding(.leading, 64)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            GlassIconBadge("checklist", size: 48, tint: .cyan)
            Text("No Tasks Yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Glass.textPrimary)
            Text("Tap Build to enter Learn Mode\nand record a workflow to automate.")
                .font(.system(size: 12))
                .foregroundStyle(Glass.textSecondary)
                .multilineTextAlignment(.center)
            GlassButton("Start Building", icon: "brain.head.profile", tint: .cyan) {
                appState.pillMode = .learn
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    private func reload() {
        var records: [TaskRecord] = []

        // 1. Active Learn Session at top
        if let session = appState.learnModeService.session {
            records.append(TaskRecord.fromLearnSession(session))
        }

        // 2. Capabilities from CapabilityStore
        let caps = CapabilityStore.shared.all()
        let capRecords = caps.map { cap -> TaskRecord in
            let schedule = TaskScheduleStore.shared.schedule(for: cap.id)
            return TaskRecord.from(cap, schedule: schedule)
        }

        // 3. Pipeline tasks (exclude ones created from capabilities to avoid duplication)
        let capNames = Set(caps.map { $0.name })
        let pipelineRecords = appState.pipelineTasks
            .filter { task in
                // Keep if NOT a capability run (those have title containing cap name)
                let isCapRun = caps.contains { cap in
                    task.id.hasPrefix("CAP-") && task.title.contains(cap.name)
                }
                return !isCapRun
            }
            .map { TaskRecord.from($0) }

        records += capRecords
        records += pipelineRecords

        // Project filter
        if let pid = selectedProjectID {
            records = records.filter { $0.projectID == pid || $0.projectID == nil }
        }

        // Tab filter
        switch selectedFilter {
        case .all:
            break
        case .recurring:
            records = records.filter { $0.isRecurring }
        case .active:
            records = records.filter { [.running, .building, .pendingApproval, .needsInput].contains($0.status) }
        case .completed:
            records = records.filter { $0.status == .completed }
        }

        taskRecords = records
    }

    private func isTaskRunning(_ record: TaskRecord) -> Bool {
        guard appState.codeIsStreaming else { return false }
        switch record.source {
        case .capability(let cap):
            return appState.pipelineTasks.first { $0.id.hasPrefix("CAP-") && $0.title.contains(cap.name) && $0.status == .ongoing } != nil
        case .pipelineTask(let task):
            return task.status == .ongoing || appState.pipelineTasks.first { $0.id == task.id && $0.status == .ongoing } != nil
        case .learnSession:
            return appState.learnModeService.isActive
        }
    }
}
