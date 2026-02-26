# UI Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> Before starting: use superpowers:using-git-worktrees to create an isolated workspace.

**Goal:** Replace the BrutalistTheme dark UI with a white/black/green/cyan light-mode design, consolidate 10 sidebar tabs into 3 (World · Intelligence · Settings), and build the World calendar view.

**Architecture:** New `AppTheme` enum replaces `BrutalistTheme` everywhere. `PanelTab` shrinks to 3 cases. `WorldView.swift` is a new file combining Todos, Transcripts, Timeline, AI Search. `IntelligenceView` gains sub-tabs absorbing WorldModel + Logs. A new `SettingsConsolidatedView` absorbs Projects, Profile, HotWords, HotKeys, Transcription.

**Tech Stack:** Swift 5.9 · SwiftUI · AppKit · SQLite · `make` build (no Xcode — build command is `make` from repo root). No XCTest — verification = clean `make` build + visual run.

**Design reference:** `docs/plans/2026-02-27-ui-redesign-design.md`

---

### Task 1: Create AppTheme.swift (replaces BrutalistTheme)

**Files:**
- Create: `Sources/AppTheme.swift`
- Keep (do not delete yet): `Sources/BrutalistTheme.swift` — deleted in Task 6

**Step 1: Create the file**

```swift
// Sources/AppTheme.swift
import SwiftUI

// MARK: - App Design Tokens

enum AppTheme {
    // MARK: Colors
    static let background    = Color(hex: "#FFFFFF")
    static let surface       = Color(hex: "#F7F7F7")
    static let surfaceHover  = Color(hex: "#EBEBEB")
    static let textPrimary   = Color(hex: "#0A0A0A")
    static let textSecondary = Color(hex: "#6B6B6B")
    static let green         = Color(hex: "#16C172")
    static let cyan          = Color(hex: "#06B6D4")
    static let border        = Color(hex: "#E4E4E4")
    static let destructive   = Color(hex: "#EF4444")

    // MARK: Typography (font TBD — using system for now)
    static let caption  = Font.system(size: 11, weight: .regular)
    static let body     = Font.system(size: 13, weight: .regular)
    static let label    = Font.system(size: 13, weight: .medium)
    static let heading  = Font.system(size: 15, weight: .semibold)
    static let title    = Font.system(size: 18, weight: .bold)
    static let mono     = Font.system(size: 12, design: .monospaced)

    // MARK: Spacing (8px grid)
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 24
    static let xxl: CGFloat = 32

    // MARK: Geometry
    static let cornerRadius:        CGFloat = 6
    static let sidebarWidth:        CGFloat = 52
    static let selectedAccentWidth: CGFloat = 3
}

// MARK: - Color Hex Init

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >>  8) & 0xFF) / 255
        let b = Double( int        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.label)
            .foregroundColor(.white)
            .padding(.horizontal, AppTheme.md)
            .padding(.vertical, AppTheme.sm)
            .background(AppTheme.textPrimary.opacity(configuration.isPressed ? 0.75 : 1))
            .cornerRadius(AppTheme.cornerRadius)
    }
}

struct RunButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.label)
            .foregroundColor(AppTheme.textPrimary)
            .padding(.horizontal, AppTheme.md)
            .padding(.vertical, AppTheme.sm)
            .background(AppTheme.green.opacity(configuration.isPressed ? 0.75 : 1))
            .cornerRadius(AppTheme.cornerRadius)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.label)
            .foregroundColor(AppTheme.textPrimary)
            .padding(.horizontal, AppTheme.md)
            .padding(.vertical, AppTheme.sm)
            .background(Color.white)
            .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                        .stroke(AppTheme.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.label)
            .foregroundColor(AppTheme.destructive)
            .padding(.horizontal, AppTheme.md)
            .padding(.vertical, AppTheme.sm)
            .background(Color.white)
            .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                        .stroke(AppTheme.destructive, lineWidth: 1))
    }
}
```

**Step 2: Build**

```bash
make
```
Expected: `Built build/AutoClawd.app` — 0 errors.

**Step 3: Commit**

```bash
git add Sources/AppTheme.swift
git commit -m "feat: add AppTheme design tokens (white/green/cyan, button styles)"
```

---

