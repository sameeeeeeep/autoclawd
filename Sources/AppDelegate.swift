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
    private var onboardingWindow: OnboardingWindow?
    private var callStreamWidget: CallStreamWidget?
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

        // Start embedded MCP server so any Claude Code session can call screen-grab tools.
        // Configure Claude Code with: { "mcpServers": { "autoclawd": { "type": "http", "url": "http://localhost:7892/mcp" } } }
        let screenGrab = ScreenGrabService()
        MCPServer.shared.start(
            screenGrab: screenGrab,
            transcriptProvider: { [weak self] in self?.appState.liveTranscriptText ?? "" },
            isPausedProvider:   { [weak self] in !(self?.appState.callRoom.claudeCodeIsActive ?? true) },
            canvasWriter: { [weak self] text in self?.appState.callModeSession.appendExternalMessage(text) },
            onJoined: { [weak self] in self?.appState.callRoom.claudeCodeJoined() },
            onLeft:   { [weak self] in self?.appState.callRoom.claudeCodeLeft() },
            onInviteParticipant: { [weak self] id, name, icon in
                self?.appState.callRoom.connectionJoined(id: id, name: name, systemImage: icon)
            },
            onSetParticipantState: { [weak self] id, stateStr in
                guard let room = self?.appState.callRoom else { return }
                let state: ParticipantState
                switch stateStr {
                case "thinking":  state = .thinking
                case "streaming": state = .streaming
                case "paused":    state = .paused
                default:          state = .idle
                }
                room.setState(state, for: id)
            },
            onParticipantMessage: { [weak self] id, name, text in
                self?.appState.callModeSession.appendParticipantMessage(id: id, name: name, text: text)
            },
            onRemoveParticipant: { [weak self] id in
                self?.appState.callRoom.remove(id: id)
            },
            onHookEvent: { [weak self] event in
                guard let self else { return }
                Log.info(.system, "[Hook] Received: \(event.eventName) tool=\(event.toolName ?? "nil")")

                let room      = self.appState.callRoom
                let session   = self.appState.callModeSession
                let ttsPlayer = self.appState.ttsPlayer

                room.claudeCodeJoined()
                room.setState(.thinking, for: "claude-code")

                Task {
                    let bundle = await HookNarrationService().narrate(event)
                    Log.info(.system, "[Hook] Narration: \(bundle.turns.count) turns, text='\(bundle.narration.prefix(60))'")

                    await MainActor.run {
                        if let tp = bundle.toolParticipant {
                            room.connectionJoined(id: tp.id, name: tp.name, systemImage: tp.systemImage)
                        }

                        if !bundle.turns.isEmpty {
                            for turn in bundle.turns {
                                session.appendParticipantMessage(
                                    id:          turn.speakerID,
                                    name:        turn.speakerName,
                                    text:        turn.text,
                                    isGenerated: turn.isGenerated
                                )
                            }
                        } else {
                            session.appendParticipantMessage(
                                id: "claude-code", name: "Claw'd",
                                text: bundle.narration, isGenerated: false
                            )
                            if let reaction = bundle.autoClawdReaction {
                                session.appendParticipantMessage(
                                    id: "llama", name: "AutoClawd",
                                    text: reaction, isGenerated: true
                                )
                            }
                        }

                        room.setState(event.isStop ? .idle : .streaming, for: "claude-code")

                        if let tp = bundle.toolParticipant {
                            if bundle.imageData != nil || bundle.toolResponseText != nil {
                                room.setState(.streaming, for: tp.id)
                                session.appendParticipantMessage(
                                    id:          tp.id,
                                    name:        tp.name,
                                    text:        bundle.toolResponseText ?? "",
                                    imageData:   bundle.imageData,
                                    isGenerated: false
                                )
                                room.setState(.idle, for: tp.id)
                            } else {
                                room.updateLastActivity(id: tp.id)
                            }
                        }
                    }

                    // Synthesize TTS outside the MainActor block so it doesn't block UI
                    let provider = SettingsManager.shared.ttsProvider
                    Log.info(.system, "[TTS] Provider=\(provider.rawValue), turns=\(bundle.turns.count)")
                    if provider != .off {
                        let turnsToSpeak = !bundle.turns.isEmpty
                            ? bundle.turns
                            : [NarrationTurn(speakerID: "claude-code", speakerName: "Claw'd", text: bundle.narration, isGenerated: false)]
                        await self.synthesizeTTS(turns: turnsToSpeak, provider: provider, ttsPlayer: ttsPlayer)
                    }
                }
            }
        )

        // Auto-register Claude Code hooks so PostToolUse events arrive at /hook.
        MCPConfigManager.writeHooksConfig()

        // Configure call mode session with the same transcript provider.
        appState.callModeSession.configure(
            transcriptProvider: { [weak self] in self?.appState.liveTranscriptText ?? "" }
        )

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

        // Show/hide the Call Stream Widget when pill mode changes.
        // Also start/stop TTS sidecar when entering/leaving call mode.
        appState.$pillMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                guard let self else { return }
                Log.info(.system, "[CallMode] pillMode sink fired: \(mode.rawValue)")
                if mode == .callMode {
                    if SettingsManager.shared.callStreamWidgetEnabled {
                        self.showCallStreamWidget()
                    }
                    // Start TTS sidecar if using LuxTTS
                    if SettingsManager.shared.ttsProvider == .luxtts {
                        Log.info(.system, "[TTS] Starting TTS sidecar (provider=luxtts)")
                        TTSSidecar.shared.start()
                    }
                } else {
                    self.callStreamWidget?.animateOut()
                    self.appState.ttsPlayer.stopAll()
                    // Unload model to free RAM when leaving call mode
                    Task { await TTSService.shared.unloadModel() }
                }
            }
            .store(in: &cancellables)

        // Also handle the case where the app launches already in call mode
        // (the $pillMode publisher fires the initial value asynchronously,
        //  but just in case, explicitly check at startup)
        if appState.pillMode == .callMode {
            Log.info(.system, "[CallMode] Launched in call mode — starting sidecar")
            if SettingsManager.shared.ttsProvider == .luxtts {
                TTSSidecar.shared.start()
            }
        }
    }

    // MARK: - Call Stream Widget

    private func showCallStreamWidget() {
        if callStreamWidget == nil {
            let widget = CallStreamWidget()
            let view = CallStreamWidgetView(appState: appState) { [weak self] in
                self?.appState.pillMode = .ambientIntelligence
                self?.callStreamWidget?.animateOut()
            }
            widget.setContent(view)
            callStreamWidget = widget
        }
        callStreamWidget?.animateIn()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stopListening()
        ClipboardMonitor.shared.stop()
        TTSSidecar.shared.stop()
        Log.info(.system, "AutoClawd terminating")
    }

    // MARK: - TTS Synthesis

    /// Synthesize and enqueue TTS audio for each conversation turn.
    /// LuxTTS: all turns sent in one batch request — different voices synthesize in parallel.
    /// Apple: sequential (AVSpeechSynthesizer is synchronous).
    private func synthesizeTTS(turns: [NarrationTurn], provider: TTSProvider, ttsPlayer: TTSPlayer) async {
        Log.info(.system, "[TTS] synthesizeTTS called: \(turns.count) turns, provider=\(provider.rawValue)")

        switch provider {
        case .luxtts:
            let batchTurns = turns.map { turn -> TTSService.BatchTurn in
                let voiceID = turn.speakerID == "claude-code" ? "clawd" : "autoclawd"
                Log.info(.system, "[TTS] Queuing voice=\(voiceID) text='\(turn.text.prefix(40))'")
                return TTSService.BatchTurn(text: turn.text, voiceID: voiceID)
            }
            let audioResults = await TTSService.shared.synthesizeBatch(
                turns: batchTurns,
                speed: SettingsManager.shared.ttsSpeed
            )
            Log.info(.system, "[TTS] Batch returned \(audioResults.compactMap { $0 }.count)/\(turns.count) audio clips")
            var anyFailed = false
            for (i, audioData) in audioResults.enumerated() {
                let turn = turns[i]
                let voiceID = batchTurns[i].voiceID
                if let audioData {
                    Log.info(.system, "[TTS] Turn \(i) (\(voiceID)): \(audioData.count) bytes")
                    await MainActor.run { ttsPlayer.enqueue(voiceID: voiceID, audioData: audioData) }
                } else {
                    anyFailed = true
                    Log.warn(.system, "[TTS] Turn \(i) (\(voiceID)) failed — falling back to Apple")
                    await withCheckedContinuation { cont in
                        AppleTTSService.shared.speak(text: turn.text, voiceID: voiceID) { cont.resume() }
                    }
                }
            }
            if anyFailed {
                Log.warn(.system, "[TTS] Some turns fell back to Apple TTS")
            }

        case .apple:
            for (i, turn) in turns.enumerated() {
                let voiceID = turn.speakerID == "claude-code" ? "clawd" : "autoclawd"
                Log.info(.system, "[TTS] Apple turn \(i): voice=\(voiceID) text='\(turn.text.prefix(40))'")
                await withCheckedContinuation { cont in
                    AppleTTSService.shared.speak(text: turn.text, voiceID: voiceID) { cont.resume() }
                }
            }

        case .off:
            break
        }
        Log.info(.system, "[TTS] synthesizeTTS complete")
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
        menu.addItem(NSMenuItem(title: "Meeting Mode  ⌃D",   action: #selector(menuMeeting),    keyEquivalent: ""))
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
    @objc private func menuMeeting()      { appState.pillMode = .meeting; if !appState.isListening { appState.startListening() } }

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
                if !appState.isListening { appState.startListening() }
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
        // Smart prompt: show multi-speaker "who are you with?" when switching to multi
        .onChange(of: appState.speakerMode) { mode in
            showMultiSpeakerPrompt = (mode == .multiple)
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
                sub2:  appState.pipelineTasks.last?.projectName ?? ""
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

        // ── FUCBC capability suggestion (Cofia-style "Automate now") ─────────────
        if let cap = appState.detectedCapability {
            return AnyView(CapabilitySuggestionCanvasView(
                capability: cap,
                onRun:     { appState.executeCapability(cap) },
                onDismiss: { appState.dismissDetectedCapability() }
            ))
        }

        // ── Mode-specific state machines ─────────────────────────────────────────
        return modeSpecificCanvas
    }

    /// Extracted to a separate property so the compiler can type-check it independently.
    private var modeSpecificCanvas: AnyView? {
        let typed = typedTextBinding
        switch appState.pillMode {
        case .ambientIntelligence:
            let v = AmbientCanvasView(
                cleanedText:  appState.liveTranscriptText,
                pendingText:  appState.pendingRawSegment,
                incomingText: appState.latestTranscriptChunk,
                typedText:    typed
            )
            return AnyView(v)
        case .transcription:
            let v = TranscriptCanvasView(
                cleanedText:  appState.liveTranscriptText,
                pendingText:  appState.pendingRawSegment,
                incomingText: appState.latestTranscriptChunk,
                onApply:      { self.appState.applyLatestTranscript() },
                onClear:      { self.appState.clearSessionTranscript() },
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
        case .meeting:
            let v = MeetingCanvasView(
                cleanedText:  appState.liveTranscriptText,
                pendingText:  appState.pendingRawSegment,
                incomingText: appState.latestTranscriptChunk,
                typedText:    typed
            )
            return AnyView(v)
        case .callMode:
            let v = CallModeCanvasView(session: appState.callModeSession)
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
