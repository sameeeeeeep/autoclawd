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
    private var setupWindow: SetupWindow?
    private var toastDismissWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appState.applicationDidFinishLaunching()
        appState.onShowSetup = { [weak self] in Task { @MainActor in self?.showSetupWindowSync() } }

        showPill()
        pillWindow?.setWidgetHeight(Self.widgetHeight(for: appState.pillMode))

        // Show first-run setup if dependencies are missing
        showSetupIfNeeded()

        // Check microphone permission
        checkMicPermission()

        // Log toast subscription
        AutoClawdLogger.toastPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entry in self?.showToast(entry) }
            .store(in: &cancellables)

        // Resize pill window when mode changes — each mode has its own widget height
        appState.$pillMode
            .dropFirst()  // initial resize handled above
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.pillWindow?.setWidgetHeight(Self.widgetHeight(for: mode))
            }
            .store(in: &cancellables)

        // Show/hide pill + toast when setting changes
        appState.$showAmbientWidget
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
            onOpenLogs: { [weak self] in self?.showMainPanel() },
            onToggleMinimal: { [weak self] in self?.toggleMinimal() }
        )
        pill.setContent(content)
        pill.menuProvider = { [weak self] in self?.makePillMenu() ?? NSMenu() }
        pill.orderFront(nil)
        pillWindow = pill
        Log.info(.ui, "Pill window shown")
    }

    /// Widget panel height for each pill mode.
    static func widgetHeight(for mode: PillMode) -> CGFloat {
        switch mode {
        case .ambientIntelligence: return 220  // map square
        case .transcription:       return 140  // text + apply button
        case .aiSearch:            return 150  // Q + A display
        }
    }

    private func toggleMinimal() {
        if case .minimal = appState.pillState {
            appState.pillState = appState.isListening ? .listening : .paused
        } else {
            appState.pillState = .minimal
        }
        Log.info(.ui, "Pill state → \(appState.pillState)")
    }

    // MARK: - Pill Context Menu

    private func makePillMenu() -> NSMenu {
        let menu = NSMenu()
        let isListening = appState.isListening

        menu.addItem(NSMenuItem(title: "Open Panel", action: #selector(menuOpenPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: isListening ? "Pause Listening  ⌃Z" : "Resume Listening  ⌃Z",
                                action: #selector(menuTogglePause), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Ambient Mode  ⌃A",    action: #selector(menuAmbient),    keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "AI Search Mode  ⌃S",  action: #selector(menuSearch),     keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Transcribe Mode  ⌃X", action: #selector(menuTranscribe), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "View Logs",           action: #selector(menuViewLogs),   keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit AutoClawd",      action: #selector(NSApp.terminate), keyEquivalent: ""))

        // Wire targets so selectors fire on self
        for item in menu.items where item.action != #selector(NSApp.terminate) {
            item.target = self
        }
        return menu
    }

    @objc private func menuOpenPanel()    { showMainPanel() }
    @objc private func menuTogglePause()  { appState.toggleListening() }
    @objc private func menuViewLogs()     { showMainPanel() }
    @objc private func menuAmbient()      { appState.pillMode = .ambientIntelligence; if !appState.isListening { appState.startListening() } }
    @objc private func menuSearch()       { appState.pillMode = .aiSearch;            if !appState.isListening { appState.startListening() } }
    @objc private func menuTranscribe()   { appState.pillMode = .transcription;       if !appState.isListening { appState.startListening() } }

    // MARK: - Toast

    private func showToast(_ entry: LogEntry) {
        guard appState.showAmbientWidget else { return }
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

    func showMainPanel(tab: PanelTab = .world) {
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

    // MARK: - Setup Window

    private func showSetupIfNeeded() {
        // Immediate show if no Groq key
        if SettingsManager.shared.groqAPIKey.isEmpty {
            showSetupWindowSync()
            return
        }
        // Background check for Ollama
        Task {
            let ollamaOK = await OllamaService().isAvailable()
            if !ollamaOK { showSetupWindowSync() }
        }
    }

    private func showSetupWindowSync() {
        guard setupWindow == nil else {
            setupWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = SetupWindow { [weak self] in
            self?.setupWindow?.orderOut(nil)
            self?.setupWindow = nil
        }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        setupWindow = win
        Log.info(.ui, "Setup window shown")
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
        VStack(spacing: 8) {
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

            widgetForCurrentMode
        }
        .frame(width: 220) // consistent width across all modes
        .animation(.easeInOut(duration: 0.22), value: appState.pillMode)
        .onReceive(
            Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
        ) { _ in
            displayLevel = appState.chunkManager.audioLevel
        }
    }

    // MARK: - Mode-Specific Widget

    @ViewBuilder
    private var widgetForCurrentMode: some View {
        switch appState.pillMode {
        case .ambientIntelligence:
            AmbientMapView(appState: appState)
                .transition(.opacity.combined(with: .offset(y: -6)))

        case .transcription:
            TranscriptionWidgetView(
                latestText: appState.latestTranscriptChunk,
                isListening: appState.isListening,
                onApply: { appState.applyLatestTranscript() }
            )
            .transition(.opacity.combined(with: .offset(y: -6)))

        case .aiSearch:
            QAWidgetView(
                latestItem: appState.qaStore.items.first,
                isListening: appState.isListening
            )
            .transition(.opacity.combined(with: .offset(y: -6)))
        }
    }
}