### Task 2: Redesign MainPanelView sidebar (3 icons, 52px, light theme)

**Files:**
- Modify: `Sources/MainPanelView.swift` — `PanelTab` enum + sidebar + window frame + background

**Step 1: Replace PanelTab enum** (lines 6–34)

Replace the entire `PanelTab` enum with:

```swift
enum PanelTab: String, CaseIterable, Identifiable {
    case world        = "World"
    case intelligence = "Intelligence"
    case settings     = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .world:        return "globe"
        case .intelligence: return "brain.head.profile"
        case .settings:     return "gearshape"
        }
    }
}
```

**Step 2: Redesign `MainPanelView.body`**

Replace the `body` computed property (lines 43–56):

```swift
var body: some View {
    HStack(spacing: 0) {
        sidebar
        Divider()
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background)
    }
    .frame(minWidth: 700, minHeight: 500)
    .background(AppTheme.background)
}
```

Note: WiFi banner moved into WorldView header in Task 3.

**Step 3: Replace sidebar** (lines 60–118)

```swift
private var sidebar: some View {
    VStack(spacing: 0) {
        Spacer().frame(height: AppTheme.xl)

        ForEach(PanelTab.allCases) { tab in
            Button { selectedTab = tab } label: {
                ZStack(alignment: .leading) {
                    if selectedTab == tab {
                        Rectangle()
                            .fill(AppTheme.green)
                            .frame(width: AppTheme.selectedAccentWidth)
                    }
                    Image(systemName: tab.icon)
                        .font(.system(size: 18, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundColor(selectedTab == tab ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: 44)
                .background(selectedTab == tab ? AppTheme.surfaceHover : Color.clear)
            }
            .buttonStyle(.plain)
            .help(tab.rawValue)
        }

        Spacer()

        // Status dot
        statusDot
            .padding(.bottom, AppTheme.xl)
    }
    .frame(width: AppTheme.sidebarWidth)
    .background(AppTheme.surface)
}
```

**Step 4: Replace `statusDot`** (lines 125–129)

```swift
private var statusDot: some View {
    Circle()
        .fill(appState.isListening ? AppTheme.green : AppTheme.textSecondary.opacity(0.4))
        .frame(width: 8, height: 8)
}
```

**Step 5: Replace `content` router** (lines 133–147)

```swift
@ViewBuilder
private var content: some View {
    switch selectedTab {
    case .world:        WorldView(appState: appState)
    case .intelligence: IntelligenceConsolidatedView(appState: appState)
    case .settings:     SettingsConsolidatedView(appState: appState)
    }
}
```

Note: `WorldView`, `IntelligenceConsolidatedView`, `SettingsConsolidatedView` are stub files created in the next step to keep the build green.

**Step 6: Remove `wifiLabelBanner`** — delete lines 151–184. The wifi banner will be inlined into `WorldView` in Task 3.

**Step 7: Add `TabHeader` stub if still referenced** — search for `TabHeader` usage, replace any remaining instances with a simple `HStack` + `Text` pattern as they appear in later tasks.

**Step 8: Build**

```bash
make
```
Expected: `Built build/AutoClawd.app` — 0 errors.

**Step 9: Commit**

```bash
git add Sources/MainPanelView.swift
git commit -m "refactor: consolidate PanelTab to 3 tabs, redesign sidebar with AppTheme"
```

---

### Task 3: Create stub views (WorldView, IntelligenceConsolidatedView, SettingsConsolidatedView)

These stubs let the build stay green across Tasks 4–6 while each view is built out.

**Files:**
- Create: `Sources/WorldView.swift`
- Create: `Sources/IntelligenceConsolidatedView.swift`
- Create: `Sources/SettingsConsolidatedView.swift`

**Step 1: Create WorldView.swift stub**

```swift
// Sources/WorldView.swift
import SwiftUI

struct WorldView: View {
    @ObservedObject var appState: AppState
    var body: some View {
        VStack {
            Text("World")
                .font(AppTheme.title)
                .foregroundColor(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }
}
```

**Step 2: Create IntelligenceConsolidatedView.swift stub**

