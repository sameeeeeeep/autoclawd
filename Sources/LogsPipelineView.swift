import SwiftUI

// MARK: - Status Color Helper

private func statusColor(_ status: String, theme: ThemePalette) -> Color {
    switch status {
    case "completed":        return theme.accent
    case "ongoing",
         "pending_approval": return theme.warning
    case "needs_input":      return theme.secondary
    default:                 return theme.textTertiary
    }
}

// MARK: - Lookup Tables

private let peopleNames: [String: String] = [
    "you": "You", "mukul": "Mukul", "priya": "Priya",
    "arjun": "Arjun", "neha": "Neha",
]

private let projectNames: [String: String] = [
    "autoclawd": "AutoClawd", "trippy": "Trippy AI", "personal": "Personal",
]

private let placeNames: [String: String] = [
    "office": "\u{1F3E2} Office", "home": "\u{1F3E0} Home",
    "cafe": "\u{2615} Caf\u{00E9}", "gym": "\u{1F4AA} Gym",
]

// MARK: - LogsPipelineView

struct LogsPipelineView: View {
    @ObservedObject var appState: AppState

    @State private var filterProject: String? = nil
    @State private var filterPlace: String? = nil
    @State private var filterStatus: String? = nil
    @State private var selectedRowID: String? = nil
    @State private var expandedStage: String? = nil

    private let projects = [
        ("autoclawd", "AutoClawd"),
        ("trippy", "Trippy AI"),
        ("personal", "Personal"),
    ]
    private let places = [
        ("office", "\u{1F3E2} Office"),
        ("home", "\u{1F3E0} Home"),
        ("cafe", "\u{2615} Caf\u{00E9}"),
    ]
    private let statuses = [
        "completed", "ongoing", "pending_approval", "needs_input", "upcoming",
    ]

    private var allGroups: [PipelineGroup] { PipelineGroup.mockData() }

    private var filteredGroups: [PipelineGroup] {
        allGroups.filter { group in
            if let fp = filterProject {
                let groupProject = group.analysisProject ?? group.tasks.first?.project
                if groupProject != fp { return false }
            }
            if let fpl = filterPlace {
                if group.placeTag != fpl { return false }
            }
            if let fs = filterStatus {
                let hasStatus = group.tasks.contains { $0.status.rawValue == fs }
                if !hasStatus && !group.tasks.isEmpty { return false }
                if group.tasks.isEmpty && fs != "filtered" { return false }
            }
            return true
        }
    }

    private var anyFilterActive: Bool {
        filterProject != nil || filterPlace != nil || filterStatus != nil
    }

