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
    private var setupWindow: SetupWindow?
    private var toastDismissWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppFonts.registerAll()   // register custom fonts before any views render
        NSApp.setActivationPolicy(.accessory)
        appState.applicationDidFinishLaunching()
        appState.onShowSetup = { [weak self] in Task { @MainActor in self?.showSetupWindowSync() } }

        showPill()

        // Show first-run setup if dependencies are missing
        showSetupIfNeeded()

        // Request all required permissions upfront (mic + speech recognition).
        // On first launch this ensures permission dialogs fire before the first
        // recording attempt — preventing the first chunk from silently failing.
        requestPermissionsUpfront()

        // Toast window disabled — logs are now shown inline inside the widget.
        // AutoClawdLogger.toastPublisher
        //     .receive(on: DispatchQueue.main)
        //     .sink { [weak self] entry in self?.showToast(entry) }
        //     .store(in: &cancellables)

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
            onCollapseChange:    { [weak self] level in self?.pillWindow?.setCollapseLevel(level) },
            onCameraVisibilityChange: { [weak self] visible in self?.pillWindow?.showsCameraFeed = visible }
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
        menu.addItem(NSMenuItem(title: "Transcribe Mode  ⌃X", action: #selector(menuTranscribe), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Code Mode  ⌃D",      action: #selector(menuCode),       keyEquivalent: ""))
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
    @objc private func menuCode()         { appState.pillMode = .code }

    // MARK: - Toast

    private func showToast(_ entry: LogEntry) {
        guard appState.showToasts else { return }
        // Cancel any pending dismiss
        toastDismissWork?.cancel()

        // Create window on first use
        if toastWindow == nil {
            toastWindow = ToastWindow()
        }
        guard let toast = toastWindow, let pill = pillWindow else { return }

        // Update content
        toast.updateEntry(entry)

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

        // Camera (for gesture control and face tracking — optional)
        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if camStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    Log.info(.system, "Camera permission: \(granted ? "granted" : "denied")")
                }
            }
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
    let onCameraVisibilityChange: (Bool) -> Void

    @State private var isWhatsAppEnabled: Bool = SettingsManager.shared.whatsAppEnabled

    @State private var collapseLevel:          WidgetCollapseLevel = .full
    @State private var displayLevel:           Float = 0
    @State private var logLines:               [(dot: Color, text: String, time: String)] = []
    @State private var canvasSnapshots:        [CanvasSnapshot] = []
    @State private var prevTranscript:         String = ""
    @State private var prevQACount:            Int = 0
    @State private var prevTaskCount:          Int = 0
    /// True while the multi-speaker "who are you with?" prompt is active in the canvas.
    @State private var showMultiSpeakerPrompt: Bool = false

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
                if mode != .code && !appState.isListening { appState.startListening() }
            },
            onToggleLocalModel:     onToggleLocalModel,
            onToggleCode:           onToggleCode,
            onToggleSpeakerMode:    onToggleSpeakerMode,
            onToggleScreenShare:    onToggleScreenShare,
            onToggleCamera:         { appState.cameraEnabled.toggle() },
            onToggleWhatsApp: {
                SettingsManager.shared.whatsAppEnabled.toggle()
                isWhatsAppEnabled = SettingsManager.shared.whatsAppEnabled
            },
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
            isCameraEnabled:        appState.cameraEnabled,
            isWhatsAppEnabled:      isWhatsAppEnabled,
            sessionLifecycle:       appState.sessionLifecycle,
            logLines:               logLines,
            isSessionProcessing:    appState.isSessionProcessing,
            isExecutionGlowActive:  appState.canvasExecutingTask != nil,
            aiCanvasContent:        canvasForCurrentMode,
            analysisIdleSubtitle:   analysisIdleSubtitle,
            executionIdleSubtitle:  executionIdleSubtitle,
            canvasSnapshots:        canvasSnapshots,
            appearance:             widgetAppearance,
            cameraFeedContent:      cameraFeedView
        )
        .onChange(of: collapseLevel) { level in onCollapseChange(level) }
        .onChange(of: appState.cameraEnabled) { enabled in
            let feedVisible = (enabled && appState.cameraService.isRunning) || appState.systemAudioEnabled
            onCameraVisibilityChange(feedVisible)
            onCollapseChange(collapseLevel)
        }
        .onChange(of: appState.cameraService.isRunning) { running in
            onCameraVisibilityChange((appState.cameraEnabled && running) || appState.systemAudioEnabled)
            onCollapseChange(collapseLevel)
        }
        .onChange(of: appState.systemAudioEnabled) { enabled in
            let feedVisible = enabled || (appState.cameraEnabled && appState.cameraService.isRunning)
            onCameraVisibilityChange(feedVisible)
            onCollapseChange(collapseLevel)
        }
        .onChange(of: appState.isAmbientReviewActive) { isActive in
            // Expand pill when the post-session review canvas opens; shrink back when done.
            withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                collapseLevel = isActive ? .expanded : .full
            }
            onCollapseChange(isActive ? .expanded : .full)
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
            let label = "\(Self.snapTimeFmt.string(from: Date())) · \(appState.pillMode.shortLabel)"
            let snapshot = CanvasSnapshot(
                mode:    appState.pillMode,
                label:   label,
                content: AnyView(AmbientCanvasView(
                    cleanedText:  appState.liveTranscriptText,
                    pendingText:  "",
                    incomingText: prevTranscript
                ))
            )
            canvasSnapshots = Array(([snapshot] + canvasSnapshots).prefix(8))
            prevTranscript = newChunk
        }
        // Canvas history: capture snapshot when a new QA answer arrives
        .onChange(of: appState.qaStore.items.count) { count in
            guard count > prevQACount, let item = appState.qaStore.items.first else {
                prevQACount = count; return
            }
            let label = "\(Self.snapTimeFmt.string(from: Date())) · Q"
            let snapshot = CanvasSnapshot(
                mode:    .aiSearch,
                label:   label,
                content: AnyView(AISearchCanvasView(question: item.question, answer: item.answer))
            )
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
                    projectName:     appState.tasksSelectedProject?.name
                        ?? appState.codeSelectedProject?.name
                ))
            )
            canvasSnapshots = Array(([snapshot] + canvasSnapshots).prefix(8))
            prevTaskCount = count
        }
        // Smart prompt: show multi-speaker "who are you with?" when switching to multi
        .onChange(of: appState.speakerMode) { mode in
            showMultiSpeakerPrompt = (mode == .multiple)
        }
    }

    // MARK: - Camera feed

    private var widgetAppearance: WidgetAppearance {
        WidgetAppearance(base: appState.widgetBase, style: appState.widgetStyle)
    }

    private var cameraFeedView: AnyView? {
        let cameraOn = appState.cameraEnabled && appState.cameraService.isRunning
        let screenOn = appState.systemAudioEnabled
        guard cameraOn || screenOn else { return nil }
        return AnyView(CameraFeedWidget(appState: appState, appearance: widgetAppearance))
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
                sub2:  appState.codeSelectedProject?.name ?? ""
            ))
        }

        return rows
    }

    // MARK: - Dynamic canvas content  (mode state machine)
    //
    // The canvas is the primary interaction layer. Each mode has multiple states and
    // the AI can push arbitrary content here. Smart prompts (e.g. multi-speaker)
    // take priority and temporarily overlay the mode's normal content.

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

        // ── Session project picker (gesture-triggered session start) ──────────────
        if appState.showSessionProjectPicker {
            return AnyView(SessionProjectPickerCanvasView(
                projects: appState.projects,
                onSelect: { project in
                    appState.showSessionProjectPicker = false
                    var config = SessionConfig()
                    config.projectID = project.id
                    config.projectName = project.name
                    appState.startUserSession(config: config)
                },
                onSkip: {
                    appState.showSessionProjectPicker = false
                    appState.startUserSession(config: SessionConfig())
                }
            ))
        }

        // ── Face linking canvas (auto-triggered or manual) ────────────────────────
        if appState.showFaceLinkingOverlay {
            return AnyView(FaceLinkingCanvasView(appState: appState))
        }

        // ── Canvas task execution (streams Claude Code output inline) ────────────
        if let execTask = appState.canvasExecutingTask {
            return AnyView(TaskExecutionCanvasView(
                task:     execTask,
                appState: appState,
                onDone:   { appState.doneWithCanvasExecution() }
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

        // ── Cleaning level picker (post-session transcript quality) ─────────────
        if appState.showCleaningPicker {
            return AnyView(CleaningPickerCanvasView(
                results: appState.cleaningResults,
                selected: appState.selectedCleaningLevel,
                isProcessing: appState.isSessionProcessing,
                onSelect: { level in appState.selectCleaningLevel(level) },
                onDismiss: { appState.dismissCleaningPicker() }
            ))
        }

        // ── Smart prompt: multi-speaker "who are you with?" ──────────────────────
        if showMultiSpeakerPrompt {
            return AnyView(MultiSpeakerPromptCanvasView(
                people:      appState.people,
                onSelect: { person in
                    appState.currentSpeakerID = person.id
                    showMultiSpeakerPrompt = false
                },
                onAddPerson: onOpenPanel,
                onSkip:      { showMultiSpeakerPrompt = false }
            ))
        }

        // ── Mode-specific state machines ─────────────────────────────────────────
        switch appState.pillMode {

        case .ambientIntelligence:
            return AnyView(AmbientCanvasView(
                cleanedText:  appState.liveTranscriptText,
                pendingText:  appState.pendingRawSegment,
                incomingText: appState.latestTranscriptChunk
            ))

        case .transcription:
            return AnyView(TranscriptCanvasView(
                cleanedText:  appState.liveTranscriptText,
                pendingText:  appState.pendingRawSegment,
                incomingText: appState.latestTranscriptChunk,
                onApply: { appState.applyLatestTranscript() },
                onClear: { appState.clearSessionTranscript() }
            ))

        case .aiSearch:
            let item = appState.qaStore.items.first
            return AnyView(AISearchCanvasView(
                question: item?.question ?? "",
                answer:   item?.answer   ?? ""
            ))

        case .tasks:
            // State 1: no project → picker
            guard let proj = appState.tasksSelectedProject else {
                return AnyView(ProjectPickerCanvasView(
                    projects: appState.projects,
                    title:    "Select project · Tasks",
                    onSelect: { appState.tasksSelectedProject = $0 }
                ))
            }
            // State 2: project selected → active tasks view
            let task = appState.pipelineTasks.last
            return AnyView(TasksCanvasView(
                latestTaskTitle: task?.title ?? "",
                taskCount:       appState.pipelineTasks.count,
                projectName:     proj.name
            ))

        case .code:
            switch appState.codeWidgetStep {
            case .projectSelect:
                // State 1: no project → picker
                guard let proj = appState.codeSelectedProject else {
                    return AnyView(ProjectPickerCanvasView(
                        projects: appState.projects,
                        title:    "Select project · Code",
                        onSelect: { appState.codeSelectedProject = $0 }
                    ))
                }
                // State 2: project chosen → confirm + auto/ask + start
                return AnyView(CodeSetupCanvasView(
                    project:             proj,
                    skipPermissions:     appState.codeSkipPermissions,
                    onTogglePermissions: { appState.codeSkipPermissions.toggle() },
                    onStart:             { appState.startCodeSession() },
                    onChangeProject:     { appState.codeSelectedProject = nil }
                ))
            case .copilot:
                // State 3: session running → streaming status
                return AnyView(CodeCanvasView(appState: appState))
            }
        }
    }
}
