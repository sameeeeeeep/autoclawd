# Liquid Glass Pill + Log Toasts + Flow Bar Toggle — Design Doc

**Date:** 2026-02-25
**Status:** Approved
**Scope:** Three related UI enhancements to the AutoClawd floating pill

---

## Overview

Three changes shipped together because they share the glass visual language and the pill window infrastructure:

1. **Liquid glass pill** — replace solid black fill with macOS-native glass effect
2. **Log toasts** — all log events appear as glass toasts below the pill, auto-replace, 3s dismiss
3. **"Show Flow bar" toggle** — Settings switch to hide/show pill; toggling on resets to default corner (recovery mechanism for off-screen drift)

---

## 1. Liquid Glass Pill

### Visual Design

Brutalist-glass hybrid: sharp Rectangle shape, neon green text labels and waveform bars, 1px border — all preserved. Only the **background fill** changes from solid black to translucent glass.

```
┌─────────────────────────────────────┐   ← Rectangle (no corner radius)
│ 🫧 [AMB]  ▓▓▓▓▓▓▓▓▓▓░░░░  [⏸]  ⊞ │   ← glass body, neon text unchanged
└─────────────────────────────────────┘
```

### Implementation

**Glass recipe (conditional on macOS version):**

```swift
// macOS 26+: native Liquid Glass
if #available(macOS 26, *) {
    Rectangle().glassEffect(.regular, in: .rect)
} else {
    // macOS 13–25: layered material + specular sheen
    ZStack {
        Rectangle().fill(.ultraThinMaterial)
        LinearGradient(
            colors: [.white.opacity(0.12), .clear],
            startPoint: .top,
            endPoint: .center
        )
    }
}
```

**Changes in `PillView.swift`:**
- `pillBackground`: replace `Rectangle().fill(Color.black)` with the above recipe
- `pillBorder`: keep `Rectangle().stroke(.white.opacity(0.25), lineWidth: 1)` — no change

**Changes in `PillWindow.swift`:**
- `hasShadow`: `false` → `true` — glass without depth looks flat

---

## 2. Log Toasts

### Architecture

A separate `NSPanel` (`ToastWindow`) floats 8pt below the pill. When any log event fires, it replaces the current toast immediately and schedules a 3-second auto-dismiss.

```
┌─────────────────────────────────────┐   ← PillWindow
└─────────────────────────────────────┘
        ↕ 8pt gap
┌────────────────────────────────────┐    ← ToastWindow
│  [●] Transcript saved        2.1s  │
└────────────────────────────────────┘
```

### Toast Anatomy

| Zone | Content |
|---|---|
| Left badge | `[●]` neon green for .info/.debug; `[!]` red for .warn/.error |
| Middle | `entry.message` — 1 line, truncated, `BrutalistTheme.monoMD` |
| Right | Relative time from app start (e.g. `2.1s`), `BrutalistTheme.monoSM`, dim white |

### Glass Recipe

Same as pill: `.glassEffect(.regular, in: .rect)` on macOS 26+, `.ultraThinMaterial` + gradient on older.

### Logger Integration

Add to `Logger.swift`:

```swift
import Combine

// In AutoClawdLogger:
static let toastPublisher = PassthroughSubject<LogEntry, Never>()

// In log(_:_:_:), after writing the entry — dispatch to main:
DispatchQueue.main.async {
    AutoClawdLogger.toastPublisher.send(entry)
}
```

### AppDelegate Integration

```swift
private var toastCancellable: AnyCancellable?
private var toastWindow: ToastWindow?
private var dismissWork: DispatchWorkItem?

// In applicationDidFinishLaunching:
toastCancellable = AutoClawdLogger.toastPublisher
    .receive(on: DispatchQueue.main)
    .sink { [weak self] entry in self?.showToast(entry) }

func showToast(_ entry: LogEntry) {
    dismissWork?.cancel()
    guard let pill = pillWindow else { return }

    if toastWindow == nil {
        let tw = ToastWindow()
        tw.setContent(ToastView(entry: entry))
        toastWindow = tw
    } else {
        toastWindow?.updateEntry(entry)
    }

    // Position 8pt below pill
    let pillFrame = pill.frame
    toastWindow?.setFrameOrigin(NSPoint(
        x: pillFrame.minX,
        y: pillFrame.minY - 8 - 36  // 36 = toast height
    ))
    toastWindow?.orderFront(nil)

    let work = DispatchWorkItem { [weak self] in
        self?.toastWindow?.orderOut(nil)
    }
    dismissWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
}
```

