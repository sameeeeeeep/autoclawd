import SwiftUI

// MARK: - WorldSpaceView

struct WorldSpaceView: View {
    @ObservedObject var appState: AppState

    @State private var selectedPlaceID: String = "office"
    @State private var viewMode: String = "overview" // "overview" or "byday"
    @State private var selectedDayOffset: Int = 0

    private let places = PlaceDetail.mockPlaces()
    private let allActivities = PlaceActivity.mockActivities()
    private let allGroups = PipelineGroup.mockData()

    private let mockPeople: [(id: String, name: String, role: String?)] = [
        ("you", "You", nil),
        ("mukul", "Mukul", "Co-founder, CTO"),
        ("priya", "Priya", "Design Lead"),
        ("arjun", "Arjun", "Backend Dev"),
        ("neha", "Neha", "Marketing"),
    ]

    private var selectedPlace: PlaceDetail {
        places.first(where: { $0.id == selectedPlaceID }) ?? places[0]
    }

    private var activitiesForPlace: [PlaceActivity] {
        allActivities[selectedPlaceID] ?? []
    }

    private var tasksForPlace: [PipelineTask] {
        allGroups
            .filter { $0.placeTag == selectedPlaceID }
            .flatMap { $0.tasks }
    }

    private var peopleAtPlace: [(id: String, name: String, role: String?)] {
        let ids = selectedPlace.peopleIDs
        return mockPeople.filter { ids.contains($0.id) }
    }

    /// Unique day offsets present in current place activities, sorted ascending.
    private var availableDayOffsets: [Int] {
        let offsets = Set(activitiesForPlace.map { $0.dayOffset })
        return offsets.sorted()
    }

    /// Activities filtered for the selected day in By Day mode.
    private var activitiesForSelectedDay: [PlaceActivity] {
        activitiesForPlace.filter { $0.dayOffset == selectedDayOffset }
    }

