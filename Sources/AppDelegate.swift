import AppKit
import AVFoundation
import Combine
import Speech
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let appState = AppState()
    private var pillWindow: PillWindow?
    private var mainPanel: MainPanelWindow?
    private var toastWindow: ToastWindow?
    private var monitorWindow: LearnModeMonitorWindow?
    private var setupWindow: SetupWindow?
    private var onboardingWindow: OnboardingWindow?
    private var statusItem: NSStatusItem?
    private var toastDismissWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppFonts.registerAll()   // register custom fonts before any views render
        NSApp.setActivationPolicy(.accessory)
        appState.applicationDidFinishLaunching()
        appState.onShowSetup = { [weak self] in Task { @MainActor in self?.showSetupWindowSync() } }

        showPill()
        setupMenuBarIcon()

        // Initialise auxiliary windows
        toastWindow = ToastWindow()
        monitorWindow = LearnModeMonitorWindow(service: appState.learnModeService)

        // Show first-run setup if dependencies are missing
        showSetupIfNeeded()

        // Request all required permissions upfront (mic + speech recognition).
        // On first launch this ensures permission dialogs fire before the first
        // recording attempt — preventing the first chunk from silently failing.
        requestPermissionsUpfront()

        // Show/hide the Learn Mode monitor window when pill mode changes
        appState.$pillMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                guard let self else { return }
                if mode == .learn {
                    self.monitorWindow?.orderFront(nil)
                } else {
                    self.monitorWindow?.orderOut(nil)
                }
            }
            .store(in: &cancellables)

        // Capability / task suggestion toast — show in top-right when detected
        appState.$detectedSuggestion
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                guard let self else { return }
                if let item = item {
                    self.showSuggestionToast(item)
                } else {
                    self.toastWindow?.dismiss()
                }
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
            x: screen.visibleFrame.maxX - PillWindow.defaultWidth - 16,
            y: screen.visibleFrame.maxY - WidgetCollapseLevel.full.height - 16
        )
    }

    private func showPill() {
        let pill = PillWindow()
        let content = PillContentView(
            appState:            appState,
            onOpenPanel:         { [weak self] in self?.showMainPanel() },
            onTogglePause:       { [weak self] in self?.appState.toggleListening() },
            onToggleLocalModel:  { [weak self] in self?.toggleLocalModel() },
            onToggleCode:        { [weak self] in self?.toggleCodeMode() },
            onToggleSpeakerMode: { [weak self] in self?.toggleSpeakerMode() },
            onToggleScreenShare: { [weak self] in self?.toggleScreenShare() },
            onCollapseChange:    { [weak self] level in self?.pillWindow?.setCollapseLevel(level) }
        )
        pill.setContent(content)
        pill.menuProvider = { [weak self] in self?.makePillMenu() ?? NSMenu() }
        pill.orderFront(nil)
        pillWindow = pill
        Log.info(.ui, "Pill window shown")
    }

    /// Toggle Ollama analysis on/off independently of the current mode.
    /// When off: transcripts are recorded + cleaned but Ollama skips analysis/tasks.
    private func toggleLocalModel() {
        appState.isOllamaEnabled.toggle()
        Log.info(.ui, "Ollama analysis \(appState.isOllamaEnabled ? "enabled" : "disabled")")
    }

    /// Toggle Claude Code auto-execution on/off independently of the current mode.
    /// When off: tasks are created by Ollama but never auto-executed.
    private func toggleCodeMode() {
        appState.isCodeExecutionEnabled.toggle()
        Log.info(.ui, "Code execution \(appState.isCodeExecutionEnabled ? "enabled" : "disabled")")
    }

    /// Cycle single ↔ multiple speaker mode.
    private func toggleSpeakerMode() {
        appState.speakerMode = appState.speakerMode == .single ? .multiple : .single
        Log.info(.ui, "Speaker mode → \(appState.speakerMode.rawValue)")
    }

    /// Toggle system audio capture (screen share) on/off.
    private func toggleScreenShare() {
        appState.systemAudioEnabled.toggle()
        Log.info(.ui, "Screen share \(appState.systemAudioEnabled ? "enabled" : "disabled")")
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
    @objc private func menuAmbient()      { appState.pillMode = .ambient; if !appState.isListening { appState.startListening() } }
    @objc private func menuSearch()       { appState.pillMode = .aiSearch; if !appState.isListening { appState.startListening() } }

    // MARK: - Menu Bar Icon

    private func setupMenuBarIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "AutoClawd")
            button.image?.size = NSSize(width: 18, height: 18)
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Panel", action: #selector(statusBarOpenPanel), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Pause Listening", action: #selector(statusBarToggleListening), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings\u{2026}", action: #selector(statusBarOpenSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit AutoClawd", action: #selector(statusBarQuit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        statusItem?.menu = menu
    }

    @objc private func statusBarOpenPanel() {
        showMainPanel()
    }

    @objc private func statusBarToggleListening() {
        appState.micEnabled.toggle()
        // Update menu item title to reflect new state
        if let menu = statusItem?.menu,
           let item = menu.items.first(where: { $0.action == #selector(statusBarToggleListening) }) {
            item.title = appState.micEnabled ? "Pause Listening" : "Resume Listening"
        }
    }

    @objc private func statusBarOpenSettings() {
        showMainPanel(tab: .settings)
    }

    @objc private func statusBarQuit() {
        NSApp.terminate(nil)
    }

    // MARK: - Suggestion Toast

    private func showSuggestionToast(_ item: SuggestionItem) {
        guard appState.showToasts else { return }
        toastDismissWork?.cancel()

        toastWindow?.show(item,
            onTap: { [weak self] in
                guard let self else { return }
                switch item {
                case .capability(let match):
                    self.appState.executeCapability(match.capability)
                    self.showMainPanel(tab: .agents)
                case .task(let task):
                    if task.detectedContext.isComplete {
                        self.appState.executeSuggestedTask(task)
                    } else {
                        // Open tasks panel for context gap-filling
                        self.appState.dismissDetectedSuggestion()
                        self.showMainPanel(tab: .tasks)
                    }
                }
            },
            onSnooze: { [weak self] in
                if case .capability(let match) = item {
                    CapabilityStore.shared.snooze(capabilityID: match.capability.id)
                }
                self?.appState.dismissDetectedSuggestion()
            },
            onMarkIrrelevant: { [weak self] in
                if case .capability(let match) = item {
                    CapabilityStore.shared.markIrrelevant(capabilityID: match.capability.id)
                }
                self?.appState.dismissDetectedSuggestion()
            }
        )

        // Auto-dismiss after 5 seconds
        let work = DispatchWorkItem { [weak self] in
            self?.appState.dismissDetectedSuggestion()
        }
        toastDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    // MARK: - Main Panel

    func showMainPanel(tab: PanelTab = .agents) {
        if let panel = mainPanel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            appState.activeTab = tab
            return
        }
        let panel = MainPanelWindow(appState: appState)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainPanel = panel
        appState.activeTab = tab
        Log.info(.ui, "Main panel opened, tab: \(tab.rawValue)")
    }

    // MARK: - Microphone Permission

    // MARK: - Upfront Permission Requests

    /// Request microphone + speech recognition permissions immediately at launch.
    /// This surfaces the system dialogs before the first recording attempt, so
    /// the first audio chunk never fails due to pending permissions.
    private func requestPermissionsUpfront() {
        // Microphone
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    Log.info(.system, "Microphone permission: \(granted ? "granted" : "denied")")
                    if !granted { self.showMicAlert() }
                }
            }
        } else if micStatus == .denied || micStatus == .restricted {
            showMicAlert()
        }

        // Speech Recognition (for local transcription mode)
        let srStatus = SFSpeechRecognizer.authorizationStatus()
        if srStatus == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    Log.info(.system, "Speech recognition permission: \(status == .authorized ? "granted" : "denied")")
                }
            }
        }
    }

    private func checkMicPermission() {
        // Kept for compatibility — actual requesting is now done in requestPermissionsUpfront()
        if AVCaptureDevice.authorizationStatus(for: .audio) == .denied {
            showMicAlert()
        }
    }

    // MARK: - Setup Window

    private func showSetupIfNeeded() {
        // Show onboarding on first launch before any setup
        if !UserDefaults.standard.bool(forKey: "onboarding_completed") {
            showOnboardingWindow()
            return
        }

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

    private func showOnboardingWindow() {
        guard onboardingWindow == nil else {
            onboardingWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = OnboardingWindow { [weak self] in
            self?.onboardingWindow?.orderOut(nil)
            self?.onboardingWindow = nil
            // After onboarding, proceed to setup if needed
            self?.showSetupIfNeeded()
        }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = win
        Log.info(.ui, "Onboarding window shown")
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

// MARK: - Pill Content (bridges AppState → WidgetView)

struct PillContentView: View {
    @ObservedObject var appState: AppState
    let onOpenPanel:          () -> Void
    let onTogglePause:        () -> Void
    let onToggleLocalModel:   () -> Void
    let onToggleCode:         () -> Void
    let onToggleSpeakerMode:  () -> Void
    let onToggleScreenShare:  () -> Void
    let onCollapseChange:     (WidgetCollapseLevel) -> Void

    @State private var collapseLevel:          WidgetCollapseLevel = .full
    @State private var displayLevel:           Float = 0
    @State private var logLines:               [(dot: Color, text: String, time: String)] = []
    @State private var canvasSnapshots:        [CanvasSnapshot] = []
    @State private var prevTranscript:         String = ""
    @State private var prevQACount:            Int = 0
    @State private var prevTaskCount:          Int = 0
    private static let logTimeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let snapTimeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        WidgetView(
            state:                  appState.pillState,
            audioLevel:             displayLevel,
            pillMode:               appState.pillMode,
            collapseLevel:          $collapseLevel,
            onOpenPanel:            onOpenPanel,
            onTogglePause:          onTogglePause,
            onCycleMode:            { appState.cyclePillMode() },
            onSetMode: { mode in
                appState.pillMode = mode
                if !appState.isListening { appState.startListening() }
            },
            onToggleLocalModel:     onToggleLocalModel,
            onToggleCode:           onToggleCode,
            onToggleSpeakerMode:    onToggleSpeakerMode,
            onToggleScreenShare:    onToggleScreenShare,
            onToggleCamera:         { },
            onSessionConfigure:     { appState.configureSession() },
            onSessionPlay: {
                switch appState.sessionLifecycle {
                case .undefined:
                    // Quick-start with default config (no config panel)
                    appState.startUserSession(config: SessionConfig())
                case .ready:
                    if let config = appState.sessionConfig {
                        appState.startUserSession(config: config)
                    }
                case .paused:
                    appState.resumeUserSession()
                default:
                    break
                }
            },
            onSessionPause:         { appState.pauseUserSession() },
            onSessionStop:          { appState.stopUserSession() },
            pipelineStages:         activePipelineStages,
            isLocalModelEnabled:    isLocalModelEnabled,
            isCodeEnabled:          isCodeEnabled,
            isMultiSpeaker:         appState.speakerMode == .multiple,
            isScreenShareEnabled:   appState.systemAudioEnabled,
            isCameraEnabled:        false,
            sessionLifecycle:       appState.sessionLifecycle,
            logLines:               logLines,
            isSessionProcessing:    appState.isSessionProcessing,
            isExecutionGlowActive:  appState.canvasExecutingTask != nil,
            aiCanvasContent:        canvasForCurrentMode,
            analysisIdleSubtitle:   analysisIdleSubtitle,
            executionIdleSubtitle:  executionIdleSubtitle,
            canvasSnapshots:        canvasSnapshots,
            appearance:             widgetAppearance
        )
        .onChange(of: collapseLevel) { level in onCollapseChange(level) }
        .onChange(of: appState.isAmbientReviewActive) { isActive in
            // Expand pill when the post-session review canvas opens; shrink back when done.
            withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                collapseLevel = isActive ? .expanded : .full
            }
            onCollapseChange(isActive ? .expanded : .full)
        }
        .onChange(of: appState.showCleaningPicker) { isShowing in
            // Expand pill when the cleaning level chooser appears so it's fully visible.
            withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                collapseLevel = isShowing ? .expanded : .full
            }
            onCollapseChange(isShowing ? .expanded : .full)
        }
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
            displayLevel = appState.chunkManager.audioLevel
        }
        .onReceive(AutoClawdLogger.toastPublisher.receive(on: DispatchQueue.main)) { entry in
            let time = Self.logTimeFmt.string(from: entry.timestamp)
            let line = (dot: logDotColor(for: entry.component),
                        text: entry.message,
                        time: time)
            logLines = Array(([line] + logLines).prefix(2))
        }
        // Canvas history: capture snapshot when transcript changes (ambient/transcription)
        .onChange(of: appState.latestTranscriptChunk) { newChunk in
            guard !prevTranscript.isEmpty, newChunk != prevTranscript else {
                prevTranscript = newChunk
                return
            }
            let snapshot = makeTranscriptSnapshot(prevTranscript: prevTranscript)
            canvasSnapshots = Array(([snapshot] + canvasSnapshots).prefix(8))
            prevTranscript = newChunk
        }
        // Canvas history: capture snapshot when a new QA answer arrives
        .onChange(of: appState.qaStore.items.count) { count in
            guard count > prevQACount, let item = appState.qaStore.items.first else {
                prevQACount = count; return
            }
            let snapshot = makeQASnapshot(question: item.question, answer: item.answer)
            canvasSnapshots = Array(([snapshot] + canvasSnapshots).prefix(8))
            prevQACount = count
        }
        // Canvas history: capture snapshot when task list grows
        .onChange(of: appState.pipelineTasks.count) { count in
            guard count > prevTaskCount else { prevTaskCount = count; return }
            let task = appState.pipelineTasks.last
            let label = "\(Self.snapTimeFmt.string(from: Date())) · Task"
            let snapshot = CanvasSnapshot(
                mode:    appState.pillMode,
                label:   label,
                content: AnyView(TasksCanvasView(
                    latestTaskTitle: task?.title ?? "",
                    taskCount:       count,
                    projectName:     task?.projectName
                ))
            )
            canvasSnapshots = Array(([snapshot] + canvasSnapshots).prefix(8))
            prevTaskCount = count
        }
    }

    // MARK: - Snapshot helpers (extracted from body to reduce type-checker complexity)

    private func makeTranscriptSnapshot(prevTranscript: String) -> CanvasSnapshot {
        let label = "\(Self.snapTimeFmt.string(from: Date())) · \(appState.pillMode.shortLabel)"
        let empty: Binding<String> = .constant("")
        let view = AmbientCanvasView(
            cleanedText:  appState.liveTranscriptText,
            pendingText:  "",
            incomingText: prevTranscript,
            typedText:    empty
        )
        return CanvasSnapshot(mode: appState.pillMode, label: label, content: AnyView(view))
    }

    private func makeQASnapshot(question: String, answer: String) -> CanvasSnapshot {
        let label = "\(Self.snapTimeFmt.string(from: Date())) · Q"
        let empty: Binding<String> = .constant("")
        let view = AISearchCanvasView(question: question, answer: answer, typedText: empty)
        return CanvasSnapshot(mode: .aiSearch, label: label, content: AnyView(view))
    }

    // MARK: - Canvas typed text binding

    /// Stable Binding<String> for canvasTypedText — avoids type-checker complexity in body.
    private var typedTextBinding: Binding<String> {
        Binding(
            get: { self.appState.canvasTypedText },
            set: { self.appState.canvasTypedText = $0 }
        )
    }

    private var widgetAppearance: WidgetAppearance {
        WidgetAppearance(base: appState.widgetBase, style: appState.widgetStyle)
    }

    // MARK: - Log dot colour

    private func logDotColor(for component: LogComponent) -> Color {
        switch component {
        case .audio:                 return .green
        case .transcribe:            return Color(red: 0.2,  green: 0.78, blue: 0.56)
        case .cleaning:              return Color(red: 1.0,  green: 0.7,  blue: 0.1)
        case .pipeline:              return Color(red: 1.0,  green: 0.5,  blue: 0.1)
        case .analysis, .taskCreate: return Color(red: 0.49, green: 0.37, blue: 0.98)
        case .taskExec:              return Color(red: 0.58, green: 0.2,  blue: 0.92)
        case .qa:                    return Color(red: 0.2,  green: 0.6,  blue: 1.0)
        default:                     return Color.white.opacity(0.45)
        }
    }

    // MARK: - Toggle state helpers

    /// Reflects the Ollama toggle — independent of mode.
    private var isLocalModelEnabled: Bool { appState.isOllamaEnabled }

    /// Reflects the code execution toggle — independent of mode.
    private var isCodeEnabled: Bool { appState.isCodeExecutionEnabled }

    // MARK: - Idle subtitle helpers

    /// Text shown on the Analysis row when Ollama is ON but not actively processing.
    private var analysisIdleSubtitle: String {
        let tasks = appState.pipelineTasks.count
        let analyses = appState.transcriptAnalyses.count
        if tasks > 0 {
            return "\(tasks) task\(tasks == 1 ? "" : "s") found"
        } else if analyses > 0 {
            return "\(analyses) transcript\(analyses == 1 ? "" : "s") processed"
        }
        return "Ready"
    }

    /// Text shown on the Execution row when code exec is ON but nothing is running.
    private var executionIdleSubtitle: String {
        let running = appState.pipelineTasks.filter { $0.status == .ongoing }.count
        let queued  = appState.pipelineTasks.filter {
            $0.status == .upcoming || $0.status == .pending_approval
        }.count
        if running > 0 && queued > 0 { return "\(running) running · \(queued) queued" }
        if running > 0               { return "\(running) running" }
        if queued > 0                { return "\(queued) task\(queued == 1 ? "" : "s") queued" }
        let done = appState.pipelineTasks.filter { $0.status == .completed }.count
        if done > 0                  { return "\(done) completed" }
        return "Ready"
    }

    // MARK: - Live pipeline stage rows (matched by .kind)

    private var activePipelineStages: [WidgetStageRow] {
        var rows: [WidgetStageRow] = []

        if appState.isSessionProcessing {
            rows.append(WidgetStageRow(
                kind:  .analysis,
                icon:  "brain",
                color: Color(red: 0.25, green: 0.55, blue: 1.0),
                title: "Analysing",
                sub1:  "Llama 3.2B · LOCAL",
                sub2:  ""
            ))
        }

        if appState.codeIsStreaming {
            rows.append(WidgetStageRow(
                kind:  .execution,
                icon:  "chevron.left.forwardslash.chevron.right",
                color: Color(red: 0.58, green: 0.2, blue: 0.92),
                title: "Claude Code",
                sub1:  appState.codeCurrentToolName ?? "Running…",
                sub2:  appState.pipelineTasks.last?.projectName ?? ""
            ))
        }

        return rows
    }

    // MARK: - Dynamic canvas content  (mode state machine)
    //
    // The canvas is the primary interaction layer. Each mode has multiple states and
    // the AI can push arbitrary content here. Priority overlays (session config,
    // task execution, review) are checked first, then mode-specific content.

    private var canvasForCurrentMode: AnyView? {

        // ── Session config panel (highest priority overlay) ─────────────────────
        if appState.sessionLifecycle == .configuring {
            return AnyView(SessionConfigView(
                appState: appState,
                appearance: WidgetAppearance(
                    base:  appState.widgetBase,
                    style: appState.widgetStyle
                )
            ))
        }

        // ── Canvas task execution (streams Claude Code output inline) ────────────
        if let execTask = appState.canvasExecutingTask {
            return AnyView(TaskExecutionCanvasView(
                task:     execTask,
                appState: appState,
                onDone:   { appState.doneWithCanvasExecution() }
            ))
        }

        // ── Cleaning level picker (post-session transcript quality) ─────────────
        // Shown first — takes priority so the user always gets to refine their transcript
        // before seeing task review. Ambient review appears after cleaning picker is dismissed.
        if appState.showCleaningPicker {
            return AnyView(CleaningPickerCanvasView(
                results: appState.cleaningResults,
                selected: appState.selectedCleaningLevel,
                isProcessing: appState.isSessionProcessing,
                onSelect: { level in appState.selectCleaningLevel(level) },
                onDismiss: { appState.dismissCleaningPicker() }
            ))
        }

        // ── Post-session ambient review (task approval + project assignment) ────────
        if let review = appState.ambientReview {
            let reviewTasks = appState.pipelineTasks.filter {
                review.sessionTaskIDs.contains($0.id) && $0.createdAt >= review.startedAt
            }
            return AnyView(AmbientSessionReviewView(
                review:          review,
                tasks:           reviewTasks,
                projects:        appState.projects,
                skills:          appState.skills,
                onApproveTask:   { id in appState.reviewApproveTask(id) },
                onSkipTask:      { id in appState.reviewSkipTask(id) },
                onApproveAll:    { appState.approveAllReviewTasks() },
                onSelectProject: { project in appState.reviewSelectProject(project) },
                onDone:          { appState.dismissAmbientReview() }
            ))
        }

        // ── FUCBC capability suggestion ("Automate now") ──────────────────────────
        if case .capability(let match) = appState.detectedSuggestion {
            return AnyView(CapabilitySuggestionCanvasView(
                capability: match.capability,
                onRun:     { appState.executeCapability(match.capability) },
                onDismiss: { appState.dismissDetectedSuggestion() }
            ))
        }

        // ── Mode-specific state machines ─────────────────────────────────────────
        return modeSpecificCanvas
    }

    /// Extracted to a separate property so the compiler can type-check it independently.
    private var modeSpecificCanvas: AnyView? {
        let typed = typedTextBinding
        switch appState.pillMode {
        case .ambient:
            let v = AmbientCanvasView(
                cleanedText:  appState.liveTranscriptText,
                pendingText:  appState.pendingRawSegment,
                incomingText: appState.latestTranscriptChunk,
                typedText:    typed
            )
            return AnyView(v)
        case .aiSearch:
            let item = appState.qaStore.items.first
            let v = AISearchCanvasView(
                question:  item?.question ?? "",
                answer:    item?.answer   ?? "",
                typedText: typed
            )
            return AnyView(v)
        case .learn:
            // Learn mode pill shows a minimal waveform indicator;
            // the full canvas is in the panel's Canvas tab.
            let v = AmbientCanvasView(
                cleanedText:  "",
                pendingText:  "",
                incomingText: "Learning…",
                typedText:    typed
            )
            return AnyView(v)
        }
    }
}