```swift
// Sources/IntelligenceConsolidatedView.swift
import SwiftUI

struct IntelligenceConsolidatedView: View {
    @ObservedObject var appState: AppState
    var body: some View {
        VStack {
            Text("Intelligence")
                .font(AppTheme.title)
                .foregroundColor(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }
}
```

**Step 3: Create SettingsConsolidatedView.swift stub**

```swift
// Sources/SettingsConsolidatedView.swift
import SwiftUI

struct SettingsConsolidatedView: View {
    @ObservedObject var appState: AppState
    var body: some View {
        VStack {
            Text("Settings")
                .font(AppTheme.title)
                .foregroundColor(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }
}
```

**Step 4: Build**

```bash
make
```
Expected: `Built build/AutoClawd.app` — 0 errors.

**Step 5: Commit**

```bash
git add Sources/WorldView.swift Sources/IntelligenceConsolidatedView.swift Sources/SettingsConsolidatedView.swift
git commit -m "feat: add stub views for World, Intelligence, Settings tabs"
```

---

### Task 4: Build WorldView (calendar + unscheduled list + search)

**Files:**
- Modify: `Sources/WorldView.swift` — full implementation

**Context:** `appState.recentTranscripts()` returns `[TranscriptRecord]`. `appState.structuredTodos` is `[StructuredTodo]`. `appState.pendingUnknownSSID` drives the wifi banner.

**Step 1: Replace WorldView.swift with full implementation**

```swift
// Sources/WorldView.swift
import SwiftUI

// MARK: - Sub-tab

enum WorldSubTab: String, CaseIterable {
    case past   = "Past"
    case today  = "Today"
    case future = "Future"
}

// MARK: - WorldView

struct WorldView: View {
    @ObservedObject var appState: AppState
    @State private var subTab: WorldSubTab = .today
    @State private var displayMonth: Date = Date()
    @State private var selectedDate: Date? = nil
    @State private var transcripts: [TranscriptRecord] = []
    @State private var searchQuery: String = ""

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 0) {
            // Wifi banner (moved here from MainPanelView)
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
                    ForEach(WorldSubTab.allCases, id: \.self) { t in
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

            Divider()

            // Unscheduled todos
            unscheduledSection

            Divider()

            // Search bar
            searchBar
        }
        .background(AppTheme.background)
        .onAppear { loadTranscripts() }
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
            ForEach(weeks, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { date in
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
        let startPad = weekday

        var days: [Date] = []
        for i in stride(from: -startPad, through: 0, by: 1) {
            if let d = calendar.date(byAdding: .day, value: i, to: monthStart) { days.append(d) }
        }
        var cur = monthStart
        while cur <= monthEnd {
            days.append(cur)
            cur = calendar.date(byAdding: .day, value: 1, to: cur) ?? cur
        }
        // Pad to complete last row
        while days.count % 7 != 0 {
            if let last = days.last, let d = calendar.date(byAdding: .day, value: 1, to: last) { days.append(d) }
        }

        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0+7, days.count)]) }
    }

    private func hasTodo(on date: Date) -> Bool {
        appState.structuredTodos.contains { todo in
            todo.isExecuted && calendar.isDate(date, inSameDayAs: Date())
        }
    }

    private func hasTranscript(on date: Date) -> Bool {
        transcripts.contains { calendar.isDate($0.timestamp, inSameDayAs: date) }
    }

    // MARK: - Unscheduled Section

    private var unscheduledSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("UNSCHEDULED")
                    .font(AppTheme.caption)
                    .foregroundColor(AppTheme.textSecondary)
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
                Text("No unscheduled todos.")
                    .font(AppTheme.body)
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.horizontal, AppTheme.lg)
                    .padding(.vertical, AppTheme.sm)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(unscheduledTodos) { todo in
                            UnscheduledTodoRow(todo: todo, appState: appState)
                            Divider().padding(.leading, AppTheme.lg)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
    }

    private var unscheduledTodos: [StructuredTodo] {
        appState.structuredTodos.filter { !$0.isExecuted }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: AppTheme.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppTheme.textSecondary)
                .font(.system(size: 13))
            TextField("Search transcripts, todos, world model…", text: $searchQuery)
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
            Text("You're on '\(ssid)' — what should I call this place?")
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
                .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.border))
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
                        isCurrentMonth ? AppTheme.textPrimary : AppTheme.textSecondary.opacity(0.4)
                    )
                    .frame(width: 28, height: 28)
                    .background(
                        isToday ? AppTheme.textPrimary :
                        isSelected ? AppTheme.surface : Color.clear,
                        in: Circle()
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

    private var projectName: String {
        appState.projects.first(where: { $0.id == todo.projectID })?.name ?? "—"
    }

    var body: some View {
        HStack(spacing: AppTheme.md) {
            priorityDot
            Text(todo.content)
                .font(AppTheme.body)
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(projectName)
                .font(AppTheme.caption)
                .foregroundColor(AppTheme.textSecondary)
            if ClaudeCodeRunner.cliURL != nil {
                Button("Run") { /* handled by StructuredTodoRow in Todo list */ }
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
```

