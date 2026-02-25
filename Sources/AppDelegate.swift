import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let appState = AppState()
    private var pillWindow: PillWindow?
    private var mainPanel: MainPanelWindow?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appState.applicationDidFinishLaunching()

        showPill()

        // Check microphone permission
        checkMicPermission()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stopListening()
        ClipboardMonitor.shared.stop()
        Log.info(.system, "AutoClawd terminating")
    }

    // MARK: - Pill Window

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
            onToggleMinimal: onToggleMinimal
        )
        .onReceive(
            Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
        ) { _ in
            displayLevel = appState.chunkManager.audioLevel
        }
    }
}
