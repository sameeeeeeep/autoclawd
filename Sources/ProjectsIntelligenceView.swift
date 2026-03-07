import SwiftUI

// MARK: - Projects Intelligence View

struct ProjectsIntelligenceView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedProjectID: String?

    private var selectedProject: Project? {
        guard let id = selectedProjectID else { return nil }
        return appState.projects.first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 0) {

            // ── Left nav ─────────────────────────────────────────
            PINavColumn(
                projects: appState.projects,
                tasks: appState.pipelineTasks,
                selectedID: $selectedProjectID
            )
            .frame(width: 160)

            Divider().opacity(0.06)

            // ── Center + right ────────────────────────────────────
            if let project = selectedProject {
                let projectTasks    = appState.pipelineTasks.filter { $0.projectID == project.id }
                let projectAnalyses = appState.transcriptAnalyses.filter { $0.projectID == project.id }

                PIProfileCard(project: project, analyses: projectAnalyses, tasks: projectTasks)
                    .frame(width: 320)

                Divider().opacity(0.06)

                IntelligenceTaskFeed(
                    header: "TASKS",
                    tasks: projectTasks,
                    appState: appState
                )
            } else {
                IntelligenceEmptyHint(icon: "folder", text: "Select a project")
            }
        }
        .onAppear {
            if selectedProjectID == nil {
                selectedProjectID = appState.projects.first?.id
            }
        }
        .onChange(of: appState.projects) { _ in
            if selectedProjectID == nil {
                selectedProjectID = appState.projects.first?.id
            }
        }
    }
}

// MARK: - Nav Column

private struct PINavColumn: View {
    let projects: [Project]
    let tasks: [PipelineTaskRecord]
    @Binding var selectedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PROJECTS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 10)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 1) {
                    ForEach(projects) { project in
                        let hasPending = tasks.contains {
                            $0.projectID == project.id &&
                            ($0.status == .pending_approval || $0.status == .needs_input)
                        }
                        PINavRow(
                            project: project,
                            hasPending: hasPending,
                            isSelected: selectedID == project.id
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.14)) {
                                selectedID = project.id
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
        }
        .background(.thickMaterial)
    }
}

private struct PINavRow: View {
    let project: Project
    let hasPending: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            PIProjectIcon(name: project.name, size: 22)

            Text(project.name)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if hasPending {
                Circle()
                    .fill(.orange)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isSelected ? Color.primary.opacity(0.07) : .clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Profile Card

private struct PIProfileCard: View {
    let project: Project
    let analyses: [TranscriptAnalysis]
    let tasks: [PipelineTaskRecord]

    private var recentAnalyses: [TranscriptAnalysis] {
        analyses.sorted { $0.timestamp > $1.timestamp }.prefix(3).map { $0 }
    }

    private var nextTask: PipelineTaskRecord? {
        tasks
            .filter { $0.status == .upcoming || $0.status == .pending_approval }
            .sorted { $0.createdAt < $1.createdAt }
            .first
    }

    private var insight: String {
        recentAnalyses
            .map { $0.summary }
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                // ── Header ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 14) {
                    PIProjectIcon(name: project.name, size: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name)
                            .font(.system(size: 18, weight: .semibold))

                        if !project.localPath.isEmpty {
                            Text(project.localPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    HStack(spacing: 16) {
                        IntelligenceStat(value: tasks.count, label: "tasks")
                        IntelligenceStat(value: analyses.count, label: "sessions")
                        if !project.tags.isEmpty {
                            IntelligenceStat(value: project.tags.count, label: "tags")
                        }
                    }

                    if !project.tags.isEmpty {
                        IntelligenceTagRow(tags: project.tags)
                    }
                }
                .padding(24)

                // ── AI Insight ────────────────────────────────────
                if !insight.isEmpty {
                    IntelligenceDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Insight", systemImage: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.purple)

                        Text(insight)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(24)
                }

                // ── Recent Sessions ───────────────────────────────
                if !recentAnalyses.isEmpty {
                    IntelligenceDivider()
                    VStack(alignment: .leading, spacing: 14) {
                        IntelligenceSectionLabel("RECENT")

                        ForEach(recentAnalyses, id: \.id) { a in
                            HStack(alignment: .top, spacing: 12) {
                                Circle()
                                    .fill(.purple.opacity(0.4))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 6)
                                    .frame(width: 12, alignment: .center)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(a.timestamp, style: .relative)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)

                                    if !a.summary.isEmpty {
                                        Text(a.summary)
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .lineSpacing(2)
                                    }
                                }
                            }
                        }
                    }
                    .padding(24)
                }

                // ── Next Action ───────────────────────────────────
                if let next = nextTask {
                    IntelligenceDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        IntelligenceSectionLabel("NEXT")

                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.purple)
                                .padding(.top, 2)

                            Text(next.title)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .background(
                            .purple.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(.purple.opacity(0.18), lineWidth: 1)
                        )
                    }
                    .padding(24)
                }

                Spacer(minLength: 32)
            }
        }
        .background(.regularMaterial)
    }
}