**Step 2: Build**

```bash
make
```
Expected: `Built build/AutoClawd.app` — 0 errors.

**Step 3: Commit**

```bash
git add Sources/WorldView.swift
git commit -m "feat: build WorldView — calendar grid, unscheduled todos, search bar"
```

---

### Task 5: Build IntelligenceConsolidatedView (Extractions + World Model + Logs)

**Files:**
- Modify: `Sources/IntelligenceConsolidatedView.swift`

**Step 1: Replace with full implementation**

```swift
// Sources/IntelligenceConsolidatedView.swift
import SwiftUI

enum IntelligenceSubTab: String, CaseIterable {
    case extractions = "Extractions"
    case worldModel  = "World Model"
    case logs        = "Logs"
}

struct IntelligenceConsolidatedView: View {
    @ObservedObject var appState: AppState
    @State private var subTab: IntelligenceSubTab = .extractions
    @State private var expandedChunk: Int? = nil
    @State private var worldModelContent: String = ""
    @State private var logContent: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Sub-tab header
            HStack(spacing: AppTheme.xl) {
                ForEach(IntelligenceSubTab.allCases, id: \.self) { tab in
                    Button { subTab = tab } label: {
                        VStack(spacing: AppTheme.xs) {
                            Text(tab.rawValue)
                                .font(subTab == tab ? AppTheme.label : AppTheme.body)
                                .foregroundColor(subTab == tab ? AppTheme.textPrimary : AppTheme.textSecondary)
                            Rectangle()
                                .fill(subTab == tab ? AppTheme.green : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()

                // Context-sensitive actions
                if subTab == .extractions {
                    extractionActions
                }
            }
            .padding(.horizontal, AppTheme.lg)
            .padding(.top, AppTheme.md)

            Divider()

            // Content
            switch subTab {
            case .extractions: extractionsContent
            case .worldModel:  worldModelContent_view
            case .logs:        logsContent
            }
        }
        .background(AppTheme.background)
        .onAppear {
            appState.refreshExtractionItems()
            let grouped = Dictionary(grouping: appState.extractionItems, by: \.chunkIndex)
            expandedChunk = grouped.keys.max()
            worldModelContent = appState.worldModelContent
            loadLogs()
        }
    }

    // MARK: - Extractions

    private var extractionActions: some View {
        HStack(spacing: AppTheme.sm) {
            Picker("", selection: $appState.synthesizeThreshold) {
                Text("Manual").tag(0)
                Text("Auto: 5").tag(5)
                Text("Auto: 10").tag(10)
                Text("Auto: 20").tag(20)
            }
            .pickerStyle(.menu)
            .frame(width: 90)
            Button("Synthesize Now") { Task { await appState.synthesizeNow() } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(appState.pendingExtractionCount == 0)
            Button("Clean Up") { Task { await appState.cleanupNow() } }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(appState.isCleaningUp)
        }
    }

    @ViewBuilder
    private var extractionsContent: some View {
        let grouped = Dictionary(grouping: appState.extractionItems, by: \.chunkIndex)
        let sortedChunks = grouped.keys.sorted(by: >)

        if sortedChunks.isEmpty {
            emptyState(icon: "brain", message: "No extraction items yet")
        } else {
            List(sortedChunks, id: \.self) { chunkIdx in
                let items = grouped[chunkIdx] ?? []
                ChunkGroupView(
                    chunkIndex: chunkIdx,
                    items: items,
                    isExpanded: expandedChunk == chunkIdx,
                    onToggle: { expandedChunk = expandedChunk == chunkIdx ? nil : chunkIdx },
                    onToggleItem: { appState.toggleExtraction(id: $0) },
                    onSetBucket: { appState.setExtractionBucket(id: $0, bucket: $1) }
                )
            }
            .listStyle(.plain)
        }
    }

    // MARK: - World Model

    private var worldModelContent_view: some View {
        TextEditor(text: $worldModelContent)
            .font(AppTheme.mono)
            .foregroundColor(AppTheme.textPrimary)
            .padding(AppTheme.lg)
            .onChange(of: worldModelContent) { appState.saveWorldModel($0) }
    }

    // MARK: - Logs

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
        let logURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("autoclawd/autoclawd.log")
        logContent = (try? String(contentsOf: logURL ?? URL(fileURLWithPath: "/dev/null"))) ?? ""
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
    }
}
```

