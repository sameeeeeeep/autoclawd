# UI Polish — Design Document
**Date:** 2026-02-27
**Branch:** claude/ui-polish

## Overview

Targeted fixes for contrast, readability, responsiveness, logs, and dark/light/system appearance modes. No layout redesign — surgical corrections only, to be followed by a Figma-driven full redesign.

---

## 1. Design Token Fixes (AppTheme.swift)

### Color corrections

| Token | Before | After | Reason |
|---|---|---|---|
| `textSecondary` | #6B6B6B | #525252 | Passes AA on both white and #F0F0F0 surface |
| `surface` | #F7F7F7 | #F0F0F0 | Distinguishable from white background |
| `surfaceHover` | #EBEBEB | #E5E5E5 | Consistent step with new surface |
| `border` | #E4E4E4 | #D4D4D4 | More visible on white background |
| ~~opacity abuse~~ | `.opacity(0.4)` | `textDisabled` token | Removes all uncontrolled opacity hacks |

### New token
```swift
static let textDisabled = Color.adaptive(light: .init(hex: "#B0B0B0"), dark: .init(hex: "#4A4A4A"))
```

### Dark mode — all tokens become adaptive via `Color.adaptive(light:dark:)`

```
background:   light #FFFFFF  / dark #0F0F0F
surface:      light #F0F0F0  / dark #1A1A1A
surfaceHover: light #E5E5E5  / dark #252525
textPrimary:  light #0A0A0A  / dark #F0F0F0
textSecondary:light #525252  / dark #A0A0A0
textDisabled: light #B0B0B0  / dark #4A4A4A
border:       light #D4D4D4  / dark #2E2E2E
green:        #16C172  (unchanged — works in both modes)
cyan:         #06B6D4  (unchanged — works in both modes)
destructive:  #EF4444  (unchanged)
```

### NSColor dynamic provider extension
```swift
extension Color {
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        }))
    }
}
```

### Typography fix
- `caption`: 11pt → 12pt minimum

---

## 2. Readability Fixes

### Sidebar (MainPanelView.swift)
- Add `Text(tab.rawValue)` label below each icon: `font(.system(size: 9, weight: .medium))`, `foregroundColor` matches icon color
- Sidebar width: 52 → 60px to accommodate label

### WorldView.swift
- `UnscheduledTodoRow` todo content: `lineLimit(1)` → `lineLimit(2)` with `.truncationMode(.tail)`
- Section header "UNSCHEDULED": `caption + textSecondary` → `label + textPrimary` (13pt medium)
- Replace `textSecondary.opacity(0.4)` for out-of-month day cells with `AppTheme.textDisabled`

### SettingsConsolidatedView.swift
- All `sectionHeader()` calls: currently render `caption + textSecondary` → change to `Font.system(size: 11, weight: .semibold)` + `textSecondary` with 1pt letter-spacing (standard macOS section header style)
- Project tags: `font(.system(size: 10, weight: .medium))` → 12pt
- `lineLimit(1)` on project paths → keep 1 line but ensure ellipsis in middle: `.truncationMode(.middle)`

---

## 3. Responsiveness Fixes

### WorldView.swift
- Remove `frame(maxHeight: 200)` on unscheduled scroll view
- Use `layoutPriority` to distribute space: calendar grid gets priority 1, unscheduled section gets priority 0 (takes remaining space up to a max)
- Cap unscheduled section with `.frame(maxHeight: 240)` relative to content, not hardcoded squeeze
- Calendar cell: cap `maxWidth` on `DayCell` to prevent ballooning on wide windows using `GeometryReader` or `.frame(maxWidth: 52)` per cell

### MainPanelView.swift
- `minWidth: 700` stays, but ensure content areas use `frame(maxWidth: .infinity)` correctly so they don't overflow at minimum width
- Button row clashing: wrap `extractionActions` in `HStack` with `fixedSize(horizontal: false, vertical: true)` to prevent clipping on narrow panel

---

## 4. Logs Fix (IntelligenceConsolidatedView.swift)

### Root cause
`loadLogs()` looks for `~/.autoclawd/autoclawd.log` but logger writes to `~/.autoclawd/logs/autoclawd-YYYY-MM-DD.log`.

### Fix
```swift
private func loadLogs() {
    // 1. Use in-memory snapshot for live entries
    let entries = AutoClawdLogger.shared.snapshot(limit: 500)
    if !entries.isEmpty {
        logEntries = entries
        return
    }
    // 2. Fallback: read today's log file
    let dateStr = todayDateString()
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".autoclawd/logs/autoclawd-\(dateStr).log")
    if let content = try? String(contentsOf: url, encoding: .utf8), !content.isEmpty {
        // Parse into entries for coloring — or display as plain text fallback
        logContent = content
    }
}
```

### Log line display
Replace plain `Text(logContent)` with a `LazyVStack` of per-entry rows:
- Each row shows: timestamp (mono, textDisabled), level badge (colored), component (textSecondary), message (textPrimary)
- Level colors: ERROR → destructive, WARN → orange, INFO → textSecondary, DEBUG → textDisabled
- Use `AutoClawdLogger.shared.snapshot()` directly (no file I/O needed for live view)
- Add a "Refresh" button to re-call `loadLogs()`

---

## 5. Dark / Light / System Appearance

### SettingsManager.swift
```swift
enum AppearanceSetting: String, CaseIterable {
    case system = "System"
    case light  = "Light"
    case dark   = "Dark"
}
// Stored as UserDefaults key "appearanceSetting"
var appearanceSetting: AppearanceSetting { get set }
```

### AppDelegate.swift / window setup
Apply at the window content level:
```swift
.preferredColorScheme(
    SettingsManager.shared.appearanceSetting == .light ? .light :
    SettingsManager.shared.appearanceSetting == .dark  ? .dark  : nil
)
```
Use `@AppStorage("appearanceSetting")` in a wrapper view so it reactively updates on change.

### SettingsConsolidatedView.swift — Display section
```
Appearance
  ○ System   ○ Light   ○ Dark    ← Picker(.segmented)
```
Under the existing Display section header.

---

## Files Changed

| File | Change |
|---|---|
| `Sources/AppTheme.swift` | Adaptive tokens, new `textDisabled`, `Color.adaptive()`, fix token values, caption 12pt |
| `Sources/MainPanelView.swift` | Sidebar labels, width 60px, button row fix |
| `Sources/WorldView.swift` | `textDisabled`, `lineLimit(2)`, section header style, layout priority, cell width cap |
| `Sources/IntelligenceConsolidatedView.swift` | Fix `loadLogs()`, per-entry log display with level colors, Refresh button |
| `Sources/SettingsConsolidatedView.swift` | Section header style, tag font size, path truncation, appearance picker |
| `Sources/SettingsManager.swift` | Add `AppearanceSetting` enum + stored property |
| `Sources/AppDelegate.swift` | Apply `.preferredColorScheme()` reactively |

---

## Out of Scope

- Layout restructuring (deferred to Figma redesign)
- Font family changes (deferred to Figma redesign)
- New features or tab changes