    var body: some View {
        let theme = ThemeManager.shared.current
        HStack(spacing: 0) {
            placeListPanel
                .frame(width: 210)
                .overlay(
                    Rectangle()
                        .fill(theme.glassBorder)
                        .frame(width: 0.5),
                    alignment: .trailing
                )

            placeDetailPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Left Panel: Place List

    private var placeListPanel: some View {
        let theme = ThemeManager.shared.current
        return VStack(alignment: .leading, spacing: 0) {
            Text("Places")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(places) { place in
                        placeCard(place: place)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
    }

    private func placeCard(place: PlaceDetail) -> some View {
        let theme = ThemeManager.shared.current
        let isSelected = selectedPlaceID == place.id
        let activities = allActivities[place.id] ?? []

        return Button {
            selectedPlaceID = place.id
            // Reset view mode when switching places
            viewMode = "overview"
            selectedDayOffset = 0
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text(place.icon)
                    .font(.system(size: 18))

                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(theme.textPrimary)

                    Text(place.address)
                        .font(.system(size: 9))
                        .foregroundColor(theme.textTertiary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        TagView(type: .person, label: "\(place.peopleIDs.count)", small: true)
                        TagView(type: .action, label: "\(activities.count) events", small: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? theme.accent.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isSelected ? theme.accent.opacity(0.18) : Color.clear, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right Panel: Place Detail

    private var placeDetailPanel: some View {
        VStack(spacing: 0) {
            detailHeader
            if viewMode == "byday" {
                daySelector
            }
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    peopleSection
                    activityTimeline
                    if !tasksForPlace.isEmpty {
                        tasksSection
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: - Detail Header

    private var detailHeader: some View {
        let theme = ThemeManager.shared.current
        let place = selectedPlace

        return HStack(alignment: .center) {
            // Left: Place info
            HStack(alignment: .center, spacing: 10) {
                Text(place.icon)
                    .font(.system(size: 20))

                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(theme.textPrimary)

                    Text(place.address)
                        .font(.system(size: 9))
                        .foregroundColor(theme.textTertiary)
                }

                TagView(type: .place, label: place.name)
            }

            Spacer()

            // Right: View mode toggle
            viewModeToggle
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 18)
        .overlay(
            Rectangle()
                .fill(theme.glassBorder)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - View Mode Toggle

    private var viewModeToggle: some View {
        let theme = ThemeManager.shared.current
        return HStack(spacing: 0) {
            toggleButton(label: "Overview", mode: "overview")
            toggleButton(label: "By Day", mode: "byday")
        }
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(theme.glassBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func toggleButton(label: String, mode: String) -> some View {
        let theme = ThemeManager.shared.current
        let isActive = viewMode == mode

        return Button {
            viewMode = mode
            if mode == "byday" {
                // Default to most recent day offset
                selectedDayOffset = availableDayOffsets.first ?? 0
            }
        } label: {
            Text(label)
                .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? theme.accent : theme.textTertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(isActive ? theme.accent.opacity(0.18) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Day Selector

    private var daySelector: some View {
        let theme = ThemeManager.shared.current
        let recentDays = (0..<7)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(recentDays), id: \.self) { offset in
                    let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
                    let code = Episode.code(from: date)
                    let isSelected = selectedDayOffset == offset
                    let hasActivity = activitiesForPlace.contains(where: { $0.dayOffset == offset })

                    Button {
                        selectedDayOffset = offset
                    } label: {
                        VStack(spacing: 3) {
                            Text(code)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(isSelected ? theme.accent : theme.textSecondary)

                            Text(dayLabel(offset: offset))
                                .font(.system(size: 8))
                                .foregroundColor(isSelected ? theme.accent : theme.textTertiary)

                            if hasActivity {
                                Circle()
                                    .fill(theme.accent)
                                    .frame(width: 4, height: 4)
                            } else {
                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: 4, height: 4)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(isSelected ? theme.accent.opacity(0.12) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(isSelected ? theme.accent.opacity(0.3) : Color.clear, lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .overlay(
            Rectangle()
                .fill(theme.glassBorder)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    private func dayLabel(offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        if offset == 0 { return "Today" }
        if offset == 1 { return "Yesterday" }
        return formatter.string(from: date)
    }

    // MARK: - People Section

    private var peopleSection: some View {
        let theme = ThemeManager.shared.current
        let people = peopleAtPlace

        return VStack(alignment: .leading, spacing: 8) {
            Text("PEOPLE AT \(selectedPlace.name.uppercased())")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundColor(theme.textSecondary)
                .textCase(.uppercase)

            // Wrapping HStack of person cards
            FlowLayout(spacing: 6) {
                ForEach(people, id: \.id) { person in
                    personCard(person: person)
                }
            }
        }
    }

    private func personCard(person: (id: String, name: String, role: String?)) -> some View {
        let theme = ThemeManager.shared.current
        return HStack(spacing: 6) {
            Circle()
                .fill(theme.accent)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(person.name)
                    .font(.system(size: 11))
                    .foregroundColor(theme.textPrimary)

                if let role = person.role {
                    Text(role)
                        .font(.system(size: 8))
                        .foregroundColor(theme.textTertiary)
                }
            }

            InfoButton()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .glassCard(cornerRadius: 9)
    }

    // MARK: - Activity Timeline

    private var activityTimeline: some View {
        let theme = ThemeManager.shared.current
        let activities: [PlaceActivity] = viewMode == "byday"
            ? activitiesForSelectedDay
            : activitiesForPlace
        let eventCount = activities.count

        let headerText: String = {
            if viewMode == "byday" {
                let date = Calendar.current.date(byAdding: .day, value: -selectedDayOffset, to: Date()) ?? Date()
                let code = Episode.code(from: date)
                return "ACTIVITY \u{2014} \(code)"
            } else {
                return "ALL ACTIVITY"
            }
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(headerText)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(theme.textSecondary)

                Text("\(eventCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(theme.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(theme.glassBorder)
                    )
            }

            if activities.isEmpty {
                emptyActivityState
            } else {
                timelineContent(activities: activities)
            }
        }
    }

    private var emptyActivityState: some View {
        let theme = ThemeManager.shared.current
        return HStack {
            Spacer()
            Text("No activity at this place on this day")
                .font(.system(size: 11))
                .foregroundColor(theme.textTertiary)
                .padding(.vertical, 32)
            Spacer()
        }
    }

    private func timelineContent(activities: [PlaceActivity]) -> some View {
        let theme = ThemeManager.shared.current
        let grouped = Dictionary(grouping: activities, by: { $0.dayOffset })
        let sortedDays = grouped.keys.sorted()

        return ZStack(alignment: .topLeading) {
            // Timeline vertical line
            Rectangle()
                .fill(theme.glassBorder)
                .frame(width: 1)
                .padding(.leading, 5)

            // Content
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sortedDays, id: \.self) { dayOffset in
                    let dayActivities = grouped[dayOffset] ?? []

                    // Day header in overview mode
                    if viewMode == "overview" {
                        dayHeader(dayOffset: dayOffset)
                    }

                    ForEach(dayActivities) { activity in
                        activityEntry(activity: activity)
                    }
                }
            }
            .padding(.leading, 18)
        }
    }

    private func dayHeader(dayOffset: Int) -> some View {
        let theme = ThemeManager.shared.current
        let date = Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date()
        let code = Episode.code(from: date)
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        let dateStr = formatter.string(from: date)

        return HStack(spacing: 8) {
            // Timeline node
            Circle()
                .fill(theme.accent)
                .frame(width: 9, height: 9)
                .offset(x: -22.5) // Center on the timeline line: -(18 - 5) + (9/2) -> shifted to align

            Text(code)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(theme.accent)

            Text(dateStr)
                .font(.system(size: 9))
                .foregroundColor(theme.textTertiary)
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func activityEntry(activity: PlaceActivity) -> some View {
        let theme = ThemeManager.shared.current
        let dotColor = activityDotColor(type: activity.type)
        let personName = mockPeople.first(where: { $0.id == activity.personID })?.name ?? activity.personID

        return HStack(alignment: .top, spacing: 0) {
            // Timeline dot
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .offset(x: -21.5, y: 10) // Align with timeline line

            // Content card
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(activity.time)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(theme.textTertiary)

                    TagView(type: .person, label: personName, small: true)

                    if let project = activity.project {
                        TagView(type: .project, label: project, small: true)
                    }

                    TagView(type: .action, label: activity.type.rawValue, small: true)

                    Spacer(minLength: 0)

                    InfoButton()
                }

                Text(activity.text)
                    .font(.system(size: 10))
                    .foregroundColor(theme.textSecondary)
                    .lineSpacing(10 * 0.4) // ~1.4 line height
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.isDark
                          ? Color.white.opacity(0.015)
                          : Color.black.opacity(0.015))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.glassBorder, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.bottom, 6)
    }

    private func activityDotColor(type: ActivityType) -> Color {
        let theme = ThemeManager.shared.current
        switch type {
        case .location:   return theme.accent
        case .meeting:    return theme.secondary
        case .transcript: return theme.tertiary
        case .social:     return theme.warning
        case .personal:   return theme.textTertiary
        }
    }

    // MARK: - Tasks Section

    private var tasksSection: some View {
        let theme = ThemeManager.shared.current
        return VStack(alignment: .leading, spacing: 8) {
            Text("TASKS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundColor(theme.textSecondary)

            ForEach(tasksForPlace, id: \.id) { task in
                taskCard(task: task)
            }
        }
    }

    private func taskCard(task: PipelineTask) -> some View {
        let theme = ThemeManager.shared.current
        let statusColor: Color = {
            switch task.status {
            case .completed:        return theme.accent
            case .ongoing:          return theme.warning
            case .pending_approval: return theme.warning
            case .needs_input:      return theme.secondary
            case .upcoming:         return theme.textTertiary
            case .filtered:         return theme.textTertiary
            }
        }()

        let modeValue: ModeBadge.Mode = {
            switch task.mode {
            case .auto: return .auto
            case .ask:  return .ask
            case .user: return .user
            }
        }()

        return HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(task.title)
                .font(.system(size: 10))
                .foregroundColor(theme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                TagView(type: .project, label: task.project, small: true)
                ModeBadge(mode: modeValue)
                TagView(type: .status, label: task.status.rawValue.replacingOccurrences(of: "_", with: " "), small: true)
            }
        }
        .padding(10)
        .glassCard(cornerRadius: 8)
    }
}

// MARK: - FlowLayout (Wrapping HStack)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let point = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private struct ArrangeResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
            totalHeight = currentY + rowHeight
        }

        return ArrangeResult(size: CGSize(width: totalWidth, height: totalHeight), positions: positions)
    }
}