// MARK: - Project Icon
// Internal (not private) so PeopleIntelligenceView can reuse it.

struct PIProjectIcon: View {
    let name: String
    let size: CGFloat

    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var tint: Color {
        let palette: [Color] = [.purple, .blue, .indigo, .teal, .cyan, .orange, .pink, .mint]
        return palette[abs(name.hashValue) % palette.count]
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

// MARK: - Shared Intelligence Components
// Internal — used by both ProjectsIntelligenceView and PeopleIntelligenceView.

struct IntelligenceTaskFeed: View {
    let header: String
    let tasks: [PipelineTaskRecord]
    let appState: AppState

    private var pending: [PipelineTaskRecord] {
        tasks
            .filter { $0.status == .pending_approval || $0.status == .needs_input }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var upcoming: [PipelineTaskRecord] {
        tasks
            .filter { $0.status == .upcoming }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var done: [PipelineTaskRecord] {
        tasks
            .filter { $0.status == .completed || $0.status == .ongoing }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
            .prefix(20).map { $0 }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {

                HStack(spacing: 10) {
                    Text(header)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.5)
                    Spacer()
                    if !pending.isEmpty {
                        Text("\(pending.count) pending")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.1), in: Capsule())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 14)

                if !pending.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(pending) { task in
                            IntelligencePendingRow(task: task, appState: appState)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if !pending.isEmpty && (!upcoming.isEmpty || !done.isEmpty) {
                    IntelligenceDivider()
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                }

                if !upcoming.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(upcoming) { task in
                            IntelligenceSimpleRow(task: task)
                        }
                    }
                }

                if !done.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(done) { task in
                            IntelligenceSimpleRow(task: task, faded: true)
                        }
                    }
                }

                if tasks.isEmpty {
                    IntelligenceEmptyHint(icon: "checkmark.circle", text: "No tasks yet")
                }

                Spacer(minLength: 32)
            }
        }
    }
}

struct IntelligencePendingRow: View {
    let task: PipelineTaskRecord
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                IntelligenceModeBadge(mode: task.mode)
                Text(task.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button("Approve") { appState.executeTask(id: task.id) }
                    .buttonStyle(IntelligenceApproveStyle())
                Button("Dismiss") { appState.dismissTask(id: task.id) }
                    .buttonStyle(IntelligenceDismissStyle())
                Spacer()
                Text(relativeTime(task.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(14)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(.orange.opacity(0.6))
                .frame(width: 2)
                .padding(.vertical, 10)
        }
        .background(
            .primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private func relativeTime(_ date: Date) -> String {
        let d = Date().timeIntervalSince(date)
        if d < 60    { return "now" }
        if d < 3600  { return "\(Int(d / 60))m" }
        if d < 86400 { return "\(Int(d / 3600))h" }
        return "\(Int(d / 86400))d"
    }
}

struct IntelligenceSimpleRow: View {
    let task: PipelineTaskRecord
    var faded: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(faded ? .green.opacity(0.55) : .secondary.opacity(0.25))
                .frame(width: 6, height: 6)
            Text(task.title)
                .font(.system(size: 13))
                .foregroundStyle(faded ? .tertiary : .secondary)
                .lineLimit(1)
            Spacer()
            Text(relativeTime(faded ? (task.completedAt ?? task.createdAt) : task.createdAt))
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private func relativeTime(_ date: Date) -> String {
        let d = Date().timeIntervalSince(date)
        if d < 60    { return "now" }
        if d < 3600  { return "\(Int(d / 60))m" }
        if d < 86400 { return "\(Int(d / 3600))h" }
        return "\(Int(d / 86400))d"
    }
}

struct IntelligenceModeBadge: View {
    let mode: TaskMode

    private var label: String {
        switch mode {
        case .auto: return "Auto"
        case .ask:  return "Ask"
        case .user: return "Manual"
        }
    }

    private var color: Color {
        switch mode {
        case .auto: return .green
        case .ask:  return .purple
        case .user: return .blue
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

struct IntelligenceStat: View {
    let value: Int
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 13, weight: .semibold))
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
    }
}

struct IntelligenceTagRow: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 11))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.purple.opacity(0.1), in: Capsule())
                }
            }
        }
    }
}

struct IntelligenceSectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .tracking(0.5)
    }
}

struct IntelligenceDivider: View {
    var body: some View { Divider().opacity(0.07) }
}

struct IntelligenceEmptyHint: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(.quaternary)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct IntelligenceApproveStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.green)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                .green.opacity(configuration.isPressed ? 0.18 : 0.1),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }
}

struct IntelligenceDismissStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                .primary.opacity(configuration.isPressed ? 0.08 : 0.04),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }
}
