import AppKit
import AVFoundation
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let appState = AppState()
    private var pillWindow: PillWindow?
    private var mainPanel: MainPanelWindow?
    private var toastWindow: ToastWindow?
    private var toastDismissWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appState.applicationDidFinishLaunching()

        showPill()

        // Check microphone permission
        checkMicPermission()

        // Log toast subscription
        AutoClawdLogger.toastPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entry in self?.showToast(entry) }
            .store(in: &cancellables)

        // Show/hide pill + toast when setting changes
        appState.$showFlowBar
            .receive(on: DispatchQueue.main)
            .dropFirst()  // skip initial value — pill is already shown by showPill()
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stopListening()
        ClipboardMonitor.shared.stop()
        Log.info(.system, "AutoClawd terminating")
    }

    // MARK: - Pill Window

    private func defaultPillOrigin() -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        return NSPoint(
            x: screen.visibleFrame.maxX - 240,
            y: screen.visibleFrame.maxY - 60
        )
    }

    private func showPill() {
        let pill = PillWindow()
        let content = PillContentView(
            appState: appState,
            onOpenPanel: { [weak self] in self?.showMainPanel() },
            onTogglePause: { [weak self] in self?.appState.toggleListening() },
            onOpenLogs: { [weak self] in self?.showMainPanel(tab: .logs) },
            onToggleMinimal: { [weak self] in self?.toggleMinimal() }
        )
        pill.setContent(content)
        pill.orderFront(nil)
        pillWindow = pill
        Log.info(.ui, "Pill window shown")
    }

    private func toggleMinimal() {
        if case .minimal = appState.pillState {
            appState.pillState = appState.isListening ? .listening : .paused
        } else {
            appState.pillState = .minimal
        }
        Log.info(.ui, "Pill state → \(appState.pillState)")
    }

    // MARK: - Toast

    private func showToast(_ entry: LogEntry) {
        guard appState.showFlowBar else { return }
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

    // MARK: - Main Panel

    func showMainPanel(tab: PanelTab = .todos) {
        if let panel = mainPanel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let panel = MainPanelWindow(appState: appState)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainPanel = panel
        Log.info(.ui, "Main panel opened, tab: \(tab.rawValue)")
    }

    // MARK: - Microphone Permission

    private func checkMicPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted {
                        Log.info(.system, "Microphone permission granted")
                    } else {
                        Log.warn(.system, "Microphone permission denied")
                        self.showMicAlert()
                    }
                }
            }
        default:
            showMicAlert()
        }
    }

    private func showMicAlert() {
        let alert = NSAlert()
        alert.messageText = "Microphone Access Required"
        alert.informativeText = "AutoClawd needs microphone access to transcribe your conversations. Please grant access in System Settings → Privacy & Security → Microphone."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }
}

// MARK: - Pill Content (bridges AppState → PillView)

struct PillContentView: View {
    @ObservedObject var appState: AppState
    let onOpenPanel: () -> Void
    let onTogglePause: () -> Void
    let onOpenLogs: () -> Void
    let onToggleMinimal: () -> Void

    // Periodic audio level update
    @State private var displayLevel: Float = 0

    var body: some View {
        PillView(
            state: appState.pillState,
            audioLevel: displayLevel,
            onOpenPanel: onOpenPanel,
            onTogglePause: onTogglePause,
            onOpenLogs: onOpenLogs,
            onToggleMinimal: onToggleMinimal,
            pillMode: appState.pillMode,
            onCycleMode: { appState.cyclePillMode() },
            appearanceMode: appState.appearanceMode
        )
        .onReceive(
            Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
        ) { _ in
            displayLevel = appState.chunkManager.audioLevel
        }
    }
}
