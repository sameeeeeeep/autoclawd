# Glass Pill + Log Toasts + Flow Bar Toggle — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the pill's black fill with a liquid-glass effect, add real-time log toasts below the pill in the same glass style, and add a Settings toggle to show/hide the pill for off-screen recovery.

**Architecture:** Logger gets a Combine `PassthroughSubject` that fires on every log entry. AppDelegate subscribes and drives a new `ToastWindow` (NSPanel) positioned 8pt below the pill. The pill's SwiftUI background is swapped to `.ultraThinMaterial` + specular gradient. A `showFlowBar: Bool` setting in SettingsManager/AppState/AppDelegate controls pill + toast visibility.

**Tech Stack:** Swift 6, SwiftUI, AppKit (NSPanel), Combine (`PassthroughSubject`). Build: `make` (raw swiftc, macOS 13 target, all Sources/*.swift). SDK 15.2 — use `.ultraThinMaterial` throughout (`.glassEffect()` upgradeable later when Xcode 26 SDK ships).

---

## Task 1: Logger Combine Publisher

**Files:**
- Modify: `Sources/Logger.swift`

Add a `PassthroughSubject` to `AutoClawdLogger` so any subscriber can observe every log entry in real-time. The publish call goes on the main queue so UI subscribers don't need a `receive(on:)`.

**Step 1: Add `import Combine` at the top of Logger.swift**

Open `Sources/Logger.swift`. The file currently starts with `import Foundation`. Change to:

```swift
import Combine
import Foundation
```

**Step 2: Add the publisher property to AutoClawdLogger**

Find the class definition:
```swift
final class AutoClawdLogger: @unchecked Sendable {
    static let shared = AutoClawdLogger()
```

Add one property directly after `static let shared`:
```swift
    /// Fires on every log entry, always on the main queue.
    static let toastPublisher = PassthroughSubject<LogEntry, Never>()
```

**Step 3: Publish in `log(_:_:_:)`**

Find the existing `log` method. It currently ends with `queue.async { [weak self] in self?.write(entry) }`. Add a main-queue publish call after that line:

```swift
    func log(_ level: LogLevel, _ component: LogComponent, _ message: String) {
        guard level >= minimumLevel else { return }
        let entry = LogEntry(timestamp: Date(), level: level, component: component, message: message)
        queue.async { [weak self] in
            self?.write(entry)
        }
        DispatchQueue.main.async {
            AutoClawdLogger.toastPublisher.send(entry)
        }
    }
```

**Step 4: Build to verify**

```bash
make
```

Expected: `Built build/AutoClawd.app` with no errors.

**Step 5: Commit**

```bash
git add Sources/Logger.swift
git commit -m "feat: add Combine toast publisher to AutoClawdLogger"
```

---

## Task 2: ToastWindow — NSPanel Subclass

**Files:**
- Create: `Sources/ToastWindow.swift`

A non-activating floating panel to host the toast view. Matches pill dimensions (220 × 36). Clear background so SwiftUI `.ultraThinMaterial` shows through.

**Step 1: Create the file**

Create `Sources/ToastWindow.swift` with this exact content:

```swift
import AppKit
import SwiftUI

/// Floating glass toast panel, positioned below the pill.
final class ToastWindow: NSPanel {

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 36),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
    }

    func setContent<V: View>(_ view: V) {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
    }

    override var canBecomeKey: Bool  { false }
    override var canBecomeMain: Bool { false }
}
```

**Step 2: Build to verify**

```bash
make
```

Expected: `Built build/AutoClawd.app` — no errors.

**Step 3: Commit**

```bash
git add Sources/ToastWindow.swift
git commit -m "feat: add ToastWindow NSPanel for log toasts"
```

---

## Task 3: ToastView — Glass SwiftUI View

**Files:**
- Create: `Sources/ToastView.swift`

Displays one `LogEntry`. Glass background (`.ultraThinMaterial` + top-edge specular sheen). Left badge `[●]` neon green for info/debug, `[!]` red for warn/error. Center message truncated to one line. Right relative timestamp.

**Step 1: Create the file**

Create `Sources/ToastView.swift`:

```swift
import SwiftUI

struct ToastView: View {
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 6) {
            // Level badge
            Text(badge)
                .font(BrutalistTheme.monoSM)
                .foregroundColor(badgeColor)

            // Message — one line, truncated
            Text(entry.message)
                .font(BrutalistTheme.monoSM)
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            // Component tag
            Text("[\(entry.component.rawValue)]")
                .font(BrutalistTheme.monoSM)
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 0)
        .frame(height: 36)
        .background(glassBackground)
        .overlay(
            Rectangle()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private var badge: String {
        switch entry.level {
        case .warn, .error: return "[!]"
        default:            return "[●]"
        }
    }

    private var badgeColor: Color {
        switch entry.level {
        case .warn, .error: return .red
        default:            return BrutalistTheme.neonGreen
        }
    }

    private var glassBackground: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            // Specular sheen: white → clear top-to-center
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
        }
    }
}
```

**Step 2: Build to verify**

```bash
make
```

Expected: `Built build/AutoClawd.app` — no errors.

**Step 3: Commit**

```bash
git add Sources/ToastView.swift
git commit -m "feat: add ToastView glass SwiftUI toast component"
```

---

## Task 4: AppDelegate — Toast Subscription + showToast

**Files:**
- Modify: `Sources/AppDelegate.swift`

Wire `AutoClawdLogger.toastPublisher` into the AppDelegate. On each event: create/update the ToastWindow, position it 8pt below the pill, show it, schedule 3-second auto-dismiss (cancelling any prior dismiss timer).

**Step 1: Add `import Combine` to AppDelegate.swift**

Find the import block at the top of `Sources/AppDelegate.swift`:
```swift
import AppKit
import AVFoundation
import SwiftUI
```
Change to:
```swift
import AppKit
import AVFoundation
import Combine
import SwiftUI
```

**Step 2: Add stored properties to AppDelegate**

Find the class body:
```swift
final class AppDelegate: NSObject, NSApplicationDelegate {

    let appState = AppState()
    private var pillWindow: PillWindow?
    private var mainPanel: MainPanelWindow?
```

Add three new properties after `mainPanel`:
```swift
    private var toastWindow: ToastWindow?
    private var toastDismissWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
```

**Step 3: Subscribe to toastPublisher in `applicationDidFinishLaunching`**

Find `applicationDidFinishLaunching`. It currently ends with `checkMicPermission()`. Add the subscription after that:

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appState.applicationDidFinishLaunching()
        showPill()
        checkMicPermission()

        // Log toast subscription
        AutoClawdLogger.toastPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entry in self?.showToast(entry) }
            .store(in: &cancellables)
    }
```

**Step 4: Add `showToast(_ entry:)` method**

Add this method to AppDelegate, after `toggleMinimal()`:

```swift
    // MARK: - Toast

    private func showToast(_ entry: LogEntry) {
        // Cancel any pending dismiss
        toastDismissWork?.cancel()

        // Create window on first use
        if toastWindow == nil {
            toastWindow = ToastWindow()
        }
        guard let toast = toastWindow, let pill = pillWindow else { return }

        // Update content
        toast.setContent(ToastView(entry: entry))

        // Position 8pt below pill
        let pillFrame = pill.frame
        toast.setFrameOrigin(NSPoint(
            x: pillFrame.minX,
            y: pillFrame.minY - 8 - 36  // 36 = toast height
        ))
        toast.orderFront(nil)

        // Schedule auto-dismiss after 3 seconds
        let work = DispatchWorkItem { [weak self] in
            self?.toastWindow?.orderOut(nil)
        }
        toastDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
```

**Step 5: Build to verify**

```bash
make
```

Expected: `Built build/AutoClawd.app` — no errors.

**Step 6: Smoke-test toasts**

```bash
make run
```

The app opens. Within seconds of launch, log events fire (e.g. "Pill window shown" from `Log.info(.ui, ...)`). You should see a glass toast appear below the pill for ~3 seconds then fade out.

**Step 7: Commit**

```bash
git add Sources/AppDelegate.swift
git commit -m "feat: wire log toasts in AppDelegate (Combine subscription + showToast)"
```

---

## Task 5: Glass Pill Background + Shadow

**Files:**
- Modify: `Sources/PillView.swift`
- Modify: `Sources/PillWindow.swift`

Replace the solid black pill background with `.ultraThinMaterial` + specular gradient. Enable shadow on PillWindow so the glass panel has visual depth.

**Step 1: Update `pillBackground` in PillView.swift**

Find the existing `pillBackground` computed property:
```swift
    private var pillBackground: some View { Rectangle().fill(Color.black) }
```

Replace with:
```swift
    private var pillBackground: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            // Specular sheen
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
        }
    }
```

**Step 2: Enable shadow in PillWindow.swift**

Find `configure()` in PillWindow:
```swift
        hasShadow = false
```

Change to:
```swift
        hasShadow = true
```

**Step 3: Build to verify**

```bash
make
```

Expected: `Built build/AutoClawd.app` — no errors.

**Step 4: Visual check**

```bash
make run
```

The pill should now be translucent — you should see your desktop/windows behind it with a frosted glass appearance. Neon green text, waveform bars, and borders are unchanged.

**Step 5: Commit**

```bash
git add Sources/PillView.swift Sources/PillWindow.swift
git commit -m "feat: liquid glass pill background (ultraThinMaterial + specular sheen)"
```

---

## Task 6: SettingsManager + AppState — showFlowBar

**Files:**
- Modify: `Sources/SettingsManager.swift`
- Modify: `Sources/AppState.swift`

Add persistent storage for the "Show Flow bar" setting. Default is `true` (visible). `AppState` exposes it as a `@Published` property so SwiftUI binds to it and AppDelegate can react via Combine.

**Step 1: Add `showFlowBar` to SettingsManager**

Find the `// MARK: - Keys` section in `Sources/SettingsManager.swift`:
```swift
    private let kTranscriptionMode = "transcription_mode"
    private let kAudioRetention    = "audio_retention_days"
    private let kMicEnabled        = "mic_enabled"
    private let kLogLevel          = "log_level"
    private let kGroqAPIKey        = "groq_api_key_storage"
```

Add one key:
```swift
    private let kShowFlowBar       = "show_flow_bar"
```

Then find `// MARK: - Properties` and add the property after `groqAPIKey`:

```swift
    var showFlowBar: Bool {
        get { defaults.object(forKey: kShowFlowBar) as? Bool ?? true }
        set { defaults.set(newValue, forKey: kShowFlowBar) }
    }
```

**Step 2: Add `showFlowBar` to AppState**

In `Sources/AppState.swift`, find the block of `@Published` properties (e.g. near `@Published var pillMode`). Add:

```swift
    @Published var showFlowBar: Bool {
        didSet { SettingsManager.shared.showFlowBar = showFlowBar }
    }
```

**Step 3: Load showFlowBar in AppState.init()**

Find where AppState loads settings from SettingsManager in its initialiser (look for the block that sets `transcriptionMode`, `micEnabled`, etc.). Add loading of showFlowBar at the same place:

```swift
        showFlowBar = settings.showFlowBar
```

**Step 4: Build to verify**

```bash
make
```

Expected: `Built build/AutoClawd.app` — no errors. If the compiler complains that `showFlowBar` is used before initialisation, make sure it's initialised before `super.init()` or reorder the `init` assignments.

**Step 5: Commit**

```bash
git add Sources/SettingsManager.swift Sources/AppState.swift
git commit -m "feat: add showFlowBar setting (SettingsManager + AppState)"
```

---

## Task 7: AppDelegate Sink + Settings UI Toggle

**Files:**
- Modify: `Sources/AppDelegate.swift`
- Modify: `Sources/MainPanelView.swift`

AppDelegate reacts to `showFlowBar` changes: hide/show pill + toast, or snap pill back to default corner on re-enable. The Settings tab gets a "Display" GroupBox with the toggle.

**Step 1: Add `defaultPillOrigin()` helper to AppDelegate**

The pill's initial position is computed from `NSScreen.main` in `configure()` inside PillWindow. We need to compute the same point from AppDelegate for the snap-back. Add this private helper to AppDelegate (place it near `showPill()`):

```swift
    private func defaultPillOrigin() -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        return NSPoint(
            x: screen.visibleFrame.maxX - 240,
            y: screen.visibleFrame.maxY - 60
        )
    }
```

**Step 2: Subscribe to `appState.$showFlowBar` in `applicationDidFinishLaunching`**

Directly after the `AutoClawdLogger.toastPublisher` subscription added in Task 4, add:

```swift
        // Show/hide pill + toast when setting changes
        appState.$showFlowBar
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                guard let self else { return }
                if show {
                    self.pillWindow?.setFrameOrigin(self.defaultPillOrigin())
                    self.pillWindow?.orderFront(nil)
                } else {
                    self.toastDismissWork?.cancel()
                    self.toastWindow?.orderOut(nil)
                    self.pillWindow?.orderOut(nil)
                }
            }
            .store(in: &cancellables)
```

**Step 3: Add "Display" GroupBox to SettingsTabView in MainPanelView.swift**

Find `SettingsTabView.body`. It currently starts with:
```swift
            VStack(alignment: .leading, spacing: 20) {
                TabHeader("SETTINGS") { EmptyView() }

                GroupBox("Transcription") {
```

Insert the Display group between `TabHeader` and `GroupBox("Transcription")`:

```swift
                GroupBox("Display") {
                    Toggle("Show Flow bar at all times", isOn: $appState.showFlowBar)
                        .font(BrutalistTheme.monoMD)
                        .padding(8)
                }
```

**Step 4: Build to verify**

```bash
make
```

Expected: `Built build/AutoClawd.app` — no errors.

**Step 5: End-to-end test**

```bash
make run
```

1. Open the main panel → Settings tab → confirm "Show Flow bar at all times" toggle appears at the top of the settings list, defaulting to ON.
2. Toggle it OFF → pill and any toast disappear.
3. Toggle it back ON → pill snaps back to default top-right corner and reappears.
4. Watch the toast area below the pill — every log event (including the ones fired by toggling the setting) should produce a glass toast that auto-dismisses after 3 seconds.

**Step 6: Commit**

```bash
git add Sources/AppDelegate.swift Sources/MainPanelView.swift
git commit -m "feat: showFlowBar sink in AppDelegate + Display toggle in Settings"
```

---

## Build Verification Checklist

After all 7 tasks:

```bash
make clean && make
```

Expected: compiles cleanly from scratch — `Built build/AutoClawd.app`.

Visual checks on `make run`:
- [ ] Pill is frosted glass (not solid black); desktop visible behind it
- [ ] Neon green `[AMB]`/`[TRS]`/`[SRC]` labels still visible
- [ ] Waveform bars still neon green when listening
- [ ] Log toasts appear below pill within 1–2s of launch
- [ ] Toast glass matches pill glass style
- [ ] Toast `[●]` badge is neon green; `[!]` is red for errors
- [ ] Toast auto-dismisses after 3s
- [ ] Settings → Display → "Show Flow bar" toggle hides pill + toast when OFF
- [ ] Toggling back ON snaps pill to top-right corner

---

## Note on macOS 26 Upgrade

When Xcode with macOS 26 SDK is available, upgrade `pillBackground` and `glassBackground` in `ToastView` from:
```swift
Rectangle().fill(.ultraThinMaterial)
```
to:
```swift
// macOS 26+: native liquid glass
if #available(macOS 26, *) {
    Rectangle().glassEffect(.regular, in: .rect)
}
```
No other changes needed — the architecture is already compatible.
