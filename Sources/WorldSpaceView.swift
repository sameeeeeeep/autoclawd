import SwiftUI

// MARK: - WorldSpaceView

struct WorldSpaceView: View {
    @ObservedObject var appState: AppState

    @State private var selectedPlaceID: String = ""
    @State private var viewMode: String = "overview" // "overview" or "byday"
    @State private var selectedDayOffset: Int = 0

    // Real data loaded on appear
    @State private var places: [PlaceDetail] = []
    @State private var allActivities: [String: [PlaceActivity]] = [:]
    @State private var placePeopleNames: [String: [String]] = [:]  // placeID → person names seen there

    private let sessionStore = SessionStore.shared

    private var selectedPlace: PlaceDetail {
        places.first(where: { $0.id == selectedPlaceID }) ?? places.first ?? PlaceDetail(id: "", name: "Unknown", icon: "\u{1F4CD}", address: "", peopleIDs: [], activityCount: 0)
    }

    private var activitiesForPlace: [PlaceActivity] {
        allActivities[selectedPlaceID] ?? []
    }

    /// Extraction items and structured todos, shown as tasks for the selected place.
    private var tasksForPlace: [SpaceTaskItem] {
        // Show all extraction items (they aren't place-scoped in the DB) when a place is selected.
        // We also include structured todos.
        var items: [SpaceTaskItem] = []

        for item in appState.extractionItems where item.isAccepted {
            items.append(SpaceTaskItem(
                id: item.id,
                title: item.content,
                type: item.type == .todo ? "todo" : "fact",
                status: item.applied ? "applied" : "pending",
                priority: item.priority,
                bucket: item.bucket.displayName,
                timestamp: item.timestamp
            ))
        }

        for todo in appState.structuredTodos {
            let projectName = appState.projects.first(where: { $0.id == todo.projectID })?.name
            items.append(SpaceTaskItem(
                id: todo.id,
                title: todo.content,
                type: "structured_todo",
                status: todo.isExecuted ? "executed" : (todo.priority ?? "pending"),
                priority: todo.priority,
                bucket: projectName ?? "General",
                timestamp: todo.createdAt
            ))
        }

        return items.sorted { $0.timestamp > $1.timestamp }
    }

