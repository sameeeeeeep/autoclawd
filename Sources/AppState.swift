import AVFoundation
import Combine
import Foundation
import SwiftUI

// MARK: - ExecutionMode

enum ExecutionMode: String, CaseIterable {
    case parallel = "parallel"
    case series = "series"

    var displayName: String {
        switch self {
        case .parallel: return "Parallel"
        case .series: return "Series"
        }
    }
}

// MARK: - Code Widget Models

enum CodeWidgetStep {
    case projectSelect
    case copilot
}

struct CodeMessage: Identifiable {
    let id = UUID()
    let role: Role
    var text: String

    enum Role { case user, assistant, tool, status, error }
}

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {

    // MARK: - Published State

    @Published var pillState: PillState = .listening
    @Published var isListening = false
    @Published var audioLevel: Float = 0.0

    @Published var transcriptionMode: TranscriptionMode {
        didSet {
            SettingsManager.shared.transcriptionMode = transcriptionMode
            rebuildTranscriptionService()
            Log.info(.system, "Transcription mode changed to \(transcriptionMode.rawValue)")
        }
    }

    @Published var micEnabled: Bool {
        didSet {
            SettingsManager.shared.micEnabled = micEnabled
            if micEnabled { startListening() } else { stopListening() }
        }
    }

    @Published var audioRetentionDays: Int {
        didSet { SettingsManager.shared.audioRetentionDays = audioRetentionDays }
    }

    @Published var groqAPIKey: String {
        didSet {
            SettingsManager.shared.groqAPIKey = groqAPIKey
            rebuildTranscriptionService()
        }
    }

    @Published var pillMode: PillMode {
        didSet {
            UserDefaults.standard.set(pillMode.rawValue, forKey: "pillMode")
            chunkManager.pillMode = pillMode
            // Force a new audio chunk on mode change so the new mode gets clean context.
            chunkManager.forceNewChunk()
            // (code mode removed — no code widget reset needed)
            // Transcript accumulates across all modes within a session.
            // clearSessionTranscript() is called only on new session start or manual Clear.
            // Mode changes never clear the transcript — text stays visible.
            Log.info(.system, "Pill mode → \(pillMode.rawValue)")
            // Learn mode: auto-start/stop session when entering/leaving .learn
            if pillMode == .learn {
                learnModeService.startSession()
            } else if oldValue == .learn {
                learnModeService.stopSession()
            }
            // Sync OCR interval with mode
            screenVisionAnalyzer.isLearnMode = (pillMode == .learn)
        }
    }

    // MARK: - Pipeline Control Toggles

    /// When false, Ollama analysis/task-creation stages are skipped after cleaning.
    @Published var isOllamaEnabled: Bool {
        didSet { SettingsManager.shared.isOllamaEnabled = isOllamaEnabled }
    }

    /// When false, auto tasks are created but never sent to Claude Code for execution.
    @Published var isCodeExecutionEnabled: Bool {
        didSet { SettingsManager.shared.isCodeExecutionEnabled = isCodeExecutionEnabled }
    }

    // MARK: - Conversation Context

    /// How many speakers are expected — informs cleaning/analysis prompts.
    enum SpeakerMode: String { case single, multiple }

    @Published var speakerMode: SpeakerMode {
        didSet {
            SettingsManager.shared.speakerMode = speakerMode.rawValue
            // Clear active speaker when returning to single-speaker mode
            if speakerMode == .single { currentSpeakerID = nil }
        }
    }

    /// Project selected for Tasks mode (nil = show project picker in canvas).
    @Published var tasksSelectedProject: Project? = nil

    /// Text typed (or auto-pasted from clipboard) into the AI canvas during a session.
    /// Accumulated alongside spoken transcript; included in pipeline at session end.
    @Published var canvasTypedText: String = ""

    /// Whether background music is likely present (enables Shazam detection).
    @Published var musicModeEnabled: Bool {
        didSet { SettingsManager.shared.musicModeEnabled = musicModeEnabled }
    }

    @Published var showAmbientWidget: Bool {
        didSet { SettingsManager.shared.showAmbientWidget = showAmbientWidget }
    }

    @Published var showToasts: Bool {
        didSet { SettingsManager.shared.showToasts = showToasts }
    }

    @Published var appearanceMode: AppearanceMode {
        didSet { SettingsManager.shared.appearanceMode = appearanceMode }
    }

    @Published var fontSizePreference: FontSizePreference {
        didSet { SettingsManager.shared.fontSizePreference = fontSizePreference }
    }

    @Published var widgetBase: WidgetBase {
        didSet { SettingsManager.shared.widgetBase = widgetBase }
    }

    @Published var widgetStyle: WidgetStyle {
        didSet { SettingsManager.shared.widgetStyle = widgetStyle }
    }

    // MARK: - People roster & speaker tagging

    @Published var people: [Person] {
        didSet { savePeople() }
    }

    /// Transient — which person is currently speaking (nil = unknown).
    @Published var currentSpeakerID: UUID? = nil
    /// Transient — current song title set by NowPlayingService via Combine; nil when nothing is playing.
    @Published var nowPlayingSongTitle: String? = nil
    /// Transient — FUCBC auto-trigger: capability detected from screen context (nil = no match).
    @Published var detectedSuggestion: SuggestionItem? = nil {
        didSet {
            // Keep activeQuestion in sync for voice-answer matching
            if case .question(let q) = detectedSuggestion {
                activeQuestion = q
            } else if detectedSuggestion == nil {
                activeQuestion = nil
            }
            // Record in history when a new suggestion appears
            if let item = detectedSuggestion {
                let entry = SuggestionHistoryEntry(item: item, shownAt: Date())
                suggestionHistory.insert(entry, at: 0)
                if suggestionHistory.count > 20 { suggestionHistory = Array(suggestionHistory.prefix(20)) }
            }
        }
    }
    /// The currently-displayed question toast (if any). Used for voice-answer matching.
    @Published var activeQuestion: SuggestionQuestion? = nil
    /// Rolling history of all suggestions shown (most recent first).
    @Published var suggestionHistory: [SuggestionHistoryEntry] = []
    /// Active tab in the main panel — set by AppDelegate.showMainPanel(tab:) to drive tab selection.
    @Published var activeTab: PanelTab = .agents

    @Published var locationName: String {
        didSet { UserDefaults.standard.set(locationName, forKey: "autoclawd.locationName") }
    }

    @Published var pendingUnknownSSID: String? = nil
    @Published var wifiLabelInput: String = ""

    @Published var extractionItems: [ExtractionItem] = []
    @Published var pendingExtractionCount: Int = 0
    @Published var synthesizeThreshold: Int {
        didSet { SettingsManager.shared.synthesizeThreshold = synthesizeThreshold }
    }

    /// Plain-English rules describing tasks that can run autonomously without user approval.
    @Published var autonomousTaskRules: [String] {
        didSet { SettingsManager.shared.autonomousTaskRules = autonomousTaskRules }
    }
    @Published var isCleaningUp = false

    @Published var projects: [Project] = []
    @Published var structuredTodos: [StructuredTodo] = []

    // Pipeline v2 published state
    @Published var cleanedTranscripts: [CleanedTranscript] = []
    @Published var transcriptAnalyses: [TranscriptAnalysis] = []
    @Published var pipelineTasks: [PipelineTaskRecord] = []
    @Published var skills: [Skill] = []

    /// True while session-end pipeline processing is active (cleaning or analysis).
    /// Used by the widget to glow the Analysis status row.
    @Published var isSessionProcessing = false

    // Widget live data — latest transcript chunk for the floating widget
    @Published var latestTranscriptChunk: String = ""
    /// Committed chunk text that is awaiting Ollama cleaning (shown at medium opacity).
    /// Cleared when the cleaned version arrives via appendRawTranscript().
    @Published var pendingRawSegment: String = ""
    /// Accumulated RAW transcript text for the current session.
    /// No Ollama cleaning per-chunk — raw text accumulates during recording.
    /// Cleaned once at session end via processSessionEnd().
    @Published var liveTranscriptText: String = ""

    // MARK: - User-Defined Session State
    @Published var sessionLifecycle: SessionLifecycleState = .undefined
    @Published var sessionConfig: SessionConfig?

    // Code widget state
    @Published var codeWidgetStep: CodeWidgetStep = .projectSelect
    @Published var codeSelectedProject: Project? = nil
    @Published var codeSessionMessages: [CodeMessage] = []
    @Published var codeIsStreaming: Bool = false
    @Published var codeCurrentToolName: String? = nil
    @Published var codeSkipPermissions: Bool = true
    private(set) var codeSession: ClaudeSession? = nil
    private var codeStreamTask: Task<Void, Never>? = nil
    var codeTaskID: String?
    private var codeStepIndex: Int = 0

    // System audio state
    @Published var systemAudioEnabled: Bool {
        didSet {
            SettingsManager.shared.systemAudioEnabled = systemAudioEnabled
            if systemAudioEnabled { startSystemAudio() } else { stopSystemAudio() }
        }
    }
    @Published var systemAudioLevel: Float = 0
    /// Most recent on-demand screen snapshot (set by captureScreenNow / captureWithSelectionNow).
    @Published var lastScreenSnapshot: ScreenSnapshot? = nil

    @Published var showSessionProjectPicker: Bool = false
    @Published var showCleaningPicker: Bool = false
    @Published var cleaningResults: [CleaningLevel: String] = [:]
    @Published var selectedCleaningLevel: CleaningLevel = .minimal

    // MARK: - Ambient Review
    /// Non-nil when a just-ended ambient session is awaiting task review on the pill canvas.
    @Published var ambientReview: AmbientReviewState? = nil
    /// Computed convenience for `onChange` observation.
    var isAmbientReviewActive: Bool { ambientReview != nil }

    // MARK: - Canvas Task Execution
    /// Non-nil while a pipeline task is streaming on the pill canvas.
    /// Execution output is delivered via the existing codeSessionMessages / codeIsStreaming machinery.
    @Published var canvasExecutingTask: PipelineTaskRecord? = nil

    // MARK: - Workflow Execution State
    /// Non-nil while a workflow is executing.
    @Published var executingWorkflow: WorkflowRecord? = nil
    @Published var workflowStepLogs: [WorkflowStepLog] = []
    @Published var workflowCurrentStep: Int = 0
    @Published var workflowTotalSteps: Int = 0
    @Published var workflowStepText: String = ""
    let workflowExecutor = WorkflowExecutor()
    let workflowBuilder = WorkflowBuilder()
    private var workflowTask: Task<Void, Never>? = nil

    // MARK: - Services

    private let storage = FileStorageManager.shared
    let chunkManager: ChunkManager
    private(set) var projectStore: ProjectStore
    private(set) var structuredTodoStore: StructuredTodoStore
    let locationService = LocationService.shared
    let nowPlaying = NowPlayingService()
    let shazam = ShazamKitService()
    private let ollama = OllamaService()
    private lazy var todoFramingService = TodoFramingService(ollama: ollama)
    private let worldModelService = WorldModelService()
    private let todoService = TodoService()
    private(set) var transcriptionService: (any Transcribable)?
    let transcriptStore: TranscriptStore
    let extractionStore: ExtractionStore
    private let extractionService: ExtractionService
    private let cleanupService: CleanupService
    private(set) var qaService: QAService
    let qaStore: QAStore
    let claudeCodeRunner = ClaudeCodeRunner()

    let screenVisionAnalyzer = ScreenVisionAnalyzer()
    let learnModeService = LearnModeService()
    let suggestionPipeline = SuggestionPipeline()

    // Pipeline v2 services
    let pipelineStore: PipelineStore
    let skillStore: SkillStore
    private(set) var pipelineOrchestrator: PipelineOrchestrator
    private let taskExecutionService: TaskExecutionService
    private var cleaningService: TranscriptCleaningService!

    // MARK: - Derived Content (refreshed on demand)

    var todosContent: String { todoService.read() }
    var worldModelContent: String { worldModelService.read() }

    /// Build rich context for QA assistant from all data sources.
    func buildQAContext() async -> QAContext {
        let sessionCtx = SessionStore.shared.buildContextBlock(
            currentSSID: LocationService.shared.currentSSID
        )
        let world = worldModelService.read()
        let projects = projectStore.all().map { (name: $0.name, tags: $0.tagsString) }
        let analyses = pipelineStore.fetchRecentAnalyses(limit: 5).map { a in
            (summary: a.summary,
             people: a.personNames.joined(separator: ", "),
             project: a.projectName)
        }
        let tasks = pipelineStore.fetchRecentTasks(limit: 10).map { t in
            (title: t.title, status: t.status.rawValue, project: t.projectName)
        }
        let todos = todoService.read()
        let sTodos = structuredTodoStore.all().map { t in
            (content: t.content, priority: t.priority, done: t.isExecuted)
        }
        let facts = extractionStore.all()
            .filter { $0.isAccepted }
            .suffix(50)
            .map { (content: $0.content, bucket: $0.bucket.rawValue) }

        return QAContext(
            sessionContext: sessionCtx,
            worldModel: world,
            projects: projects,
            recentAnalyses: analyses,
            recentTasks: tasks,
            todos: todos,
            structuredTodos: sTodos,
            extractionFacts: facts
        )
    }

    // MARK: - Init

    init() {
        let settings = SettingsManager.shared

        transcriptionMode      = settings.transcriptionMode
        micEnabled             = settings.micEnabled
        audioRetentionDays     = settings.audioRetentionDays
        groqAPIKey             = settings.groqAPIKey
        synthesizeThreshold    = settings.synthesizeThreshold
        autonomousTaskRules    = settings.autonomousTaskRules
        showAmbientWidget      = settings.showAmbientWidget
        showToasts             = settings.showToasts
        appearanceMode         = settings.appearanceMode
        fontSizePreference     = settings.fontSizePreference
        widgetBase             = settings.widgetBase
        widgetStyle            = settings.widgetStyle
        isOllamaEnabled        = settings.isOllamaEnabled
        isCodeExecutionEnabled = settings.isCodeExecutionEnabled
        speakerMode            = SpeakerMode(rawValue: settings.speakerMode) ?? .single
        musicModeEnabled       = settings.musicModeEnabled
        systemAudioEnabled     = settings.systemAudioEnabled
        self.people       = AppState.init_loadPeople()
        self.locationName = UserDefaults.standard.string(forKey: "autoclawd.locationName") ?? "My Room"

        let savedMode = UserDefaults.standard.string(forKey: "pillMode")
            .flatMap { PillMode(rawValue: $0) } ?? .ambient
        pillMode = savedMode

        transcriptStore = TranscriptStore(url: FileStorageManager.shared.transcriptsDatabaseURL)
        let root = FileStorageManager.shared.rootDirectory
        projectStore        = ProjectStore(url: root.appendingPathComponent("projects.db"))
        structuredTodoStore = StructuredTodoStore(url: root.appendingPathComponent("structured_todos.db"))
        projects            = projectStore.all()
        structuredTodos     = structuredTodoStore.all()

        let exStore = ExtractionStore(url: FileStorageManager.shared.intelligenceDatabaseURL)
        extractionStore = exStore
        let cleanupSvc = CleanupService(
            ollama: ollama,
            worldModel: worldModelService,
            todos: todoService,
            store: exStore
        )
        cleanupService = cleanupSvc
        extractionService = ExtractionService(
            ollama: ollama,
            worldModel: worldModelService,
            todos: todoService,
            store: exStore,
            cleanup: cleanupSvc
        )
        qaService    = QAService(ollama: OllamaService())
        qaStore      = QAStore()
        chunkManager = ChunkManager()

        // Pipeline v2 services
        let pStore = PipelineStore(url: FileStorageManager.shared.pipelineDatabaseURL)
        pipelineStore = pStore
        let sStore = SkillStore(directory: FileStorageManager.shared.skillsDirectory)
        skillStore = sStore
        skills = sStore.all()

        let pipelineOllama = OllamaService()
        let cleaningSvc = TranscriptCleaningService(
            ollama: pipelineOllama, transcriptStore: transcriptStore,
            pipelineStore: pStore, skillStore: sStore
        )
        let analysisSvc = TranscriptAnalysisService(
            ollama: pipelineOllama, projectStore: projectStore,
            pipelineStore: pStore, skillStore: sStore
        )
        let taskCreationSvc = TaskCreationService(
            ollama: pipelineOllama, pipelineStore: pStore,
            skillStore: sStore, workflowRegistry: WorkflowRegistry.shared,
            projectStore: projectStore
        )
        let taskExecSvc = TaskExecutionService(
            pipelineStore: pStore, claudeCodeRunner: claudeCodeRunner,
            projectStore: projectStore, skillStore: sStore
        )
        cleaningService = cleaningSvc
        taskExecutionService = taskExecSvc
        pipelineOrchestrator = PipelineOrchestrator(
            cleaningService: cleaningSvc,
            analysisService: analysisSvc,
            taskCreationService: taskCreationSvc,
            taskExecutionService: taskExecSvc
        )
        // Wire up UI refresh when execution steps change
        taskExecSvc.onStepUpdated = { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshPipeline()
            }
        }

        setupLogger()
        buildTranscriptionService()
        configureChunkManager()

        // Forward mic buffers to ShazamKit for recognition
        chunkManager.setBufferHandler { [weak self] buf in
            Task { @MainActor [weak self] in
                self?.shazam.process(buf)
            }
        }

        // Display Shazam-detected title when music dot is active and NowPlaying isn't running
        shazam.$currentTitle
            .receive(on: RunLoop.main)
            .sink { [weak self] title in
                guard let self, !self.nowPlaying.isPlaying else { return }
                guard let musicPerson = self.people.first(where: { $0.isMusic }),
                      self.currentSpeakerID == musicPerson.id else { return }
                self.nowPlayingSongTitle = title
            }
            .store(in: &cancellables)

        // Start/stop Shazam based on whether the Music dot is the active speaker
        $currentSpeakerID
            .receive(on: RunLoop.main)
            .sink { [weak self] id in
                guard let self else { return }
                let musicPerson = self.people.first(where: { $0.isMusic })
                if id == musicPerson?.id {
                    self.shazam.start()
                } else {
                    self.shazam.stop()
                    if !self.nowPlaying.isPlaying {
                        self.nowPlayingSongTitle = nil
                    }
                }
            }
            .store(in: &cancellables)

        // Auto-activate Music person when NowPlayingService detects a song
        nowPlaying.$isPlaying
            .combineLatest(nowPlaying.$currentTitle)
            .receive(on: RunLoop.main)  // defensive: both types are @MainActor, but explicit is clearer
            .sink { [weak self] isPlaying, title in
                guard let self else { return }
                guard let musicPerson = self.people.first(where: { $0.isMusic }) else { return }
                if isPlaying {
                    self.currentSpeakerID    = musicPerson.id
                    self.nowPlayingSongTitle = title
                } else {
                    self.nowPlayingSongTitle = nil
                    if self.currentSpeakerID == musicPerson.id {
                        self.currentSpeakerID = nil
                    }
                }
            }
            .store(in: &cancellables)

        // Voice answers to question toasts:
        // When a question is visible, monitor live transcript for option matches.
        // First spoken phrase that fuzzy-matches an option auto-selects it.
        $liveTranscriptText
            .receive(on: RunLoop.main)
            .sink { [weak self] fullText in
                guard let self,
                      let question = self.activeQuestion,
                      !fullText.isEmpty else { return }
                // Only examine the most recent ~10 words (tail of transcript)
                let words = fullText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                let tail = words.suffix(12).joined(separator: " ").lowercased()
                for option in question.options where option.lowercased() != "not relevant" {
                    let norm = option.lowercased()
                        .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
                    // Match if all significant words of the option appear in the spoken tail
                    let optionWords = norm.components(separatedBy: .whitespaces).filter { $0.count > 2 }
                    guard !optionWords.isEmpty else { continue }
                    let matchCount = optionWords.filter { tail.contains($0) }.count
                    if Double(matchCount) / Double(optionWords.count) >= 0.7 {
                        Log.info(.pipeline, "Voice answer matched: '\(option)'")
                        self.activeQuestion = nil
                        self.handleSuggestionQuestionOption(option, question: question)
                        return
                    }
                }
            }
            .store(in: &cancellables)

    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching() {
        Log.info(.system, "AutoClawd started. Mode: \(transcriptionMode.rawValue). RAM: (not measured)")
        // Wire screen analyzer into Learn Mode so it can capture on-demand snapshots
        learnModeService.screenAnalyzer = screenVisionAnalyzer
        // Refresh OpenClaw skill cache after FUCBC builds a new capability
        learnModeService.onCapabilityBuilt = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.skillStore.refreshOpenClawSkills()
                self?.refreshSkills()
            }
        }
        // Seed pre-built workflows on first run
        WorkflowStore.shared.seedPrebuiltWorkflowsIfNeeded()
        ClipboardMonitor.shared.start()
        ClipboardMonitor.shared.onTextCopied = { [weak self] text in
            guard let self, self.sessionLifecycle == .active else { return }
            // Append clipboard text to the canvas typed input with a newline separator
            if self.canvasTypedText.isEmpty {
                self.canvasTypedText = text
            } else {
                self.canvasTypedText += "\n" + text
            }
            Log.info(.system, "Clipboard text auto-pasted to canvas (\(text.count) chars)")
        }

        // Clipboard suggestion trigger — highest-intent signal (user explicitly copied something).
        // Fires for text and URLs in ambient mode; not during learn mode or active execution.
        ClipboardMonitor.shared.onContentCopied = { [weak self] type, _, full in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self,
                      self.pillMode != .learn,
                      self.canvasExecutingTask == nil,
                      self.detectedSuggestion == nil,
                      type == "text" || type == "url"
                else { return }

                let app = NSWorkspace.shared.frontmostApplication?.localizedName
                self.suggestionPipeline.scheduleClipboardSuggestion(
                    contentType: type,
                    copiedContent: full,
                    screenText: self.screenVisionAnalyzer.recentContext() ?? "",
                    transcript: self.liveTranscriptText,
                    app: app,
                    urls: self.lastScreenSnapshot?.detectedURLs ?? [],
                    worldModel: self.worldModelService.excerpt(forApp: app)
                ) { [weak self] item in
                    guard let self, self.detectedSuggestion == nil else { return }
                    self.detectedSuggestion = item
                    Log.info(.pipeline, "Clipboard suggestion: \(item.id)")
                }
            }
        }

        locationService.onUnknownSSID = { [weak self] ssid in
            self?.pendingUnknownSSID = ssid
        }
        locationService.start()

        let hotkeys = GlobalHotkeyMonitor.shared
        hotkeys.onToggleMic = { [weak self] in
            Task { @MainActor in self?.toggleListening() }
        }
        hotkeys.onAmbientMode = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.pillMode = .ambient
                if !self.isListening { self.startListening() }
            }
        }
        hotkeys.onSearchMode = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.pillMode = .aiSearch
                if !self.isListening { self.startListening() }
            }
        }
        hotkeys.start()

        if micEnabled {
            startListening()
        }

        refreshExtractionItems()
        refreshPipeline()

        // Start system audio if enabled
        if systemAudioEnabled {
            startSystemAudio()
        }

        // Wire and start task scheduler
        TaskScheduler.shared.appState = self
        TaskScheduler.shared.start()

        // Register app-switch observer for ambient OCR
        setupAppSwitchObserver()

        // Sync initial OCR mode
        screenVisionAnalyzer.isLearnMode = (pillMode == .learn)
    }

    // MARK: - Listening Control

    func startListening() {
        guard !isListening else { return }
        chunkManager.startListening()
        isListening = true
        pillState = .listening
        // Sync session lifecycle — recording started outside user-defined flow
        if sessionLifecycle == .undefined {
            sessionLifecycle = .active
        }
        Log.info(.ui, "Mic started")
    }

    func stopListening() {
        guard isListening else { return }
        chunkManager.stopListening()
        isListening = false
        pillState = .paused
        // Sync session lifecycle
        if sessionLifecycle == .active || sessionLifecycle == .paused {
            sessionLifecycle = .undefined
        }
        Log.info(.ui, "Mic stopped")
    }

    func toggleListening() {
        if isListening {
            // Pause: stop mic immediately and process the partial chunk
            chunkManager.pause()
            isListening = false
            pillState = .paused
            if sessionLifecycle == .active { sessionLifecycle = .paused }
            Log.info(.ui, "Mic paused")
        } else {
            // Resume: restart chunk cycle (resume from paused, or start fresh)
            if case .paused = chunkManager.state {
                chunkManager.resume()
            } else {
                chunkManager.startListening()
            }
            isListening = true
            pillState = .listening
            if sessionLifecycle == .paused || sessionLifecycle == .undefined {
                sessionLifecycle = .active
            }
            Log.info(.ui, "Mic resumed")
        }
    }

    // MARK: - System Audio Control

    func startSystemAudio() {
        guard systemAudioEnabled else { return }
        guard SystemAudioCapturer.hasPermission() else {
            SystemAudioCapturer.requestPermission()
            systemAudioEnabled = false
            Log.warn(.audio, "Screen Recording permission not granted — disabling system audio")
            return
        }
        // Wire screen preview frames
        chunkManager.systemAudioCapturer.onFrame = { [weak self] image in
            // Run Vision OCR on screen frames (throttled to every 10s internally)
            self?.screenVisionAnalyzer.processFrame(image)
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Forward to Learn Mode service when active
                if self.learnModeService.isActive {
                    self.learnModeService.receiveFrame(image)
                }
                // FUCBC auto-trigger: unified capability detection (ambient only — not during Learn Mode)
                // In Learn Mode the user is training; suggestions would be intrusive and irrelevant.
                let ocrText = self.screenVisionAnalyzer.recentContext() ?? ""
                if !ocrText.isEmpty, self.pillMode != .learn {
                    let app = NSWorkspace.shared.frontmostApplication?.localizedName
                    // TODO: pass real URLs when ScreenVisionAnalyzer exposes them
                    // (detectedURLs come from on-demand captureNow() snapshots only;
                    //  the background processFrame() path doesn't surface barcode URLs)
                    let item = self.suggestionPipeline.evaluate(
                        screenText: ocrText,
                        transcript: self.liveTranscriptText,
                        app: app,
                        urls: self.lastScreenSnapshot?.detectedURLs ?? []
                    )
                    // Only update detectedSuggestion when there is a new suggestion to show.
                    // Never clear it here — clearing happens only via user action (dismiss/execute)
                    // or when a genuinely different suggestion replaces the current one.
                    // Without this guard: the cooldown suppresses the 2nd-frame repeat → returns nil
                    // → sets detectedSuggestion = nil → toast disappears one frame after it appeared.
                    if let item {
                        if self.detectedSuggestion?.id != item.id {
                            self.detectedSuggestion = item
                        }
                    }

                    // Debounced screen-triggered Haiku (3-min cooldown, only on OCR change).
                    // Fills the gap when user works silently — no voice session means
                    // sessionEndSuggest never fires, so screen work would get no suggestions.
                    self.suggestionPipeline.scheduleScreenSuggestion(
                        screenText: ocrText,
                        transcript: self.liveTranscriptText,
                        app: app,
                        urls: self.lastScreenSnapshot?.detectedURLs ?? [],
                        clipboard: ClipboardMonitor.shared.entries.suffix(5).map { "[\($0.type)] \($0.preview)" },
                        worldModel: self.worldModelService.excerpt(forApp: app)
                    ) { [weak self] screenItem in
                        // Don't surface suggestions while Claude Code is actively running (distracting)
                        guard let self, self.detectedSuggestion == nil,
                              self.canvasExecutingTask == nil else { return }
                        self.detectedSuggestion = screenItem
                        Log.info(.pipeline, "Screen-triggered suggestion: \(screenItem.id)")
                    }
                }
            }
        }
        Task {
            do {
                try await chunkManager.enableSystemAudio()
                // Forward system audio level to UI
                chunkManager.systemAudioCapturer.$audioLevel
                    .receive(on: RunLoop.main)
                    .sink { [weak self] level in
                        self?.systemAudioLevel = level
                    }
                    .store(in: &cancellables)
                Log.info(.audio, "System audio started")
            } catch {
                Log.error(.audio, "System audio failed to start: \(error.localizedDescription)")
                systemAudioEnabled = false
            }
        }
    }

    func stopSystemAudio() {
        chunkManager.disableSystemAudio()
        systemAudioLevel = 0
        Log.info(.audio, "System audio stopped")
    }

    /// Select a project from the session project picker (1-indexed).
    func selectSessionProject(index: Int) {
        let available = Array(projects.prefix(5))
        guard index >= 1, index <= available.count else { return }
        showSessionProjectPicker = false
        var config = SessionConfig()
        config.projectID = available[index - 1].id
        config.projectName = available[index - 1].name
        startUserSession(config: config)
    }

    func cyclePillMode() {
        pillMode = pillMode.next()
    }

    /// Replace live transcript with the cleaned version from the pipeline.
    /// Called at session end when Ollama cleaning returns the polished full-session text.
    /// Replaces (not appends) because liveTranscriptText already has the raw accumulation.
    func replaceWithCleanedTranscript(_ text: String) {
        liveTranscriptText = text
        pendingRawSegment = ""
        latestTranscriptChunk = ""
    }

    /// Session model: append committed chunk text directly to the accumulated transcript.
    /// No intermediate "pending" layer — text flows: streaming partial → committed → accumulated.
    /// Clears the live streaming partial so the next chunk starts fresh.
    func appendChunkToSession(_ text: String) {
        let separator = liveTranscriptText.isEmpty ? "" : " "
        liveTranscriptText += separator + text
        // Also feed into the unified canvas text box so STT and typing share one field
        let canvasSep = canvasTypedText.isEmpty ? "" : "\n"
        canvasTypedText += canvasSep + text
        latestTranscriptChunk = ""   // next chunk's streaming will start fresh
        pendingRawSegment = ""       // no pending layer in session model
    }

    /// Clears the accumulated session transcript.
    /// Called on session end (10 s+ silence detected by ChunkManager) or explicit Clear button.
    /// NOT called on mode changes — transcript survives across mode switches within a session.
    func clearSessionTranscript() {
        liveTranscriptText = ""
        pendingRawSegment = ""
        latestTranscriptChunk = ""
        canvasTypedText = ""
        Log.info(.ui, "Session transcript cleared (new session)")
    }

    // MARK: - User-Defined Session Lifecycle

    /// Open the session config panel.
    func configureSession() {
        // Ambient mode: skip the start-of-session project picker.
        // Ambient sessions show a review canvas at the END with project assignment.
        if pillMode == .ambient {
            startUserSession(config: SessionConfig())
            return
        }
        // Other modes: keep the existing config panel.
        sessionLifecycle = .configuring
        sessionConfig = SessionConfig()
    }

    /// Dismiss the config panel without starting.
    func dismissSessionConfig() {
        sessionLifecycle = .undefined
        sessionConfig = nil
    }

    /// Start recording with the given session config.
    func startUserSession(config: SessionConfig) {
        sessionConfig = config
        sessionLifecycle = .active
        clearSessionTranscript()
        showCleaningPicker = false
        cleaningResults.removeAll()
        // Clear any stale overlays from a previous session so they don't block the canvas.
        ambientReview = nil
        showSessionProjectPicker = false

        // Derive pill mode from context — default to ambient
        if pillMode != .ambient {
            pillMode = .ambient
        }

        // Reset session-scoped trackers
        screenVisionAnalyzer.resetForNewSession()

        chunkManager.startListening(sessionConfig: config)
        Log.info(.system, "User session started (project: \(config.projectName ?? "none"))")
    }

    /// Pause the active recording session.
    func pauseUserSession() {
        guard sessionLifecycle == .active else { return }
        sessionLifecycle = .paused
        chunkManager.pause()
        Log.info(.system, "User session paused")
    }

    /// Resume a paused recording session.
    func resumeUserSession() {
        guard sessionLifecycle == .paused else { return }
        sessionLifecycle = .active
        chunkManager.resume()
        Log.info(.system, "User session resumed")
    }

    /// Stop the session and trigger full pipeline processing on accumulated text.
    func stopUserSession() {
        guard sessionLifecycle == .active || sessionLifecycle == .paused else { return }

        // canvasTypedText is the single source of truth for the session — it accumulates
        // both STT text (appended by appendChunkToSession) and anything the user typed/pasted.
        // Fall back to liveTranscriptText only if the user cleared the text box manually.
        let canvas = canvasTypedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullRawText = canvas.isEmpty ? liveTranscriptText : canvas
        let capturedConfig = sessionConfig
        let capturedSessionID = chunkManager.currentSessionID
        let capturedPillMode = pillMode

        // Stop recording
        chunkManager.stopListening()

        // All modes use ambient pipeline source
        let source: PipelineSource = .ambient

        // Background OCR rolling buffer — lightweight metadata for Llama.
        // If the user triggered an on-demand capture, its execution context flows
        // via lastScreenSnapshot (set by captureScreenNow / captureWithSelectionNow).
        let screenSummary = screenVisionAnalyzer.recentContext()
        let capturedLastSnapshot = lastScreenSnapshot

        // Build split contexts:
        //   analysisCtx  → Llama (lightweight: background OCR or manual metadata + cropped OCR)
        //   executionCtx → Claude Code task prompts only (full / cropped OCR text)
        let screenAnalysisCtx: String? = {
            if let snap = capturedLastSnapshot {
                // Manual capture: give Llama only the metadata context (app/window/dialog/URLs)
                // plus cropped OCR if the user made a selection (small enough for Llama).
                let meta = snap.metadataContext()
                return meta.isEmpty ? nil : meta
            }
            // No manual capture: fall back to rolling background OCR summary.
            return screenSummary
        }()

        let screenExecutionCtx: String? = capturedLastSnapshot?.executionContext()

        // Dispatch session-end pipeline processing
        if !fullRawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let orchestrator = pipelineOrchestrator
            Task.detached {
                await orchestrator.processSessionEnd(
                    fullText: fullRawText,
                    sessionID: capturedSessionID,
                    sessionContext: capturedConfig,
                    speakerContext: nil,
                    screenAnalysisContext: screenAnalysisCtx,
                    screenExecutionContext: screenExecutionCtx,
                    source: source
                )
            }
            Log.info(.system, "User session stopped — dispatching session-level processing (\(fullRawText.count) chars)")

            // Session-end Haiku pass: one Claude Haiku call with full context when pipeline goes idle.
            // Only in ambient mode — not during Learn Mode (user is training, not working).
            if capturedPillMode == .ambient {
                // Capture all signals on @MainActor before async handoff
                let sessionApp = NSWorkspace.shared.frontmostApplication?.localizedName
                let suggCtx = SuggestionContext(
                    transcript: fullRawText,
                    screenText: screenSummary ?? "",
                    app:        sessionApp,
                    urls:       lastScreenSnapshot?.detectedURLs ?? [],
                    clipboard:  ClipboardMonitor.shared.entries.suffix(5).map { "[\($0.type)] \($0.preview)" },
                    worldModel: worldModelService.excerpt(forApp: sessionApp)
                )
                let pipeline = suggestionPipeline
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let item = await pipeline.sessionEndSuggest(context: suggCtx) {
                        if self.detectedSuggestion == nil {
                            self.detectedSuggestion = item
                            Log.info(.pipeline, "Session-end suggestion: \(item.id)")
                        }
                    }
                }
            }

            // Ambient mode: show post-session review canvas immediately.
            // Tasks and analyses will populate it reactively as the pipeline runs.
            // Do NOT call clearSessionTranscript() here — dismissAmbientReview() does it.
            if capturedPillMode == .ambient {
                var review = AmbientReviewState()
                review.cleanedTranscript = fullRawText
                review.sessionID = capturedSessionID
                review.phase = .cleaning
                review.startedAt = Date()
                ambientReview = review
            }
        } else {
            Log.info(.system, "User session stopped — no transcript to process")
        }

        // Reset state — keep transcript visible until next session starts or manual clear
        sessionLifecycle = .undefined
        sessionConfig = nil
    }

    // MARK: - Screen Capture (On-Demand)

    /// Manually captures the frontmost window: OCR + barcode + rectangle detection + screenshot.
    /// Stores result in `lastScreenSnapshot` so it's included in the next session-end pipeline run.
    /// The screenshot image auto-attaches to the next task via ContextCaptureStore.
    @discardableResult
    func captureScreenNow() async -> ScreenSnapshot? {
        let snapshot = await screenVisionAnalyzer.captureNow()
        if let snap = snapshot {
            let desc = [snap.appName, snap.windowTitle].compactMap { $0 }.joined(separator: " – ")
            Log.info(.ui, "Screen captured: \(desc.isEmpty ? "frontmost window" : desc)")
            await MainActor.run { self.lastScreenSnapshot = snap }
        }
        return snapshot
    }

    /// Captures the frontmost window then presents a fullscreen selection overlay.
    /// After the user drags a region (or clicks to point), crops the snapshot to that region
    /// and re-runs OCR on just the selection — yielding a small, focused execution context.
    ///
    /// - Returns: The snapshot with `croppedText` set, or nil if cancelled.
    @discardableResult
    func captureWithSelectionNow() async -> ScreenSnapshot? {
        // 1. Capture the window first (so Vision runs before the overlay appears)
        guard let snapshot = await screenVisionAnalyzer.captureNow() else {
            Log.warn(.ui, "captureWithSelectionNow: capture failed")
            return nil
        }

        // 2. Show the selection overlay — returns a normalised rect or nil (cancel)
        guard let normRect = await ScreenSelectionPanel.present() else {
            Log.info(.ui, "captureWithSelectionNow: cancelled by user")
            return nil
        }

        // 3. Apply the selection: crop + OCR on just the selected region
        let final = await screenVisionAnalyzer.applySelection(normalizedRect: normRect, to: snapshot)

        let desc = [final.appName, final.windowTitle].compactMap { $0 }.joined(separator: " – ")
        Log.info(.ui, "Screen capture with selection: \(desc) — cropped OCR \(final.croppedText?.count ?? 0) chars")

        await MainActor.run { self.lastScreenSnapshot = final }
        return final
    }

    /// Clear the last manual snapshot (e.g. after session end processes it).
    func clearLastScreenSnapshot() {
        lastScreenSnapshot = nil
    }

    // MARK: - Cleaning Level Chooser

    private var pendingCleaningRawText: String = ""

    /// Show the cleaning level chooser: auto-run minimal cleaning first, then let user
    /// pick level 2/3 if unsatisfied. Thumbs up dismisses.
    private func showCleaningLevelChooser(rawText: String) {
        pendingCleaningRawText = rawText
        cleaningResults = [.raw: rawText]
        selectedCleaningLevel = .minimal
        showCleaningPicker = true

        // Auto-run minimal cleaning immediately
        let svc = cleaningService!
        isSessionProcessing = true
        Task.detached {
            let result = await svc.cleanAtLevel(rawText: rawText, level: .minimal)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isSessionProcessing = false
                self.cleaningResults[.minimal] = result
                self.liveTranscriptText = result
                Log.info(.cleaning, "Auto-cleaned minimal: \(result.count) chars")
            }
        }
    }

    /// User chose a different cleaning level — run that pass and show result.
    /// Does NOT close the picker — thumbs up dismisses.
    func selectCleaningLevel(_ level: CleaningLevel) {
        selectedCleaningLevel = level

        let rawText = pendingCleaningRawText
        guard !rawText.isEmpty else { return }

        // If already cached, just show it
        if let cached = cleaningResults[level] {
            liveTranscriptText = cached
            Log.info(.cleaning, "Cleaning level \(level.displayName) (cached): \(cached.count) chars")
            return
        }

        // Raw is always available
        if level == .raw {
            liveTranscriptText = rawText
            Log.info(.cleaning, "Cleaning level: raw")
            return
        }

        // Run the chosen cleaning pass
        let svc = cleaningService!
        isSessionProcessing = true
        Task.detached {
            let result = await svc.cleanAtLevel(rawText: rawText, level: level)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isSessionProcessing = false
                self.cleaningResults[level] = result
                self.liveTranscriptText = result
                Log.info(.cleaning, "Cleaning level \(level.displayName): \(result.count) chars")
            }
        }
    }

    /// Dismiss the cleaning picker (thumbs up).
    func dismissCleaningPicker() {
        showCleaningPicker = false
    }

    /// Called at the chunk boundary: freezes the current streaming partial as a pending
    /// raw segment (visible while Ollama cleans it), then resets the streaming partial
    /// so the next chunk starts fresh.
    func freezeCurrentChunkAsRaw() {
        if !latestTranscriptChunk.isEmpty {
            // Append to any existing pending segment — multiple commits can queue up
            let sep = pendingRawSegment.isEmpty ? "" : " "
            pendingRawSegment += sep + latestTranscriptChunk
        }
        latestTranscriptChunk = ""
    }

    /// Re-route a task to a different skill + workflow and execute it.
    func rerouteTask(id: String, skillID: String) {
        guard let task = pipelineTasks.first(where: { $0.id == id }) else { return }
        let skill = skills.first(where: { $0.id == skillID })
        let workflowID = skill?.workflowID ?? "autoclawd-claude-code"
        pipelineStore.updateTaskSkillAndWorkflow(id: id, skillID: skillID, workflowID: workflowID)
        refreshPipeline()
        // Accept + execute with new routing
        pipelineStore.updateTaskStatus(id: id, status: .ongoing, startedAt: Date())
        refreshPipeline()
        let updated = pipelineTasks.first(where: { $0.id == id }) ?? task
        Task { [pipelineOrchestrator] in
            await pipelineOrchestrator.executeAcceptedTask(updated)
        }
    }

    // MARK: - Code Widget Actions

    /// Start a co-pilot session for the selected project (promptless — voice feeds in).
    func startCodeSession() {
        guard let project = codeSelectedProject else { return }
        codeSessionMessages = []
        codeIsStreaming = true
        codeWidgetStep = .copilot

        // Register a pipeline task record so code sessions appear in monitoring/timeline
        let taskID = pipelineStore.nextTaskID(prefix: "CC")
        codeTaskID = taskID
        codeStepIndex = 0
        let record = PipelineTaskRecord(
            id: taskID,
            analysisID: "code-\(taskID)",
            title: "Code session: \(project.name)",
            prompt: "Interactive co-pilot session for \(project.name)",
            projectID: project.id,
            projectName: project.name,
            mode: .user,
            status: .ongoing,
            skillID: nil,
            workflowID: "autoclawd-claude-code",
            workflowSteps: ["Voice → Co-pilot → Claude Code CLI"],
            missingConnection: nil,
            pendingQuestion: nil,
            attachmentPaths: [],
            createdAt: Date(),
            startedAt: Date(),
            completedAt: nil
        )
        pipelineStore.insertTask(record)
        logCodeStep("Code session started")
        refreshPipeline()

        let initialPrompt = "You are a co-pilot for this project. Listen for instructions and execute them. Start by briefly describing what this project is (1-2 sentences)."

        guard let (session, stream) = claudeCodeRunner.startSession(
            prompt: initialPrompt, in: project,
            dangerouslySkipPermissions: codeSkipPermissions
        ) else {
            codeSessionMessages.append(CodeMessage(role: .error, text: "Failed to start Claude CLI"))
            codeIsStreaming = false
            return
        }
        codeSession = session
        codeSessionMessages.append(CodeMessage(role: .status, text: "Session started"))

        codeStreamTask = Task { @MainActor in
            await processCodeStream(stream)
        }
    }

    /// Feed a voice transcript into the active code session.
    func feedVoiceToCodeSession(_ transcript: String) {
        guard let session = codeSession, session.isRunning else { return }
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        codeSessionMessages.append(CodeMessage(role: .user, text: trimmed))
        logCodeStep("You: \(trimmed)")
        session.sendMessage(trimmed)
        codeIsStreaming = true
    }

    /// Log a step for the active code pipeline task.
    private func logCodeStep(_ description: String, status: String = "completed") {
        guard let taskID = codeTaskID else { return }
        let step = TaskExecutionStep(
            id: UUID().uuidString,
            taskID: taskID,
            stepIndex: codeStepIndex,
            description: description,
            status: status,
            timestamp: Date(),
            output: nil
        )
        codeStepIndex += 1
        pipelineStore.insertStep(step)
    }

    func stopCodeSession() {
        codeStreamTask?.cancel()
        codeStreamTask = nil
        codeSession?.stop()
        codeSession = nil
        codeIsStreaming = false
        codeCurrentToolName = nil
        if let taskID = codeTaskID {
            logCodeStep("Code session ended")
            pipelineStore.updateTaskStatus(id: taskID, status: .completed, completedAt: Date())
            codeTaskID = nil
            codeStepIndex = 0
            refreshPipeline()
        }
    }

    func resetCodeWidget() {
        stopCodeSession()
        codeWidgetStep = .projectSelect
        codeSessionMessages = []
    }

    private func processCodeStream(_ stream: AsyncThrowingStream<ClaudeEvent, Error>) async {
        var accumulatedText = ""
        var lastTextFlushTime = Date()
        do {
            for try await event in stream {
                switch event {
                case .text(let t):
                    accumulatedText += t
                    if let lastIdx = codeSessionMessages.indices.last,
                       codeSessionMessages[lastIdx].role == .assistant {
                        codeSessionMessages[lastIdx] = CodeMessage(role: .assistant, text: accumulatedText)
                    } else {
                        codeSessionMessages.append(CodeMessage(role: .assistant, text: accumulatedText))
                    }
                    // Flush to pipeline periodically (every 2s or at newlines)
                    let now = Date()
                    if now.timeIntervalSince(lastTextFlushTime) > 2.0 || accumulatedText.contains("\n") {
                        let trimmed = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { logCodeStep(trimmed) }
                        accumulatedText = ""
                        lastTextFlushTime = now
                    }

                case .toolUse(let name, _):
                    // Flush any pending text before logging tool use
                    if !accumulatedText.isEmpty {
                        let trimmed = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { logCodeStep(trimmed) }
                        accumulatedText = ""
                    }
                    codeCurrentToolName = name
                    codeSessionMessages.append(CodeMessage(role: .tool, text: "Using \(name)…"))
                    logCodeStep("Using \(name)...", status: "running")

                case .toolResult(let name, let output):
                    codeCurrentToolName = nil
                    let summary = output.isEmpty ? "\(name) done" : "\(name): \(String(output.prefix(120)))"
                    codeSessionMessages.append(CodeMessage(role: .tool, text: summary))
                    logCodeStep(summary)

                case .result(let text):
                    // Flush remaining accumulated text
                    if !accumulatedText.isEmpty {
                        let trimmed = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { logCodeStep(trimmed) }
                        accumulatedText = ""
                    }
                    if !text.isEmpty {
                        codeSessionMessages.append(CodeMessage(role: .assistant, text: text))
                        logCodeStep(text)
                    }
                    codeIsStreaming = false

                case .status(let msg):
                    codeSessionMessages.append(CodeMessage(role: .status, text: msg))
                    logCodeStep(msg, status: "running")

                case .error(let msg):
                    codeSessionMessages.append(CodeMessage(role: .error, text: msg))
                    logCodeStep("Error: \(msg)", status: "failed")

                case .sessionInit:
                    break
                }
            }
        } catch {
            codeSessionMessages.append(
                CodeMessage(role: .error, text: error.localizedDescription)
            )
            logCodeStep("Session error: \(error.localizedDescription)", status: "failed")
        }
        codeIsStreaming = false
    }


    // MARK: - Actions

    func confirmWifiLabel() {
        guard let _ = pendingUnknownSSID,
              !wifiLabelInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        locationService.labelCurrentSSID(wifiLabelInput)
        pendingUnknownSSID = nil
        wifiLabelInput = ""
    }

    // MARK: - Transcript Access

    func recentTranscripts() -> [TranscriptRecord] {
        transcriptStore.recent(limit: 50)
    }

    func searchTranscripts(query: String) -> [TranscriptRecord] {
        transcriptStore.search(query: query)
    }

    // MARK: - Extraction Access

    func refreshExtractionItems() {
        extractionItems = extractionStore.all()
        pendingExtractionCount = extractionStore.pendingAccepted().count
    }

    func synthesizeNow() async {
        await extractionService.synthesize()
        await MainActor.run {
            refreshExtractionItems()
            refreshStructuredTodos()
        }
    }

    func cleanupNow() async {
        isCleaningUp = true
        await cleanupService.cleanup()
        refreshExtractionItems()
        isCleaningUp = false
    }

    func toggleExtraction(id: String) {
        guard let item = extractionItems.first(where: { $0.id == id }) else { return }
        let newOverride: String? = item.isAccepted ? "dismissed" : "accepted"
        extractionStore.setUserOverride(id: id, override: newOverride)
        refreshExtractionItems()
    }

    func setExtractionBucket(id: String, bucket: ExtractionBucket) {
        extractionStore.setBucket(id: id, bucket: bucket)
        refreshExtractionItems()
    }

    // MARK: - Pipeline v2 Access

    func refreshPipeline() {
        cleanedTranscripts = pipelineStore.fetchRecentCleaned()
        transcriptAnalyses = pipelineStore.fetchRecentAnalyses()
        pipelineTasks      = pipelineStore.fetchRecentTasks()
    }

    func refreshSkills() {
        skills = skillStore.all()
    }

    func acceptTask(id: String) {
        pipelineStore.updateTaskStatus(id: id, status: .ongoing, startedAt: Date())
        refreshPipeline()
        // Trigger execution in background
        if let task = pipelineTasks.first(where: { $0.id == id }) {
            Task { [pipelineOrchestrator] in
                await pipelineOrchestrator.executeAcceptedTask(task)
            }
        }
    }

    func executeTask(id: String) {
        // Re-trigger execution for an already-ongoing task (e.g. stuck/retry)
        if let task = pipelineTasks.first(where: { $0.id == id }) {
            Task { [pipelineOrchestrator] in
                await pipelineOrchestrator.executeAcceptedTask(task)
            }
        }
    }

    func dismissTask(id: String) {
        pipelineStore.updateTaskStatus(id: id, status: .filtered)
        refreshPipeline()
    }

    // MARK: - Capability Execution

    /// Execute a detected FUCBC capability by running its SKILL.md on the pill canvas.
    func executeCapability(_ capability: Capability) {
        detectedSuggestion = nil

        guard let project = projects.first else {
            Log.warn(.system, "Execute capability: no project available")
            return
        }

        let prompt: String
        if let skillPath = capability.skillMDPath {
            prompt = """
            Read and execute the skill defined in \(skillPath).
            Capability: \(capability.name) — \(capability.description)
            """
        } else {
            let steps = capability.subWorkflows
                .enumerated()
                .map { i, wf in
                    "\(i + 1). \(wf.name): \(wf.description)" +
                    (wf.invocation.map { "\n   Run: \($0)" } ?? "")
                }
                .joined(separator: "\n")
            prompt = """
            Execute capability: \(capability.name)
            \(capability.description)
            Steps:
            \(steps)
            """
        }

        let taskID = "CAP-\(String(UUID().uuidString.prefix(8)).uppercased())"
        let task = PipelineTaskRecord(
            id: taskID,
            analysisID: "cap-\(taskID)",
            title: "\(capability.emoji) \(capability.name)",
            prompt: prompt,
            projectID: project.id,
            projectName: project.name,
            mode: .auto,
            status: .ongoing,
            skillID: nil,
            workflowID: nil,
            workflowSteps: capability.subWorkflows.map { $0.name },
            missingConnection: nil,
            pendingQuestion: nil,
            attachmentPaths: [],
            createdAt: Date()
        )

        pipelineTasks.insert(task, at: 0)

        codeSessionMessages = []
        codeIsStreaming = true
        codeCurrentToolName = nil
        codeTaskID = taskID
        codeStepIndex = 0
        canvasExecutingTask = task

        guard let (session, stream) = claudeCodeRunner.startSession(
            prompt: prompt, in: project,
            dangerouslySkipPermissions: true
        ) else {
            codeSessionMessages.append(CodeMessage(role: .error, text: "Failed to start Claude CLI"))
            codeIsStreaming = false
            canvasExecutingTask = nil
            return
        }
        codeSession = session
        codeSessionMessages.append(CodeMessage(role: .status, text: "\(capability.emoji) \(capability.name)"))

        codeStreamTask = Task { @MainActor in
            await processCodeStream(stream)
        }
        Log.info(.pipeline, "Capability execution started: \(capability.name) in \(project.name)")
    }

    /// Clear the detected capability suggestion (user dismissed it).
    func dismissDetectedSuggestion() {
        detectedSuggestion = nil
        activeQuestion = nil
    }

    /// Handle a user's answer to an interactive question toast.
    /// "Not relevant" → dismiss. Any other option → build a task from the chosen action + original context.
    func handleSuggestionQuestionOption(_ option: String, question: SuggestionQuestion) {
        dismissDetectedSuggestion()
        let snippet = String((question.context.screenText + " " + question.context.transcript)
            .prefix(120)).replacingOccurrences(of: "\n", with: " ")
        guard option.lowercased() != "not relevant" else {
            // Teach world model: this context type is not actionable for this user
            worldModelService.appendSuggestionFeedback(
                "NOT RELEVANT in \(question.context.app ?? "unknown"): \(question.question) | ctx: \(snippet)"
            )
            return
        }
        // Positive: teach world model what the user acts on
        worldModelService.appendSuggestionFeedback(
            "ACTED '\(option)' in \(question.context.app ?? "unknown"): \(question.question)"
        )

        let ctx = TaskContext(
            files:    [],
            contacts: [],
            urls:     question.context.urls,
            rawOCR:   question.context.screenText
        )
        let executionPrompt = [
            "User selected: \(option)",
            "",
            "Conversation context:",
            question.context.transcript,
            "",
            "Screen context:",
            String(question.context.screenText.prefix(600)),
            "",
            "Complete the selected action: \(option). If anything is ambiguous, ask one clarifying question first."
        ].joined(separator: "\n")

        let task = TaskSuggestion(
            id:              UUID().uuidString,
            title:           option,
            intent:          "task",
            detectedContext: ctx,
            executionPrompt: executionPrompt,
            confidence:      1.0  // user explicitly chose this
        )
        executeSuggestedTask(task)
        Log.info(.pipeline, "Question option selected: '\(option)'")
    }

    /// Execute a task suggestion detected by the SuggestionPipeline.
    func executeSuggestedTask(_ task: TaskSuggestion) {
        detectedSuggestion = nil
        guard let project = projects.first else {
            Log.warn(.pipeline, "executeSuggestedTask: no project available")
            return
        }

        let taskID = "TASK-\(String(UUID().uuidString.prefix(8)).uppercased())"
        let record = PipelineTaskRecord(
            id: taskID,
            analysisID: "task-\(taskID)",
            title: "⚡ \(task.title)",
            prompt: task.executionPrompt,
            projectID: project.id,
            projectName: project.name,
            mode: .auto,
            status: .ongoing,
            skillID: nil,
            workflowID: nil,
            workflowSteps: [task.intent],
            missingConnection: nil,
            pendingQuestion: nil,
            attachmentPaths: [],
            createdAt: Date()
        )

        pipelineTasks.insert(record, at: 0)

        // Cancel any prior stream before starting a new one
        codeStreamTask?.cancel()
        codeStreamTask = nil

        codeSessionMessages = []
        codeIsStreaming = true
        codeCurrentToolName = nil
        codeTaskID = taskID
        codeStepIndex = 0
        canvasExecutingTask = record

        guard let (session, stream) = claudeCodeRunner.startSession(
            prompt: task.executionPrompt,
            in: project,
            dangerouslySkipPermissions: true
        ) else {
            codeSessionMessages.append(CodeMessage(role: .error, text: "Failed to start Claude CLI"))
            codeIsStreaming = false
            canvasExecutingTask = nil
            return
        }

        codeSession = session
        codeSessionMessages.append(CodeMessage(role: .status, text: "⚡ \(task.title)"))
        codeStreamTask = Task { @MainActor in
            await processCodeStream(stream)
        }
        Log.info(.pipeline, "Task execution started: \(task.title) in \(project.name)")
    }

    // MARK: - Pipeline Task Re-execution

    /// Re-run an existing pipeline task by ID (used by TaskScheduler and TaskDetailView).
    func runPipelineTask(id: String) {
        guard let task = pipelineTasks.first(where: { $0.id == id }) else {
            Log.warn(.system, "runPipelineTask: task not found for id \(id)")
            return
        }
        guard let project = projects.first(where: { $0.id == task.projectID }) ?? projects.first else {
            Log.warn(.system, "runPipelineTask: no project for task \(id)")
            return
        }

        pipelineStore.updateTaskStatus(id: id, status: .ongoing, startedAt: Date())
        refreshPipeline()

        codeSessionMessages = []
        codeIsStreaming = true
        codeCurrentToolName = nil
        codeTaskID = id
        codeStepIndex = 0
        canvasExecutingTask = pipelineTasks.first(where: { $0.id == id })

        guard let (session, stream) = claudeCodeRunner.startSession(
            prompt: task.prompt, in: project,
            dangerouslySkipPermissions: true
        ) else {
            codeSessionMessages.append(CodeMessage(role: .error, text: "Failed to start Claude CLI"))
            codeIsStreaming = false
            canvasExecutingTask = nil
            pipelineStore.updateTaskStatus(id: id, status: .filtered, completedAt: Date())
            refreshPipeline()
            return
        }
        codeSession = session
        codeSessionMessages.append(CodeMessage(role: .status, text: task.title))

        codeStreamTask = Task { @MainActor in
            await processCodeStream(stream)
            pipelineStore.updateTaskStatus(id: id, status: .completed, completedAt: Date())
            refreshPipeline()
        }
        Log.info(.pipeline, "runPipelineTask: re-running '\(task.title)' in \(project.name)")
    }

    // MARK: - App Switch Observer

    /// Register for NSWorkspace.didActivateApplicationNotification.
    /// In ambient + learn mode, triggers a lightweight OCR capture on every app switch.
    /// (Skipped only in aiSearch mode where screen context isn't used.)
    func setupAppSwitchObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.pillMode != .aiSearch else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.screenVisionAnalyzer.captureOnAppSwitch()
                // App switch = high-signal context change → fire Haiku with 60s debounce
                // (much shorter than the 3-min passive screen trigger)
                guard self.pillMode != .learn, self.detectedSuggestion == nil else { return }
                let ocrText = self.screenVisionAnalyzer.recentContext() ?? ""
                guard !ocrText.isEmpty else { return }
                let switchApp = NSWorkspace.shared.frontmostApplication?.localizedName
                self.suggestionPipeline.scheduleAppSwitchSuggestion(
                    screenText: ocrText,
                    transcript: self.liveTranscriptText,
                    app:        switchApp,
                    urls:       self.lastScreenSnapshot?.detectedURLs ?? [],
                    clipboard:  ClipboardMonitor.shared.entries.suffix(5).map { "[\($0.type)] \($0.preview)" },
                    worldModel: self.worldModelService.excerpt(forApp: switchApp)
                ) { [weak self] item in
                    guard let self, self.detectedSuggestion == nil,
                          self.canvasExecutingTask == nil else { return }
                    self.detectedSuggestion = item
                    Log.info(.pipeline, "App-switch suggestion: \(item.id)")
                }
            }
        }
        Log.info(.system, "AppState: app-switch OCR observer registered")
    }

    // MARK: - Workflow Execution

    /// Execute a workflow with the given inputs. Chains steps serially with context passing.
    func executeWorkflow(_ workflow: WorkflowRecord, inputs: WorkflowInputs) {
        guard let project = projects.first(where: { $0.id == (inputs.projectID ?? "") })
            ?? projects.first else {
            Log.warn(.system, "Execute workflow: no project available")
            return
        }

        // Reset workflow state
        executingWorkflow = workflow
        workflowStepLogs = []
        workflowCurrentStep = 0
        workflowTotalSteps = workflow.steps.count
        workflowStepText = ""

        // Create a pipeline task for visibility in LogsPipelineView
        let taskID = "WF-\(String(UUID().uuidString.prefix(8)).uppercased())"
        let task = PipelineTaskRecord(
            id: taskID,
            analysisID: "wf-\(taskID)",
            title: "\(workflow.emoji) \(workflow.name)",
            prompt: "Workflow: \(workflow.description)",
            projectID: project.id,
            projectName: project.name,
            mode: .auto,
            status: .ongoing,
            skillID: nil,
            workflowID: workflow.id,
            workflowSteps: workflow.steps.map { $0.name },
            missingConnection: nil,
            pendingQuestion: nil,
            attachmentPaths: [],
            createdAt: Date()
        )
        pipelineTasks.insert(task, at: 0)

        // Set up canvas streaming
        codeSessionMessages = []
        codeIsStreaming = true
        codeCurrentToolName = nil
        codeTaskID = taskID
        codeStepIndex = 0
        canvasExecutingTask = task

        codeSessionMessages.append(CodeMessage(role: .status, text: "\(workflow.emoji) \(workflow.name) \u{2014} \(workflow.steps.count) steps"))

        // Wire executor callbacks
        workflowExecutor.onStepStarted = { [weak self] index, name, total in
            Task { @MainActor in
                guard let self else { return }
                self.workflowCurrentStep = index
                self.workflowTotalSteps = total
                self.workflowStepText = ""
                self.codeSessionMessages.append(CodeMessage(role: .status, text: "Step \(index + 1)/\(total): \(name)"))
            }
        }

        workflowExecutor.onStepCompleted = { [weak self] index, name, output in
            Task { @MainActor in
                guard let self else { return }
                let summary = output.map { String($0.prefix(200)) } ?? "done"
                self.codeSessionMessages.append(CodeMessage(role: .assistant, text: "\u{2705} \(name): \(summary)"))
            }
        }

        workflowExecutor.onStepFailed = { [weak self] index, name, error in
            Task { @MainActor in
                guard let self else { return }
                self.codeSessionMessages.append(CodeMessage(role: .error, text: "\u{274C} \(name): \(error)"))
            }
        }

        workflowExecutor.onStepText = { [weak self] index, text in
            Task { @MainActor in
                self?.workflowStepText = text
            }
        }

        workflowExecutor.onWorkflowCompleted = { [weak self] log in
            Task { @MainActor in
                guard let self else { return }
                self.executingWorkflow = nil
                self.codeIsStreaming = false
                self.canvasExecutingTask = nil
                let status = log.status == .completed ? "\u{2705} Completed" : "\u{274C} Failed"
                self.codeSessionMessages.append(CodeMessage(role: .status, text: "\(workflow.emoji) \(workflow.name) \u{2014} \(status) (\(log.completedSteps)/\(log.totalSteps) steps)"))
            }
        }

        // Run workflow
        workflowTask = Task { @MainActor in
            let log = await workflowExecutor.execute(
                workflow: workflow,
                inputs: inputs,
                project: project,
                claudeCodeRunner: claudeCodeRunner
            )
            workflowStepLogs = log.stepLogs
        }

        Log.info(.pipeline, "Workflow execution started: \(workflow.name) in \(project.name)")
    }

    // MARK: - Ambient Review Actions

    /// Approve a task directly from the post-session review canvas and stream it on the canvas.
    func reviewApproveTask(_ id: String) {
        guard var review = ambientReview else { return }
        review.approvedTaskIDs.insert(id)
        review.skippedTaskIDs.remove(id)
        ambientReview = review
        executeReviewTaskOnCanvas(id)
    }

    /// Skip a task from the post-session review canvas (marks it filtered).
    func reviewSkipTask(_ id: String) {
        guard var review = ambientReview else { return }
        review.skippedTaskIDs.insert(id)
        review.approvedTaskIDs.remove(id)
        ambientReview = review
        dismissTask(id: id)
    }

    /// Update the project selected in the post-session review canvas.
    func reviewSelectProject(_ project: Project?) {
        guard var review = ambientReview else { return }
        review.selectedProjectID   = project?.id
        review.selectedProjectName = project?.name
        ambientReview = review
    }

    /// Select project in the review by 1-based index (0 = None, 1..N = project list).
    func selectReviewProjectByIndex(_ index: Int) {
        if index == 0 {
            reviewSelectProject(nil)
        } else {
            let allProjects = Array(projects.prefix(5))
            if index >= 1 && index <= allProjects.count {
                reviewSelectProject(allProjects[index - 1])
            }
        }
    }

    /// Approve all session tasks and start executing them sequentially on the canvas.
    func approveAllReviewTasks() {
        guard var review = ambientReview, review.phase == .tasksReady else { return }
        let taskIDs = review.sessionTaskIDs.filter { !review.skippedTaskIDs.contains($0) }
        guard !taskIDs.isEmpty else {
            review.phase = .done
            ambientReview = review
            Log.info(.pipeline, "Review: no tasks to execute — done")
            return
        }
        review.approvedTaskIDs = Set(taskIDs)
        review.executionQueue = Array(taskIDs.dropFirst())
        ambientReview = review
        // Kick off the first task; doneWithCanvasExecution() handles the rest.
        executeReviewTaskOnCanvas(taskIDs[0])
        Log.info(.pipeline, "Review: approving all \(taskIDs.count) task(s), \(taskIDs.count - 1) queued")
    }

    /// Dismiss the ambient review: retroactively assigns the selected project to all
    /// analyses and tasks from this session, then clears the review and the transcript.
    func dismissAmbientReview() {
        guard let review = ambientReview else { return }

        // Retroactively patch project onto all pipeline records from this session.
        if let pid = review.selectedProjectID, let pname = review.selectedProjectName {
            for aid in review.sessionAnalysisIDs {
                if let a = transcriptAnalyses.first(where: { $0.id == aid }) {
                    pipelineStore.updateAnalysis(
                        id: aid, projectName: pname, projectID: pid,
                        priority: a.priority, tags: a.tags, summary: a.summary
                    )
                }
            }
            for tid in review.sessionTaskIDs {
                if let t = pipelineTasks.first(where: { $0.id == tid }) {
                    pipelineStore.updateTaskDetails(
                        id: tid, title: t.title, prompt: t.prompt,
                        projectName: pname, projectID: pid
                    )
                }
            }
            refreshPipeline()
            Log.info(.system, "Ambient review: assigned project '\(pname)' retroactively to \(review.sessionAnalysisIDs.count) analyses, \(review.sessionTaskIDs.count) tasks")
        }

        ambientReview = nil
        clearSessionTranscript()
        Log.info(.system, "Ambient review dismissed")
    }

    /// Re-run the full pipeline (analysis → task creation → execution) on an
    /// existing cleaned transcript. Useful for transcripts captured in
    /// transcription-only mode, or that previously produced no actionable tasks.
    func rerunPipeline(cleanedTranscript: CleanedTranscript) {
        let text = cleanedTranscript.cleanedText
        let tid  = cleanedTranscript.sourceTranscriptIDs.first ?? 0
        let sid  = cleanedTranscript.sessionID ?? UUID().uuidString
        let dur  = cleanedTranscript.durationSeconds
        let spk  = cleanedTranscript.speakerName
        Task { [pipelineOrchestrator] in
            await pipelineOrchestrator.processTranscript(
                text: text,
                transcriptID: tid,
                sessionID: sid,
                sessionChunkSeq: 0,
                durationSeconds: dur,
                speakerName: spk,
                source: .ambient
            )
        }
    }

    // MARK: - Canvas Task Execution

    /// Start executing a pipeline task and stream its output on the pill canvas.
    /// Reuses the existing codeSessionMessages / codeIsStreaming / processCodeStream machinery.
    func executeReviewTaskOnCanvas(_ taskID: String) {
        guard let task = pipelineTasks.first(where: { $0.id == taskID }) else { return }

        // Resolve project: review selection → task's project → first available.
        let resolvedProjectID = ambientReview?.selectedProjectID ?? task.projectID
        let project: Project?
        if let pid = resolvedProjectID {
            project = projects.first(where: { $0.id == pid }) ?? projects.first
        } else {
            project = projects.first
        }
        guard let project else {
            Log.warn(.system, "Canvas execution: no project available for task \(taskID)")
            return
        }

        // Mark task as running in the pipeline store.
        pipelineStore.updateTaskStatus(id: taskID, status: .ongoing, startedAt: Date())
        refreshPipeline()

        // Wire up streaming state (reuses code widget published properties).
        codeSessionMessages = []
        codeIsStreaming = true
        codeCurrentToolName = nil
        codeTaskID = taskID
        codeStepIndex = 0
        canvasExecutingTask = task

        guard let (session, stream) = claudeCodeRunner.startSession(
            prompt: task.prompt, in: project,
            dangerouslySkipPermissions: true
        ) else {
            codeSessionMessages.append(CodeMessage(role: .error, text: "Failed to start Claude CLI"))
            codeIsStreaming = false
            canvasExecutingTask = nil
            return
        }
        codeSession = session
        codeSessionMessages.append(CodeMessage(role: .status, text: task.title))

        codeStreamTask = Task { @MainActor in
            await processCodeStream(stream)
            // Mark complete when stream finishes naturally.
            pipelineStore.updateTaskStatus(id: taskID, status: .completed, completedAt: Date())
            refreshPipeline()
        }
        Log.info(.pipeline, "Canvas execution started: \(task.title) in \(project.name)")
    }

    /// Stop the canvas execution: advance the sequential execution queue or show done state.
    func doneWithCanvasExecution() {
        codeStreamTask?.cancel()
        codeStreamTask = nil
        codeSession = nil
        codeIsStreaming = false
        codeCurrentToolName = nil
        if let taskID = codeTaskID {
            pipelineStore.updateTaskStatus(id: taskID, status: .completed, completedAt: Date())
            refreshPipeline()
        }
        codeTaskID = nil
        canvasExecutingTask = nil

        // Advance the execution queue — start next task or show done state.
        if var review = ambientReview, !review.executionQueue.isEmpty {
            let nextID = review.executionQueue.removeFirst()
            ambientReview = review
            executeReviewTaskOnCanvas(nextID)
            Log.info(.pipeline, "Review: starting next queued task \(nextID)")
        } else if ambientReview != nil {
            // Queue exhausted — all tasks done.
            ambientReview?.phase = .done
            Log.info(.pipeline, "Review: all tasks executed, showing done state")
        }
        // If ambientReview is nil, canvasForCurrentMode falls through to the next canvas layer.
    }

    /// Send a follow-up message to an active Claude session for a task (with optional attachments).
    func sendMessageToTask(id: String, message: String, attachments: [Attachment] = []) {
        taskExecutionService.sendMessage(taskID: id, message: message, attachments: attachments)
    }

    /// Check if a task has an active Claude session.
    func taskHasActiveSession(id: String) -> Bool {
        taskExecutionService.hasActiveSession(taskID: id)
    }

    /// Stop an active Claude session for a task.
    func stopTaskSession(id: String) {
        taskExecutionService.stopSession(taskID: id)
        refreshPipeline()
    }

    func setTaskMode(id: String, mode: TaskMode) {
        pipelineStore.updateTaskMode(id: id, mode: mode)
        refreshPipeline()
    }

    // MARK: - Inline Editing

    func updateAnalysis(id: String, projectName: String?, projectID: String?, priority: String?, tags: [String], summary: String) {
        pipelineStore.updateAnalysis(id: id, projectName: projectName, projectID: projectID, priority: priority, tags: tags, summary: summary)
        refreshPipeline()
    }

    func updateTaskDetails(id: String, title: String, prompt: String, projectName: String?, projectID: String?) {
        pipelineStore.updateTaskDetails(id: id, title: title, prompt: prompt, projectName: projectName, projectID: projectID)
        refreshPipeline()
    }

    // MARK: - File Write-through

    func saveTodos(_ content: String) {
        todoService.write(content)
    }

    func saveWorldModel(_ content: String) {
        worldModelService.write(content)
    }

    // MARK: - Data Management

    func exportData() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "autoclawd-export.txt"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let world = self?.worldModelContent ?? ""
            let todos = self?.todosContent ?? ""
            let export = "# AutoClawd Export\n\n## World Model\n\(world)\n\n## Todos\n\(todos)"
            try? export.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func confirmDeleteAll() {
        let alert = NSAlert()
        alert.messageText = "Delete all AutoClawd data?"
        alert.informativeText = "This will delete all transcripts, world model, and to-do entries."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .critical
        if alert.runModal() == .alertFirstButtonReturn {
            deleteAllData()
        }
    }

    // MARK: - Project & Todo Management

    func refreshProjects()        { projects = projectStore.all() }
    func refreshStructuredTodos() { structuredTodos = structuredTodoStore.all() }

    func addProject(name: String, path: String) {
        _ = projectStore.insert(name: name, localPath: path)
        refreshProjects()
    }

    func deleteProject(id: String) {
        projectStore.delete(id: id)
        refreshProjects()
    }

    func setTodoProject(todoID: String, projectID: String?) {
        structuredTodoStore.setProject(id: todoID, projectID: projectID)
        refreshStructuredTodos()
    }

    func setTranscriptProject(transcriptID: Int64, projectID: UUID?) {
        transcriptStore.setProject(projectID, for: transcriptID)
    }

    func addStructuredTodo(content: String, priority: String?, project: Project? = nil) {
        let inserted = structuredTodoStore.insert(content: content, priority: priority)
        if let project {
            structuredTodoStore.setProject(id: inserted.id, projectID: project.id)
        }
        refreshStructuredTodos()

        // Frame in background if we have a project for context
        guard let project else { return }
        let todoID = inserted.id
        Task { [weak self] in
            guard let self else { return }
            let framed = await todoFramingService.frame(rawPayload: content, for: project)
            guard framed != content else { return }
            structuredTodoStore.updateContent(id: todoID, content: framed)
            await MainActor.run { self.refreshStructuredTodos() }
        }
    }

    func deleteTodo(id: String) {
        structuredTodoStore.delete(id: id)
        refreshStructuredTodos()
    }

    func markTodoExecuted(id: String, output: String) {
        structuredTodoStore.markExecuted(id: id, output: output)
        refreshStructuredTodos()
    }

    func executeSelectedTodos(ids: Set<String>, mode: ExecutionMode) async {
        let todos = structuredTodos.filter { ids.contains($0.id) }
        guard !todos.isEmpty else { return }
        let apiKey = SettingsManager.shared.anthropicAPIKey

        let runnable = todos.filter { todo in projects.first(where: { $0.id == todo.projectID }) != nil }
        let skipped  = todos.count - runnable.count
        if skipped > 0 {
            Log.warn(.system, "⚠️ \(skipped) todo(s) skipped — no project assigned")
        }
        Log.warn(.system, "⚡ Executing \(runnable.count) todo(s) [\(mode.displayName)]…")

        // Helper: run one todo, collect output, mark executed
        func runOne(_ todo: StructuredTodo, project: Project) async {
            var lines: [String] = []
            do {
                for try await line in ClaudeCodeRunner().run(
                    todo: todo, project: project,
                    apiKey: apiKey.isEmpty ? nil : apiKey
                ) {
                    lines.append(line)
                    Log.info(.system, "[\(todo.content.prefix(20))] \(line)")
                }
                let output = lines.joined(separator: "\n")
                markTodoExecuted(id: todo.id, output: output)
                Log.warn(.system, "✓ Done: \(todo.content.prefix(40))")
            } catch {
                Log.warn(.system, "❌ Failed '\(todo.content.prefix(30))': \(error.localizedDescription)")
            }
        }

        switch mode {
        case .parallel:
            await withTaskGroup(of: Void.self) { group in
                for todo in todos {
                    guard let project = projects.first(where: { $0.id == todo.projectID }) else { continue }
                    group.addTask { await runOne(todo, project: project) }
                }
            }
        case .series:
            for todo in todos {
                guard let project = projects.first(where: { $0.id == todo.projectID }) else { continue }
                await runOne(todo, project: project)
            }
        }
    }

    // Callback set by AppDelegate so Settings tab can re-open the setup window
    var onShowSetup: (() -> Void)?

    func showSetup() {
        onShowSetup?()
    }

    // MARK: - Private Setup

    private func setupLogger() {
        Log.minimumLevel = SettingsManager.shared.logLevel
        Log.configure(storageManager: storage)
    }

    private func buildTranscriptionService() {
        switch transcriptionMode {
        case .local:
            transcriptionService = LocalTranscriptionService()
        case .groq:
            let key = groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            transcriptionService = key.isEmpty ? nil : TranscriptionService(apiKey: key)
        }
        reconfigureChunkManager()
    }

    private func rebuildTranscriptionService() {
        buildTranscriptionService()
    }

    private func configureChunkManager() {
        chunkManager.appState = self
        reconfigureChunkManager()

        chunkManager.onItemsClassified = { [weak self] _ in
            guard let self else { return }
            self.refreshExtractionItems()
            let pending = self.extractionStore.pendingAccepted().count
            self.pendingExtractionCount = pending
            if self.synthesizeThreshold > 0, pending >= self.synthesizeThreshold {
                Task { await self.synthesizeNow() }
            }
        }

        pipelineOrchestrator.onPipelineUpdated = { [weak self] in
            self?.refreshPipeline()
        }

        pipelineOrchestrator.onTranscriptionCleaned = { [weak self] cleanedText in
            guard let self else { return }
            Task { @MainActor in
                self.replaceWithCleanedTranscript(cleanedText)
                // Update review transcript and advance cleaning → analyzing phase.
                if var review = self.ambientReview {
                    review.cleanedTranscript = cleanedText
                    if review.phase == .cleaning {
                        review.phase = .analyzing
                    }
                    self.ambientReview = review
                }
                // Forward to Learn Mode so it accumulates transcript context
                self.learnModeService.addTranscriptChunk(cleanedText)
            }
        }

        pipelineOrchestrator.onSessionProcessingChanged = { [weak self] active in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isSessionProcessing = active
                // When processing ends, advance review to tasksReady if still in a pipeline phase.
                if !active, var review = self.ambientReview {
                    if review.phase == .analyzing || review.phase == .cleaning {
                        review.phase = .tasksReady
                        self.ambientReview = review
                    }
                }
            }
        }

        // Observe audio level changes
        chunkManager.$chunkIndex
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.audioLevel = self?.chunkManager.audioLevel ?? 0 }
            }
            .store(in: &cancellables)

        // ── Ambient review: reactively populate analysis IDs as pipeline emits them ──
        // Only include analyses from THIS session (timestamp >= review.startedAt) to avoid
        // contaminating the review with analyses from previous sessions.
        $transcriptAnalyses
            .receive(on: RunLoop.main)
            .sink { [weak self] analyses in
                guard var review = self?.ambientReview else { return }
                let newIDs = analyses
                    .filter { $0.timestamp >= review.startedAt && !review.sessionAnalysisIDs.contains($0.id) }
                    .map(\.id)
                guard !newIDs.isEmpty else { return }
                review.sessionAnalysisIDs.append(contentsOf: newIDs)
                self?.ambientReview = review
            }
            .store(in: &cancellables)

        // ── Ambient review: reactively populate task IDs matched to this session's analyses ──
        $pipelineTasks
            .receive(on: RunLoop.main)
            .sink { [weak self] tasks in
                guard var review = self?.ambientReview else { return }
                let newIDs = tasks
                    .filter { review.sessionAnalysisIDs.contains($0.analysisID)
                           && $0.createdAt >= review.startedAt
                           && !review.sessionTaskIDs.contains($0.id) }
                    .map(\.id)
                guard !newIDs.isEmpty else { return }
                review.sessionTaskIDs.append(contentsOf: newIDs)
                review.phase = .tasksReady
                self?.ambientReview = review
            }
            .store(in: &cancellables)
    }

    private func reconfigureChunkManager() {
        guard let ts = transcriptionService else { return }
        chunkManager.configure(
            transcriptionService: ts,
            extractionService: extractionService,
            pipelineOrchestrator: pipelineOrchestrator,
            transcriptStore: transcriptStore,
            qaService: qaService,
            qaStore: qaStore
        )
    }

    private func deleteAllData() {
        let fm = FileManager.default
        try? fm.removeItem(at: storage.transcriptsDatabaseURL)
        try? fm.removeItem(at: storage.worldModelURL)
        try? fm.removeItem(at: storage.todosURL)
        for url in (try? fm.contentsOfDirectory(at: storage.audioDirectory,
                                                  includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: url)
        }
        Log.info(.system, "All data deleted")
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Hot-Word Processing

    @MainActor
    func processHotWordMatches(_ matches: [HotWordMatch]) async {
        for match in matches {
            Log.info(.system, "Hot-word: '\(match.config.keyword)' action=\(match.config.action.rawValue)")

            var resolvedProject: Project? = nil
            if let ref = match.explicitProjectRef {
                let all = projectStore.all()
                if let idx = Int(ref), idx >= 1, idx <= all.count {
                    resolvedProject = all[idx - 1]
                } else {
                    resolvedProject = all.first { $0.name.lowercased().contains(ref.lowercased()) }
                }
            } else {
                resolvedProject = await projectStore.inferProject(for: match.payload, using: ollama)
            }

            switch match.config.action {
            case .executeImmediately:
                guard let project = resolvedProject else {
                    Log.warn(.system, "Hot-word executeImmediately: no project resolved, skipping")
                    continue
                }
                Task {
                    for try await line in claudeCodeRunner.run(
                        match.payload,
                        in: project,
                        dangerouslySkipPermissions: match.config.skipPermissions
                    ) {
                        Log.info(.system, "[hot-exec] \(line)")
                    }
                }

            case .addTodo:
                let inserted = structuredTodoStore.insert(
                    content: match.payload,
                    priority: "HIGH"
                )
                if let project = resolvedProject {
                    structuredTodoStore.setProject(id: inserted.id, projectID: project.id)
                }
                refreshStructuredTodos()
                Log.info(.todo, "Hot-word added todo (raw): \(match.payload)")

                // Frame the task in background — updates content silently when done
                if let project = resolvedProject {
                    let todoID = inserted.id
                    let raw = match.payload
                    Task { [weak self] in
                        guard let self else { return }
                        let framed = await todoFramingService.frame(rawPayload: raw, for: project)
                        guard framed != raw else { return }
                        structuredTodoStore.updateContent(id: todoID, content: framed)
                        await MainActor.run { self.refreshStructuredTodos() }
                        Log.info(.todo, "Hot-word todo framed: \(framed)")
                    }
                }

            case .addWorldModelInfo:
                if let project = resolvedProject, let pid = UUID(uuidString: project.id) {
                    worldModelService.appendInfo(match.payload, for: pid)
                } else {
                    worldModelService.write(worldModelService.read() + "\n- \(match.payload)")
                }
                Log.info(.world, "Hot-word added to world model")

            case .logOnly:
                Log.info(.system, "Hot-word log-only: \(match.payload)")
            }
        }
    }

    // MARK: - People persistence

    private static let peopleKey = "autoclawd.people"

    private static func init_loadPeople() -> [Person] {
        var people: [Person]
        if let data = UserDefaults.standard.data(forKey: peopleKey),
           let decoded = try? JSONDecoder().decode([Person].self, from: data),
           !decoded.isEmpty {
            people = decoded
        } else {
            people = [Person.makeMe()]
        }
        // Upgrade migration: ensure at least one Music person is present
        if !people.contains(where: { $0.isMusic }) {
            people.append(Person.makeMusic())
        }
        return people
    }

    private func savePeople() {
        if let data = try? JSONEncoder().encode(people) {
            UserDefaults.standard.set(data, forKey: Self.peopleKey)
        }
    }

    /// Name of the person currently tagged as speaker, or nil.
    var currentSpeakerName: String? {
        guard let id = currentSpeakerID else { return nil }
        return people.first(where: { $0.id == id })?.name
    }

    /// Toggle speaker: tap same person = clear, tap different = set.
    func toggleSpeaker(_ id: UUID) {
        currentSpeakerID = (currentSpeakerID == id) ? nil : id
    }

    /// Add a new person with the next unused color and auto-placed position.
    func addPerson(name: String) {
        let usedColors = Set(people.map { $0.colorIndex })
        let nextColor = PersonColor.allCases.first(where: { !usedColors.contains($0.rawValue) })
            ?? PersonColor.allCases[people.count % PersonColor.allCases.count]
        let angle = Double(people.count) * 137.5 * (.pi / 180)
        let r = 0.18 + Double(people.count) * 0.04
        let x = max(0.1, min(0.9, 0.5 + r * cos(angle)))
        let y = max(0.1, min(0.9, 0.5 + r * sin(angle)))
        let p = Person(id: UUID(), name: name, colorIndex: nextColor.rawValue,
                       mapPosition: CGPoint(x: x, y: y), isMe: false)
        people.append(p)
    }
}