### ToastWindow

New `NSPanel` subclass at `Sources/ToastWindow.swift`:
- Style: `.borderless + .nonactivatingPanel + .utilityWindow`
- `backgroundColor = .clear`, `hasShadow = true`, `level = .floating`
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`
- Width: matches pill width (220pt); height: 36pt
- `canBecomeKey = false`, `canBecomeMain = false`

### ToastView

New SwiftUI view at `Sources/ToastView.swift`:
- `@State var entry: LogEntry` — mutated via `updateEntry()` on window
- Layout: `HStack` — badge + message + Spacer + timestamp
- Glass background identical to pill recipe
- `Rectangle().stroke(.white.opacity(0.20), lineWidth: 1)` border

---

## 3. "Show Flow Bar" Toggle

### Settings UI

New `GroupBox("Display")` inserted at top of `SettingsTabView` body (above Transcription group):

```swift
GroupBox("Display") {
    Toggle("Show Flow bar at all times", isOn: $appState.showFlowBar)
        .padding(8)
}
```

### Storage

`SettingsManager.swift` — new property:

```swift
private let kShowFlowBar = "show_flow_bar"

var showFlowBar: Bool {
    get { defaults.object(forKey: kShowFlowBar) as? Bool ?? true }
    set { defaults.set(newValue, forKey: kShowFlowBar) }
}
```

### AppState

```swift
@Published var showFlowBar: Bool {
    didSet { SettingsManager.shared.showFlowBar = showFlowBar }
}

// In init(), after loading other settings:
showFlowBar = SettingsManager.shared.showFlowBar
```

### AppDelegate Reaction

Sink on `appState.$showFlowBar` in `applicationDidFinishLaunching`:

```swift
appState.$showFlowBar
    .receive(on: DispatchQueue.main)
    .sink { [weak self] show in
        guard let self else { return }
        if show {
            // Snap back to default top-right corner
            if let screen = NSScreen.main {
                let x = screen.visibleFrame.maxX - 240
                let y = screen.visibleFrame.maxY - 60
                self.pillWindow?.setFrameOrigin(NSPoint(x: x, y: y))
            }
            self.pillWindow?.orderFront(nil)
            self.toastWindow?.orderFront(nil)
        } else {
            self.pillWindow?.orderOut(nil)
            self.toastWindow?.orderOut(nil)
        }
    }
    .store(in: &cancellables)
```

Note: `cancellables` is a new `Set<AnyCancellable>` property on `AppDelegate`.

---

## Files Touched

| File | Change |
|---|---|
| `Sources/PillView.swift` | `pillBackground` — conditional glass recipe |
| `Sources/PillWindow.swift` | `hasShadow = true` |
| `Sources/Logger.swift` | Add `import Combine`, `toastPublisher: PassthroughSubject<LogEntry, Never>`, publish in `log()` |
| `Sources/AppDelegate.swift` | `var cancellables: Set<AnyCancellable>`, subscribe to toastPublisher + showFlowBar, manage ToastWindow |
| `Sources/AppState.swift` | `@Published var showFlowBar: Bool` with `didSet` |
| `Sources/SettingsManager.swift` | `showFlowBar` stored property |
| `Sources/MainPanelView.swift` | "Display" `GroupBox` in `SettingsTabView` |
| **NEW** `Sources/ToastWindow.swift` | `NSPanel` subclass for toasts |
| **NEW** `Sources/ToastView.swift` | SwiftUI glass toast view |

---

## Non-Goals (this PR)

- Toast does not follow pill while being dragged mid-drag (re-positions on next toast)
- Toast stacking (multiple toasts visible) — replace-only for now
- Filtering toasts by log level or component — all events shown
- Pill position persistence across launches remains unchanged