    /// People from appState.people, filtered to those seen at the selected place
    /// (via session_people linkage) plus always including "You".
    private var peopleAtPlace: [Person] {
        let namesAtPlace = Set(placePeopleNames[selectedPlaceID] ?? [])
        // Always include "You" (isMe), and any person whose name was seen at this place
        return appState.people.filter { person in
            person.isMe || namesAtPlace.contains(person.name)
        }
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
        Group {
            if places.isEmpty {
                emptyPlacesState
            } else {
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
        }
        .onAppear { loadData() }
    }

    // MARK: - Data Loading

    private func loadData() {
        // 1. Load places from SessionStore
        let placeRecords = sessionStore.allPlaces()
        let now = Date()
        let calendar = Calendar.current

        // Also include current location if it has a name but may not be in the places table yet
        var builtPlaces: [PlaceDetail] = []
        var builtActivities: [String: [PlaceActivity]] = [:]
        var builtPeopleNames: [String: [String]] = [:]

        for record in placeRecords {
            let sessions = sessionStore.sessions(forPlaceID: record.id)
            let activityCount = sessions.count
            let icon = placeIcon(for: record.name)
            let address = record.wifiSSID == record.name ? "" : "WiFi: \(record.wifiSSID)"

            // Gather people names seen at this place
            let pNames = sessionStore.peopleNames(forPlaceID: record.id)
            builtPeopleNames[record.id] = pNames

            // Compute peopleIDs for the card badge — map matched names to appState person IDs
            let matchedPeopleIDs: [String] = appState.people.compactMap { person in
                if person.isMe { return person.id.uuidString }
                if pNames.contains(person.name) { return person.id.uuidString }
                return nil
            }

            builtPlaces.append(PlaceDetail(
                id: record.id,
                name: record.name,
                icon: icon,
                address: address,
                peopleIDs: matchedPeopleIDs,
                activityCount: activityCount
            ))

            // Build activities from sessions
            var placeActivities: [PlaceActivity] = []

            for session in sessions {
                let dayOffset = calendar.dateComponents([.day], from: calendar.startOfDay(for: session.startedAt), to: calendar.startOfDay(for: now)).day ?? 0

                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "h:mm a"
                let timeStr = timeFormatter.string(from: session.startedAt)

                // Session arrival activity
                placeActivities.append(PlaceActivity(
                    time: timeStr,
                    dayOffset: dayOffset,
                    personID: "you",
                    text: session.endedAt != nil
                        ? "Session at \(record.name)"
                        : "Arrived at \(record.name)",
                    type: .location,
                    project: nil
                ))

                // If there's a transcript snippet, add it as a transcript activity
                if !session.transcriptSnippet.isEmpty {
                    let snippetText = session.transcriptSnippet.count > 120
                        ? String(session.transcriptSnippet.prefix(120)) + "..."
                        : session.transcriptSnippet

                    // Find speaker from the transcript records for this session
                    let sessionTranscripts = appState.recentTranscripts().filter { $0.sessionID == session.id }
                    let speakerName = sessionTranscripts.first?.speakerName ?? "You"
                    let personID = appState.people.first(where: { $0.name == speakerName })?.id.uuidString ?? "you"

                    // Find project name if any transcript has a project
                    let projectName: String? = sessionTranscripts.compactMap { tr in
                        guard let pid = tr.projectID else { return nil }
                        return appState.projects.first(where: { $0.id == pid.uuidString })?.name
                    }.first

                    placeActivities.append(PlaceActivity(
                        time: timeStr,
                        dayOffset: dayOffset,
                        personID: personID,
                        text: snippetText,
                        type: .transcript,
                        project: projectName
                    ))
                }
            }

            // Sort activities: most recent first within each day, days ascending
            placeActivities.sort { a, b in
                if a.dayOffset != b.dayOffset { return a.dayOffset < b.dayOffset }
                return a.time > b.time
            }

            builtActivities[record.id] = placeActivities
        }

        // Also add recent transcripts as activities (not session-linked ones)
        // to enrich places where we might have transcripts but no explicit session link
        let recentTranscripts = appState.recentTranscripts()
        for transcript in recentTranscripts where transcript.sessionID == nil {
            let dayOffset = calendar.dateComponents([.day], from: calendar.startOfDay(for: transcript.timestamp), to: calendar.startOfDay(for: now)).day ?? 0
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "h:mm a"
            let timeStr = timeFormatter.string(from: transcript.timestamp)
            let speakerName = transcript.speakerName ?? "You"
            let personID = appState.people.first(where: { $0.name == speakerName })?.id.uuidString ?? "you"
            let projectName: String? = transcript.projectID.flatMap { pid in
                appState.projects.first(where: { $0.id == pid.uuidString })?.name
            }
            let snippetText = transcript.text.count > 120
                ? String(transcript.text.prefix(120)) + "..."
                : transcript.text

            // Assign to "current location" place if no session link
            if let currentPlace = builtPlaces.first(where: { $0.name == appState.locationName }) {
                var existing = builtActivities[currentPlace.id] ?? []
                existing.append(PlaceActivity(
                    time: timeStr,
                    dayOffset: dayOffset,
                    personID: personID,
                    text: snippetText,
                    type: .transcript,
                    project: projectName
                ))
                builtActivities[currentPlace.id] = existing
            }
        }

        // Update state
        places = builtPlaces
        allActivities = builtActivities
        placePeopleNames = builtPeopleNames

        // Auto-select: current place, or first place
        if let currentPlace = builtPlaces.first(where: { $0.name == appState.locationName }) {
            selectedPlaceID = currentPlace.id
        } else if let first = builtPlaces.first {
            selectedPlaceID = first.id
        }
    }

    /// Pick an appropriate icon based on common place name patterns.
    private func placeIcon(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("home") || lower.contains("apartment") || lower.contains("flat") { return "\u{1F3E0}" }
        if lower.contains("office") || lower.contains("work") || lower.contains("wework") || lower.contains("cowork") { return "\u{1F3E2}" }
        if lower.contains("cafe") || lower.contains("caf\u{00E9}") || lower.contains("coffee") || lower.contains("starbucks") { return "\u{2615}" }
        if lower.contains("gym") || lower.contains("fitness") || lower.contains("cult") { return "\u{1F4AA}" }
        if lower.contains("school") || lower.contains("university") || lower.contains("college") || lower.contains("campus") { return "\u{1F393}" }
        if lower.contains("library") { return "\u{1F4DA}" }
        if lower.contains("restaurant") || lower.contains("food") || lower.contains("dining") { return "\u{1F37D}" }
        if lower.contains("airport") || lower.contains("terminal") { return "\u{2708}\u{FE0F}" }
        if lower.contains("hotel") || lower.contains("hostel") { return "\u{1F3E8}" }
        if lower.contains("hospital") || lower.contains("clinic") { return "\u{1F3E5}" }
        if lower.contains("mobile") || lower.contains("hotspot") { return "\u{1F4F1}" }
        return "\u{1F4CD}" // default pin
    }

    // MARK: - Empty State

    private var emptyPlacesState: some View {
        let theme = ThemeManager.shared.current
        return VStack(spacing: 16) {
            Spacer()
            Text("\u{1F30D}")
                .font(.system(size: 40))
            Text("No places detected yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.textPrimary)
            Text("AutoClawd learns your places from WiFi networks as you move around.")
                .font(.system(size: 11))
                .foregroundColor(theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

            if people.isEmpty {
                Text("No people detected at this place yet")
                    .font(.system(size: 11))
                    .foregroundColor(theme.textTertiary)
                    .padding(.vertical, 8)
            } else {
                // Wrapping HStack of person cards
                FlowLayout(spacing: 6) {
                    ForEach(people) { person in
                        personCard(person: person)
                    }
                }
            }
        }
    }

    private func personCard(person: Person) -> some View {
        let theme = ThemeManager.shared.current
        return HStack(spacing: 6) {
            Circle()
                .fill(person.color)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(person.name)
                    .font(.system(size: 11))
                    .foregroundColor(theme.textPrimary)

                if person.isMe {
                    Text("You")
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
                .offset(x: -22.5) // Center on the timeline line

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
        // Resolve person name from appState.people or fall back to personID
        let personName: String = {
            if let uuid = UUID(uuidString: activity.personID),
               let person = appState.people.first(where: { $0.id == uuid }) {
                return person.name
            }
            // Fallback: check by name match or use raw ID
            return appState.people.first(where: { $0.name.lowercased() == activity.personID.lowercased() })?.name
                ?? (activity.personID == "you" ? "You" : activity.personID)
        }()

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
            Text("TASKS & EXTRACTIONS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundColor(theme.textSecondary)

            ForEach(tasksForPlace, id: \.id) { task in
                taskCard(task: task)
            }
        }
    }

    private func taskCard(task: SpaceTaskItem) -> some View {
        let theme = ThemeManager.shared.current
        let statusColor: Color = {
            switch task.status {
            case "applied", "executed": return theme.accent
            case "HIGH":                return theme.error
            case "MEDIUM":              return theme.warning
            case "LOW":                 return theme.textTertiary
            default:                    return theme.secondary
            }
        }()

        return HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(task.title)
                .font(.system(size: 10))
                .foregroundColor(theme.textPrimary)
                .lineLimit(2)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                TagView(type: .project, label: task.bucket, small: true)
                TagView(type: .status, label: task.status, small: true)
            }
        }
        .padding(10)
        .glassCard(cornerRadius: 8)
    }
}

// MARK: - SpaceTaskItem (lightweight model for task display)

private struct SpaceTaskItem: Identifiable {
    let id: String
    let title: String
    let type: String       // "todo", "fact", "structured_todo"
    let status: String
    let priority: String?
    let bucket: String
    let timestamp: Date
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