**Step 2: Build**

```bash
make
```
Expected: `Built build/AutoClawd.app` — 0 errors.

**Step 3: Commit**

```bash
git add Sources/IntelligenceConsolidatedView.swift
git commit -m "feat: IntelligenceConsolidatedView with Extractions/WorldModel/Logs sub-tabs"
```

---

### Task 6: Build SettingsConsolidatedView (Projects + Hot Words + Hot Keys + Transcription)

**Files:**
- Modify: `Sources/SettingsConsolidatedView.swift`

**Step 1: Replace with full implementation**

```swift
// Sources/SettingsConsolidatedView.swift
import SwiftUI

struct SettingsConsolidatedView: View {
    @ObservedObject var appState: AppState
    @State private var groqKey      = SettingsManager.shared.groqAPIKey
    @State private var anthropicKey = SettingsManager.shared.anthropicAPIKey
    @State private var isValidating = false
    @State private var validationResult: Bool? = nil
    @State private var showAddHotWord = false
    @State private var localHotWordConfigs: [HotWordConfig] = SettingsManager.shared.hotWordConfigs
    @State private var showAddProject = false
    @State private var newProjectName = ""
    @State private var newProjectPath = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.xxl) {
                sectionHeader("Projects")
                projectsSection

                Divider()
                sectionHeader("Hot Words")
                hotWordsSection

                Divider()
                sectionHeader("Transcription")
                transcriptionSection

                Divider()
                sectionHeader("API Keys")
                apiKeysSection

                Divider()
                sectionHeader("Display")
                displaySection

                Divider()
                sectionHeader("Microphone & Audio")
                audioSection

                Divider()
                sectionHeader("Data")
                dataSection
            }
            .padding(AppTheme.xl)
        }
        .background(AppTheme.background)
        .sheet(isPresented: $showAddHotWord) {
            AddHotWordSheet(isPresented: $showAddHotWord) { config in
                localHotWordConfigs.append(config)
                SettingsManager.shared.hotWordConfigs = localHotWordConfigs
            }
        }
        .sheet(isPresented: $showAddProject) {
            AddProjectSheet(isPresented: $showAddProject) { name, path in
                appState.addProject(name: name, path: path)
            }
        }
    }

    // MARK: - Projects

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.sm) {
            ForEach(appState.projects) { project in
                HStack(spacing: AppTheme.md) {
                    VStack(alignment: .leading, spacing: AppTheme.xs) {
                        Text(project.name)
                            .font(AppTheme.label)
                            .foregroundColor(AppTheme.textPrimary)
                        Text(project.localPath)
                            .font(AppTheme.caption)
                            .foregroundColor(AppTheme.textSecondary)
                            .lineLimit(1)
                        if !project.tags.isEmpty {
                            HStack(spacing: AppTheme.xs) {
                                ForEach(project.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(AppTheme.caption)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, AppTheme.sm)
                                        .padding(.vertical, 2)
                                        .background(AppTheme.green)
                                        .cornerRadius(AppTheme.xs)
                                }
                            }
                        }
                    }
                    Spacer()
                    Button { appState.deleteProject(id: project.id) } label: {
                        Image(systemName: "trash")
                            .foregroundColor(AppTheme.destructive)
                    }
                    .buttonStyle(.plain)
                }
                .padding(AppTheme.md)
                .background(AppTheme.surface)
                .cornerRadius(AppTheme.cornerRadius)
            }

            Button("+ Add Project") { showAddProject = true }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    // MARK: - Hot Words

    private var hotWordsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.sm) {
            ForEach(localHotWordConfigs) { config in
                HStack(spacing: AppTheme.md) {
                    VStack(alignment: .leading, spacing: AppTheme.xs) {
                        HStack(spacing: AppTheme.sm) {
                            Text("hot \(config.keyword)")
                                .font(AppTheme.mono)
                                .foregroundColor(AppTheme.green)
                            Text("→ \(config.action.displayName)")
                                .font(AppTheme.caption)
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                    Spacer()
                    Button {
                        localHotWordConfigs.removeAll { $0.id == config.id }
                        SettingsManager.shared.hotWordConfigs = localHotWordConfigs
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(AppTheme.md)
                .background(AppTheme.surface)
                .cornerRadius(AppTheme.cornerRadius)
            }

            if localHotWordConfigs.isEmpty {
                Text("No hot words configured. Use pattern: hot <keyword> for project <number> <task>")
                    .font(AppTheme.caption)
                    .foregroundColor(AppTheme.textSecondary)
            }

            Button("+ Add Hot Word") { showAddHotWord = true }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    // MARK: - Transcription

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.md) {
            Picker("Mode", selection: $appState.transcriptionMode) {
                ForEach(TranscriptionMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
        }
    }

    // MARK: - API Keys

    private var apiKeysSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.md) {
            settingsField(label: "Anthropic API Key", placeholder: "sk-ant-...") {
                SecureField("sk-ant-...", text: $anthropicKey)
                    .onChange(of: anthropicKey) { SettingsManager.shared.anthropicAPIKey = $0 }
            }
            if appState.transcriptionMode == .groq {
                HStack(spacing: AppTheme.sm) {
                    settingsField(label: "Groq API Key", placeholder: "gsk_...") {
                        SecureField("gsk_...", text: $groqKey)
                            .onChange(of: groqKey) { SettingsManager.shared.groqAPIKey = $0 }
                    }
                    Button(isValidating ? "…" : "Validate") { validateGroq() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(isValidating || groqKey.isEmpty)
                    if let result = validationResult {
                        Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(result ? AppTheme.green : AppTheme.destructive)
                    }
                }
            }
        }
    }

    // MARK: - Display

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.md) {
            Toggle("Show Ambient Widget", isOn: $appState.showAmbientWidget)
                .font(AppTheme.body)
            VStack(alignment: .leading, spacing: AppTheme.xs) {
                Text("Pill Appearance")
                    .font(AppTheme.caption)
                    .foregroundColor(AppTheme.textSecondary)
                Picker("", selection: $appState.appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
            }
        }
    }

    // MARK: - Audio

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.md) {
            Toggle("Always-on listening", isOn: $appState.micEnabled)
                .font(AppTheme.body)
            HStack {
                Text("Delete audio after")
                    .font(AppTheme.body)
                    .foregroundColor(AppTheme.textPrimary)
                Picker("", selection: $appState.audioRetentionDays) {
                    ForEach(AudioRetention.allCases, id: \.rawValue) { r in
                        Text(r.displayName).tag(r.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        HStack(spacing: AppTheme.md) {
            Button("Re-run Setup") { appState.showSetup() }
                .buttonStyle(SecondaryButtonStyle())
            Button("Export All") { appState.exportData() }
                .buttonStyle(SecondaryButtonStyle())
            Button("Delete All") { appState.confirmDeleteAll() }
                .buttonStyle(DestructiveButtonStyle())
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(AppTheme.caption)
            .foregroundColor(AppTheme.textSecondary)
            .kerning(0.8)
    }

    private func settingsField<Content: View>(label: String, placeholder: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.xs) {
            Text(label)
                .font(AppTheme.caption)
                .foregroundColor(AppTheme.textSecondary)
            content()
                .textFieldStyle(.roundedBorder)
        }
    }

    private func validateGroq() {
        isValidating = true
        validationResult = nil
        Task {
            do {
                let url = URL(string: "https://api.groq.com/openai/v1/models")!
                var req = URLRequest(url: url)
                req.setValue("Bearer \(groqKey)", forHTTPHeaderField: "Authorization")
                let (_, response) = try await URLSession.shared.data(for: req)
                await MainActor.run {
                    validationResult = (response as? HTTPURLResponse)?.statusCode == 200
                    isValidating = false
                }
            } catch {
                await MainActor.run { validationResult = false; isValidating = false }
            }
        }
    }
}
```