    var body: some View {
        let theme = ThemeManager.shared.current
        VStack(spacing: 0) {
            filterBar
            HStack(spacing: 0) {
                pipelineTable
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if selectedRowID != nil {
                    detailSidebar
                        .frame(width: 300)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .background(theme.isDark ? Color.black.opacity(0.05) : Color.black.opacity(0.01))
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
                TagView(type: .status, label: "\(filteredGroups.count) groups", small: true)
                Spacer()
            }

            // Filter row
            HStack(spacing: 6) {
                Text("Filter:")
                    .font(.system(size: 8, weight: .regular))
                    .foregroundColor(theme.textTertiary)
                    .padding(.trailing, 2)

                // Project filters
                ForEach(projects, id: \.0) { key, label in
                    filterChip(
                        label: label,
                        isActive: filterProject == key,
                        activeColor: theme.tagProject
                    ) {
                        filterProject = filterProject == key ? nil : key
                    }
                }

                filterSeparator

                // Place filters
                ForEach(places, id: \.0) { key, label in
                    filterChip(
                        label: label,
                        isActive: filterPlace == key,
                        activeColor: theme.tagPlace
                    ) {
                        filterPlace = filterPlace == key ? nil : key
                    }
                }

                filterSeparator

                // Status filters
                ForEach(statuses, id: \.self) { status in
                    filterChip(
                        label: status.replacingOccurrences(of: "_", with: " "),
                        isActive: filterStatus == status,
                        activeColor: statusColor(status, theme: theme)
                    ) {
                        filterStatus = filterStatus == status ? nil : status
                    }
                }

                // Clear button
                if anyFilterActive {
                    Button {
                        filterProject = nil
                        filterPlace = nil
                        filterStatus = nil
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

    // MARK: - Pipeline Table

    private var pipelineTable: some View {
        let theme = ThemeManager.shared.current
        return VStack(spacing: 0) {
            columnHeaderRow
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredGroups) { group in
                        pipelineRow(group: group)
                    }
                }
            }
        }
        .background(theme.isDark ? Color.clear : Color.clear)
    }

    // MARK: - Column Header Row

    private var columnHeaderRow: some View {
        let theme = ThemeManager.shared.current
        return HStack(spacing: 0) {
            columnHeader("TIME", color: theme.textTertiary)
                .frame(width: 55)
            columnHeader("TRANSCRIPT \u{1F399}", color: theme.textSecondary)
                .frame(maxWidth: .infinity)
                .layoutPriority(1.2)
            columnHeader("CLEANING \u{1F9F9}", color: theme.tertiary)
                .frame(maxWidth: .infinity)
                .layoutPriority(1.2)
            columnHeader("ANALYSIS \u{1F9E0}", color: theme.secondary)
                .frame(maxWidth: .infinity)
                .layoutPriority(1.0)
            columnHeader("TASK \u{26A1}", color: theme.warning)
                .frame(maxWidth: .infinity)
                .layoutPriority(1.2)
            columnHeader("RESULT \u{2713}", color: theme.accent)
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
                        Text(chunk.duration)
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(theme.textTertiary)
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
                TagView(type: .project, label: projectNames[proj] ?? proj, small: true)
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
                    taskMiniCard(task: task)
                }
            }
        }
    }

    private func taskMiniCard(task: PipelineTask) -> some View {
        let theme = ThemeManager.shared.current
        let modeBadgeMode: ModeBadge.Mode = {
            switch task.mode {
            case .auto: return .auto
            case .ask:  return .ask
            case .user: return .user
            }
        }()

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(task.id)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(theme.textTertiary)
                ModeBadge(mode: modeBadgeMode)
            }
            Text(task.title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(theme.warning)
                .lineLimit(2)

            // Accept / Reject for pending tasks
            if task.status == .pending_approval || task.status == .needs_input {
                HStack(spacing: 4) {
                    Button {
                        // Accept action
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
                        // Reject action
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "xmark")
                                .font(.system(size: 7))
                            Text("Reject")
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
                .fill(theme.warning.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(theme.warning.opacity(0.12), lineWidth: 0.5)
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
                    Text(task.result.duration)
                        .font(.system(size: 7))
                        .foregroundColor(theme.textTertiary)
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
                            emoji: "\u{1F399}",
                            name: "TRANSCRIPT",
                            color: theme.textSecondary,
                            group: group
                        )
                        detailStageSection(
                            stage: "cleaning",
                            emoji: "\u{1F9F9}",
                            name: "CLEANING",
                            color: theme.tertiary,
                            group: group
                        )
                        detailStageSection(
                            stage: "analysis",
                            emoji: "\u{1F9E0}",
                            name: "ANALYSIS",
                            color: theme.secondary,
                            group: group
                        )
                        detailStageSection(
                            stage: "task",
                            emoji: "\u{26A1}",
                            name: "TASK",
                            color: theme.warning,
                            group: group
                        )
                        detailStageSection(
                            stage: "result",
                            emoji: "\u{2713}",
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
            Text(group.id)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(theme.textPrimary)
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
            if let place = group.placeTag {
                TagView(type: .place, label: placeNames[place] ?? place, small: true)
            }
            if let person = group.personTag {
                TagView(type: .person, label: peopleNames[person] ?? person, small: true)
            }
            if let proj = group.analysisProject {
                TagView(type: .project, label: projectNames[proj] ?? proj, small: true)
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
                    Text(emoji)
                        .font(.system(size: 10))
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
                        Text(chunk.duration)
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(theme.textTertiary)
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
                Text("Filtered out at cleaning stage")
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
                        TagView(type: .project, label: projectNames[proj] ?? proj, small: true)
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
                Text("No tasks generated")
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

        return VStack(alignment: .leading, spacing: 6) {
            // ID + project + mode
            HStack(spacing: 4) {
                Text(task.id)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(theme.textTertiary)
                TagView(type: .project, label: projectNames[task.project] ?? task.project, small: true)
                ModeBadge(mode: modeBadgeMode)
            }

            // Title
            Text(task.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(theme.warning)

            // Skill badge
            if let skill = task.skill {
                Text("\u{1F9E0} \(skill)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(theme.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(theme.tertiary.opacity(0.09))
                    )
                    .overlay(
                        Capsule()
                            .stroke(theme.tertiary.opacity(0.15), lineWidth: 0.5)
                    )
            }

            // Workflow visualization
            if !task.workflowSteps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(task.workflowSteps.enumerated()), id: \.offset) { idx, step in
                        HStack(spacing: 4) {
                            if idx > 0 {
                                Text("\u{2192}")
                                    .font(.system(size: 8))
                                    .foregroundColor(theme.accent.opacity(0.5))
                            }
                            Text(step)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(theme.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(theme.accent.opacity(0.10))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(theme.accent.opacity(0.20), lineWidth: 0.5)
                                )
                        }
                    }
                }
            }

            // Missing connection warning
            if let missing = task.missingConnection {
                HStack(spacing: 6) {
                    Text("\u{26A0}\u{FE0F}")
                        .font(.system(size: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Missing Connection")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(theme.error)
                        Text(missing)
                            .font(.system(size: 8))
                            .foregroundColor(theme.error.opacity(0.80))
                        Button {
                            // Go to connections
                        } label: {
                            Text("\u{2192} Go to Connections")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.error.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(theme.error.opacity(0.20), lineWidth: 0.5)
                )
            }

            // Prompt
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

            // Accept / Reject / Resolve for pending tasks
            if task.status == .pending_approval || task.status == .needs_input {
                HStack(spacing: 6) {
                    Button {
                        // Accept action
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8))
                            Text("Accept")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .foregroundColor(theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(theme.accent.opacity(0.18))
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        // Reject action
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8))
                            Text("Reject")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .foregroundColor(theme.error)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(theme.error.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        // Resolve with AI
                    } label: {
                        HStack(spacing: 3) {
                            Text("\u{1F4AC}")
                                .font(.system(size: 8))
                            Text("Resolve with AI")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .foregroundColor(theme.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(theme.tertiary.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
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
                            Text(task.result.duration)
                                .font(.system(size: 7))
                                .foregroundColor(theme.textTertiary)
                        }

                        // Step-by-step execution log
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(task.result.steps.enumerated()), id: \.offset) { idx, step in
                                HStack(alignment: .top, spacing: 6) {
                                    // Step indicator circle
                                    let isCompleted = idx < task.result.steps.count - 1
                                        || task.status == .completed
                                    Circle()
                                        .fill(isCompleted
                                            ? theme.accent.opacity(0.80)
                                            : theme.warning.opacity(0.60))
                                        .frame(width: 12, height: 12)
                                        .overlay(
                                            Text(isCompleted ? "\u{2713}" : "\u{2026}")
                                                .font(.system(size: 7, weight: .bold))
                                                .foregroundColor(
                                                    theme.isDark
                                                        ? Color.black
                                                        : Color.white
                                                )
                                        )

                                    Text(step)
                                        .font(.system(size: 9))
                                        .foregroundColor(theme.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
