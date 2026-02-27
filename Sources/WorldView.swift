// Sources/WorldView.swift
import SwiftUI

// MARK: - Sub-tab (moved to MainPanelView.swift)

private enum LegacyWorldSubTab: String, CaseIterable {
    case past   = "Past"
    case today  = "Today"
    case future = "Future"
}

// MARK: - WorldView

struct WorldView: View {
    @ObservedObject var appState: AppState
    @State private var subTab: LegacyWorldSubTab = .today
    @State private var displayMonth: Date = Date()
    @State private var selectedDate: Date? = nil
    @State private var transcripts: [TranscriptRecord] = []
    @State private var searchQuery: String = ""
    @State private var runningTodo: StructuredTodo? = nil

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 0) {
            // Wifi banner
            if let ssid = appState.pendingUnknownSSID {
                wifiBanner(ssid: ssid)
                Divider()
            }

            // Top bar: month nav + sub-tab picker
            HStack(spacing: AppTheme.md) {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)

                Text(monthLabel)
                    .font(AppTheme.heading)
                    .foregroundColor(AppTheme.textPrimary)
                    .frame(minWidth: 120)

                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Picker("", selection: $subTab) {
                    ForEach(LegacyWorldSubTab.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .padding(.horizontal, AppTheme.lg)
            .padding(.vertical, AppTheme.md)

            Divider()

            // Calendar grid
            calendarGrid
                .padding(.horizontal, AppTheme.lg)
                .padding(.vertical, AppTheme.md)
                .layoutPriority(1)

            Divider()

            // Unscheduled todos
            unscheduledSection

            Divider()

            // Search bar
            searchBar
        }
        .background(AppTheme.background)
        .onAppear { loadTranscripts() }
        .sheet(item: $runningTodo) { todo in
            ExecutionOutputView(todo: todo, appState: appState)
        }
    }

    // MARK: - Month Label

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: displayMonth)
    }

    private func shiftMonth(_ delta: Int) {
        displayMonth = calendar.date(byAdding: .month, value: delta, to: displayMonth) ?? displayMonth
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        VStack(spacing: AppTheme.sm) {
            // Day-of-week headers
            HStack(spacing: 0) {
                ForEach(["Mon","Tue","Wed","Thu","Fri","Sat","Sun"], id: \.self) { d in
                    Text(d)
                        .font(AppTheme.caption)
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Weeks
            ForEach(weeks.indices, id: \.self) { wi in
                let week = weeks[wi]
                HStack(spacing: 0) {
                    ForEach(week.indices, id: \.self) { di in
                        let date = week[di]
                        DayCell(
                            date: date,
                            isCurrentMonth: calendar.isDate(date, equalTo: displayMonth, toGranularity: .month),
                            isToday: calendar.isDateInToday(date),
                            isSelected: selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false,
                            hasTodo: hasTodo(on: date),
                            hasTranscript: hasTranscript(on: date)
                        ) {
                            selectedDate = date
                        }
                    }
                }
            }
        }
    }

    // MARK: - Calendar Data

    private var weeks: [[Date]] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayMonth)),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)
        else { return [] }

        // Pad to Monday start
        var weekday = calendar.component(.weekday, from: monthStart)
        weekday = ((weekday - 2) + 7) % 7  // Monday = 0

        var days: [Date] = []
        for i in stride(from: -weekday, to: 0, by: 1) {
            if let d = calendar.date(byAdding: .day, value: i, to: monthStart) {
                days.append(d)
            }
        }
        var cur = monthStart
        while cur <= monthEnd {
            days.append(cur)
            if let next = calendar.date(byAdding: .day, value: 1, to: cur) {
                cur = next
            } else { break }
        }
        // Pad to complete last row
        while days.count % 7 != 0 {
            if let last = days.last, let d = calendar.date(byAdding: .day, value: 1, to: last) {
                days.append(d)
            } else { break }
        }

        return stride(from: 0, to: days.count, by: 7).map {
            Array(days[$0..<min($0 + 7, days.count)])
        }
    }

    private func hasTodo(on date: Date) -> Bool {
        let isToday = calendar.isDateInToday(date)
        return appState.structuredTodos.contains { todo in
            // Show dot on today for any active (unexecuted) todos
            // Show dot on past days only if they have executed todos (future: will use scheduledDate)
            if !todo.isExecuted {
                return isToday
            } else {
                return false // executed todos don't yet have a completion date stored — skip for now
            }
        }
    }

    private func hasTranscript(on date: Date) -> Bool {
        transcripts.contains { calendar.isDate($0.timestamp, inSameDayAs: date) }
    }

    // MARK: - Unscheduled Section

    private var unscheduledSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Unscheduled")
                    .font(AppTheme.label)
                    .foregroundColor(AppTheme.textPrimary)
                Text("\(unscheduledTodos.count)")
                    .font(AppTheme.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, AppTheme.xs)
                    .padding(.vertical, 2)
                    .background(AppTheme.textSecondary)
                    .cornerRadius(AppTheme.xs)
                Spacer()
            }
            .padding(.horizontal, AppTheme.lg)
            .padding(.vertical, AppTheme.sm)

            if unscheduledTodos.isEmpty {
                Text("All caught up — no unscheduled todos.")
                    .font(AppTheme.body)
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.horizontal, AppTheme.lg)
                    .padding(.vertical, AppTheme.sm)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(unscheduledTodos) { todo in
                            UnscheduledTodoRow(todo: todo, appState: appState) {
                                runningTodo = todo
                            }
                            Divider().padding(.leading, AppTheme.lg)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
    }

    private var unscheduledTodos: [StructuredTodo] {
        appState.structuredTodos.filter { !$0.isExecuted }
            .sorted { priorityRankWorld($0.priority) < priorityRankWorld($1.priority) }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: AppTheme.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppTheme.textSecondary)
                .font(.system(size: 13))
            TextField("Search transcripts, todos, world model\u{2026}", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(AppTheme.body)
                .foregroundColor(AppTheme.textPrimary)
        }
        .padding(.horizontal, AppTheme.lg)
        .padding(.vertical, AppTheme.md)
        .background(AppTheme.surface)
    }

    // MARK: - Wifi Banner

    private func wifiBanner(ssid: String) -> some View {
        HStack(spacing: AppTheme.sm) {
            Image(systemName: "wifi")
                .foregroundColor(AppTheme.cyan)
                .font(.system(size: 12))
            Text("You're on '\(ssid)' \u{2014} what should I call this place?")
                .font(AppTheme.caption)
                .foregroundColor(AppTheme.textPrimary)
            TextField("e.g. Home, Philz Coffee", text: $appState.wifiLabelInput)
                .textFieldStyle(.plain)
                .font(AppTheme.caption)
                .frame(maxWidth: 140)
                .padding(.horizontal, AppTheme.sm)
                .padding(.vertical, AppTheme.xs)
                .background(AppTheme.surface)
                .cornerRadius(AppTheme.cornerRadius)
                .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                            .stroke(AppTheme.border, lineWidth: 1))
            Button("Save") { appState.confirmWifiLabel() }
                .buttonStyle(PrimaryButtonStyle())
                .controlSize(.small)
            Button("Skip") {
                appState.pendingUnknownSSID = nil
                appState.wifiLabelInput = ""
            }
            .buttonStyle(SecondaryButtonStyle())
            .controlSize(.small)
        }
        .padding(.horizontal, AppTheme.lg)
        .padding(.vertical, AppTheme.sm)
        .background(AppTheme.background)
    }

    private func loadTranscripts() {
        transcripts = appState.recentTranscripts()
    }
}