**Step 2: Check that `AddHotWordSheet` exists** — search for it:

```bash
grep -rn "AddHotWordSheet" Sources/
```

If missing, add a minimal stub inside `SettingsConsolidatedView.swift`:

```swift
struct AddHotWordSheet: View {
    @Binding var isPresented: Bool
    let onAdd: (HotWordConfig) -> Void
    @State private var keyword = ""
    @State private var action: HotWordAction = .addTodo

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.lg) {
            Text("Add Hot Word")
                .font(AppTheme.title)
            VStack(alignment: .leading, spacing: AppTheme.xs) {
                Text("Trigger keyword").font(AppTheme.caption).foregroundColor(AppTheme.textSecondary)
                TextField("e.g. p1", text: $keyword).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: AppTheme.xs) {
                Text("Action").font(AppTheme.caption).foregroundColor(AppTheme.textSecondary)
                Picker("", selection: $action) {
                    ForEach(HotWordAction.allCases, id: \.self) { a in Text(a.displayName).tag(a) }
                }
                .pickerStyle(.radioGroup)
            }
            HStack {
                Button("Cancel") { isPresented = false }.buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Add") {
                    guard !keyword.isEmpty else { return }
                    onAdd(HotWordConfig(keyword: keyword, action: action))
                    isPresented = false
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(keyword.isEmpty)
            }
        }
        .padding(AppTheme.xl)
        .frame(width: 360)
    }
}
```

**Step 3: Build**

```bash
make
```
Expected: `Built build/AutoClawd.app` — 0 errors. Fix any type errors before committing.

**Step 4: Commit**

```bash
git add Sources/SettingsConsolidatedView.swift
git commit -m "feat: SettingsConsolidatedView — projects, hot words, transcription, API keys"
```

---

### Task 7: Restyle PillView + ToastView + other files using BrutalistTheme

**Files:**
- Modify: `Sources/PillView.swift`
- Modify: `Sources/ToastView.swift`
- Modify: `Sources/SessionTimelineView.swift`
- Modify: `Sources/SetupView.swift`
- Modify: `Sources/WorldModelGraphView.swift`
- Modify: `Sources/UserProfileChatView.swift`
- Modify: `Sources/AmbientMapView.swift`
- Modify: `Sources/MapEditorView.swift`
- Delete: `Sources/BrutalistTheme.swift` (after all references removed)

**Step 1: Global find-replace in each file**

For each file, make these substitutions:
- `BrutalistTheme.neonGreen` → `AppTheme.green`
- `BrutalistTheme.monoSM` → `AppTheme.caption`
- `BrutalistTheme.monoMD` → `AppTheme.body`
- `BrutalistTheme.monoLG` → `AppTheme.heading`
- `BrutalistTheme.monoHeader` → `AppTheme.label`
- `BrutalistTheme.selectedBG` → `AppTheme.surfaceHover`
- `BrutalistTheme.divider` → `AppTheme.border`
- `Color.white.opacity(0.4)` → `AppTheme.textSecondary` (where used as text color)
- `.foregroundColor(.white.opacity(...))` → `.foregroundColor(AppTheme.textSecondary)`
- `.background(Color.black...)` → `.background(AppTheme.background)`
- Dark background fills → `AppTheme.background` or `AppTheme.surface`

**Step 2: PillView specific — update colors**

In `Sources/PillView.swift`:
- `BrutalistTheme.neonGreen` → `AppTheme.green`
- Keep existing pill shape/animation logic unchanged
- Background `.ultraThinMaterial` stays (pill floats over desktop, not over white background)
- Change `Color.white.opacity(...)` text to `AppTheme.textPrimary` where on light surface

**Step 3: Verify no remaining BrutalistTheme references**

```bash
grep -rn "BrutalistTheme" Sources/
```

Expected: no output.

**Step 4: Delete BrutalistTheme.swift**

```bash
rm Sources/BrutalistTheme.swift
```