// MARK: - Priority helper (local to WorldView)

private func priorityRankWorld(_ priority: String?) -> Int {
    switch priority {
    case "HIGH":   return 0
    case "MEDIUM": return 1
    case "LOW":    return 2
    default:       return 3
    }
}

// MARK: - DayCell

struct DayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let hasTodo: Bool
    let hasTranscript: Bool
    let onTap: () -> Void

    private var dayNumber: String {
        "\(Calendar.current.component(.day, from: date))"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(dayNumber)
                    .font(isToday ? AppTheme.label : AppTheme.body)
                    .foregroundColor(
                        isToday ? .white :
                        isSelected ? AppTheme.textPrimary :
                        isCurrentMonth ? AppTheme.textPrimary : AppTheme.textDisabled
                    )
                    .frame(width: 28, height: 28)
                    .background(
                        Group {
                            if isToday {
                                Circle().fill(AppTheme.textPrimary)
                            } else if isSelected {
                                Circle().fill(AppTheme.surface)
                            } else {
                                Circle().fill(Color.clear)
                            }
                        }
                    )

                HStack(spacing: 2) {
                    if hasTodo {
                        Circle().fill(AppTheme.green).frame(width: 4, height: 4)
                    }
                    if hasTranscript {
                        Circle().fill(AppTheme.cyan).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - UnscheduledTodoRow

struct UnscheduledTodoRow: View {
    let todo: StructuredTodo
    @ObservedObject var appState: AppState
    let onRun: () -> Void

    private var projectName: String {
        appState.projects.first(where: { $0.id == todo.projectID })?.name ?? "\u{2014}"
    }

    private var canRun: Bool { ClaudeCodeRunner.findCLI() != nil }

    var body: some View {
        HStack(spacing: AppTheme.md) {
            priorityDot
            Text(todo.content)
                .font(AppTheme.body)
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(projectName)
                .font(AppTheme.caption)
                .foregroundColor(AppTheme.textSecondary)
                .lineLimit(1)
            if canRun {
                Button("Run", action: onRun)
                    .buttonStyle(RunButtonStyle())
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, AppTheme.lg)
        .padding(.vertical, AppTheme.sm)
        .background(AppTheme.background)
        .contentShape(Rectangle())
    }

    private var priorityDot: some View {
        let color: Color = {
            switch todo.priority {
            case "HIGH":   return AppTheme.destructive
            case "MEDIUM": return Color.orange
            default:       return AppTheme.border
            }
        }()
        return Circle().fill(color).frame(width: 6, height: 6)
    }
}