**Step 5: Build**

```bash
make
```
Expected: `Built build/AutoClawd.app` — 0 errors. Fix any remaining references.

**Step 6: Commit**

```bash
git add -A
git commit -m "refactor: replace all BrutalistTheme refs with AppTheme, delete BrutalistTheme.swift"
```

---

### Task 8: Update README.md

**Files:**
- Modify: `README.md`

**Step 1: Update How It Works pipeline**

Replace the existing pipeline line with:

```
Mic → Transcription → LLM Extraction → World Model + Todos → AI Framing → Execution
```

Add hot-word shortcut path:

```
Hot Word Trigger → Project Detection → Todo Creation → AI Framing → Auto-execution
```

**Step 2: Update feature list in README**

Under a new **Features** section (or update the existing flow), add:

- **Hot-word detection** — Say `hot <keyword> for project <N> <task>` to instantly create and optionally auto-execute a todo
- **AI todo framing** — Raw speech payloads are cleaned into clear task titles using the project's README and CLAUDE.md as context (via Ollama, non-blocking)
- **Execute All** — Multi-select todos and run in parallel or series with live toast feedback
- **Transcript → Todo** — Any transcript row can be converted to a structured todo with one click, with project assignment
- **Per-project world model** — Each project has its own scoped read/write to the world model

**Step 3: Update Architecture diagram**

Add to the diagram:
```
│  HotWordDetector                                 │
│    pattern: "hot <keyword> for project <N> ..."  │
│    → StructuredTodoStore                         │
│                                                  │
│  TodoFramingService (Ollama)                     │
│    reads project README.md + CLAUDE.md           │
│    → cleans raw speech into task titles          │
```

**Step 4: Update Roadmap**

Tick off completed items:
- [x] Auto-project matching — link extracted todos to projects
- [x] Execution history and re-run support (partial)

Add new items:
- [ ] Scheduled todos — assign todos to specific times, show on World calendar
- [ ] Location/people tagging UI in World view
- [ ] Dark mode
- [ ] Custom font picker

**Step 5: Update Shortcuts table**

Add:
| `hot <kw> for project <N> <task>` | Create todo via voice hot-word |

**Step 6: Build (to ensure README changes don't break anything)**

```bash
make
```

**Step 7: Commit**

```bash
git add README.md
git commit -m "docs: update README with hot-words, AI framing, execute all, new architecture"
```

---

### Task 9: Final cleanup and MainPanelView TodoTab / TranscriptTab removal

**Files:**
- Modify: `Sources/MainPanelView.swift` — remove now-unused structs

**Step 1: Remove dead view structs from MainPanelView.swift**

These structs are now absorbed into WorldView / IntelligenceConsolidatedView / SettingsConsolidatedView and can be removed:
- `TodoTabView` — functionality moved to `WorldView.unscheduledSection` + existing ExecutionOutputView
- `WorldModelTabView` — absorbed into `IntelligenceConsolidatedView`
- `TranscriptTabView` / `TranscriptRowView` — absorbed into `WorldView`
- `ProjectsTabView` / `AddProjectSheet` — absorbed into `SettingsConsolidatedView`
- `SettingsTabView` — replaced by `SettingsConsolidatedView`
- `TabHeader` helper — no longer needed

Keep:
- `StructuredTodoRow` — still used by ExecutionOutputView and potentially WorldView
- `ExecutionOutputView` — still used as a sheet
- `AddProjectSheet` — still used by SettingsConsolidatedView (or move it there)
- `LogsTabView` if it exists separately

**Step 2: Build after each deletion** — delete one struct at a time and run `make` to catch any remaining dependencies.

**Step 3: Final build**

```bash
make
```
Expected: `Built build/AutoClawd.app` — 0 errors, 0 warnings about unused code.

**Step 4: Final commit**

```bash
git add Sources/MainPanelView.swift
git commit -m "refactor: remove dead view structs from MainPanelView after consolidation"
```

---

## Completion

After all 9 tasks pass build verification:

1. Launch the app: `build/AutoClawd.app/Contents/MacOS/AutoClawd`
2. Verify: white background, 3-icon sidebar, World calendar view loads
3. Invoke **superpowers:finishing-a-development-branch** to merge
