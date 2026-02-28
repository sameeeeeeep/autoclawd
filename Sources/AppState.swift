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
            if oldValue == .code && pillMode != .code {
                resetCodeWidget()
            }
            Log.info(.system, "Pill mode → \(pillMode.rawValue)")
        }
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

    // MARK: - People roster & speaker tagging

    @Published var people: [Person] {
        didSet { savePeople() }
    }

    /// Transient — which person is currently speaking (nil = unknown).
    @Published var currentSpeakerID: UUID? = nil
    /// Transient — current song title set by NowPlayingService via Combine; nil when nothing is playing.
    @Published var nowPlayingSongTitle: String? = nil

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
    @Published var isCleaningUp = false

    @Published var projects: [Project] = []
    @Published var structuredTodos: [StructuredTodo] = []

    // Pipeline v2 published state
    @Published var cleanedTranscripts: [CleanedTranscript] = []
    @Published var transcriptAnalyses: [TranscriptAnalysis] = []
    @Published var pipelineTasks: [PipelineTaskRecord] = []
    @Published var skills: [Skill] = []

    // Widget live data — latest transcript chunk for the floating widget
    @Published var latestTranscriptChunk: String = ""

    // Code widget state
    @Published var codeWidgetStep: CodeWidgetStep = .projectSelect
    @Published var codeSelectedProject: Project? = nil
    @Published var codeSessionMessages: [CodeMessage] = []
    @Published var codeIsStreaming: Bool = false
    @Published var codeCurrentToolName: String? = nil
    @Published var codeSkipPermissions: Bool = true
    private(set) var codeSession: ClaudeSession? = nil
    private var codeStreamTask: Task<Void, Never>? = nil

    // WhatsApp state
    @Published var whatsAppStatus: WhatsAppStatus = .disconnected
    let whatsAppPoller = WhatsAppPoller()

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
    private var transcriptionService: (any Transcribable)?
    private let transcriptStore: TranscriptStore
    let extractionStore: ExtractionStore
    private let extractionService: ExtractionService
    private let cleanupService: CleanupService
    private let pasteService: TranscriptionPasteService
    private let qaService: QAService
    let qaStore: QAStore
    let claudeCodeRunner = ClaudeCodeRunner()

    // Pipeline v2 services
    let pipelineStore: PipelineStore
    let skillStore: SkillStore
    private let pipelineOrchestrator: PipelineOrchestrator
    private let taskExecutionService: TaskExecutionService

    // MARK: - Derived Content (refreshed on demand)

    var todosContent: String { todoService.read() }
    var worldModelContent: String { worldModelService.read() }

    // MARK: - Init

    init() {
        let settings = SettingsManager.shared

        transcriptionMode   = settings.transcriptionMode
        micEnabled          = settings.micEnabled
        audioRetentionDays  = settings.audioRetentionDays
        groqAPIKey          = settings.groqAPIKey
        synthesizeThreshold = settings.synthesizeThreshold
        showAmbientWidget    = settings.showAmbientWidget
        showToasts           = settings.showToasts
        appearanceMode      = settings.appearanceMode
        self.people       = AppState.init_loadPeople()
        self.locationName = UserDefaults.standard.string(forKey: "autoclawd.locationName") ?? "My Room"

        let savedMode = UserDefaults.standard.string(forKey: "pillMode")
            .flatMap { PillMode(rawValue: $0) } ?? .ambientIntelligence
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
        pasteService = TranscriptionPasteService()
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
            projectStore: projectStore
        )
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
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching() {
        Log.info(.system, "AutoClawd started. Mode: \(transcriptionMode.rawValue). RAM: (not measured)")
        ClipboardMonitor.shared.start()
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
                self.pillMode = .ambientIntelligence
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
        hotkeys.onTranscribeMode = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.pillMode = .transcription
                if !self.isListening { self.startListening() }
            }
        }
        hotkeys.onCodeMode = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.pillMode = .code
            }
        }
        hotkeys.start()

        if micEnabled {
            startListening()
        }

        refreshExtractionItems()
        refreshPipeline()

        // Start WhatsApp if previously connected
        if SettingsManager.shared.whatsAppEnabled {
            startWhatsApp()
        }
    }

    // MARK: - Listening Control

    func startListening() {
        guard !isListening else { return }
        chunkManager.startListening()
        isListening = true
        pillState = .listening
        Log.info(.ui, "Mic started")
    }

    func stopListening() {
        guard isListening else { return }
        chunkManager.stopListening()
        isListening = false
        pillState = .paused
        Log.info(.ui, "Mic stopped")
    }

    func toggleListening() {
        if isListening {
            // Pause: stop mic immediately and process the partial chunk
            chunkManager.pause()
            isListening = false
            pillState = .paused
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
            Log.info(.ui, "Mic resumed")
        }
    }

    func cyclePillMode() {
        pillMode = pillMode.next()
    }

    /// Re-paste the latest transcript chunk into the active text field.
    func applyLatestTranscript() {
        guard !latestTranscriptChunk.isEmpty else { return }
        pasteService.paste(text: latestTranscriptChunk)
    }

    // MARK: - Code Widget Actions

    /// Start a co-pilot session for the selected project (promptless — voice feeds in).
    func startCodeSession() {
        guard let project = codeSelectedProject else { return }
        codeSessionMessages = []
        codeIsStreaming = true
        codeWidgetStep = .copilot

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
        session.sendMessage(trimmed)
        codeIsStreaming = true
    }

    func stopCodeSession() {
        codeStreamTask?.cancel()
        codeStreamTask = nil
        codeSession?.stop()
        codeSession = nil
        codeIsStreaming = false
        codeCurrentToolName = nil
    }

    func resetCodeWidget() {
        stopCodeSession()
        codeWidgetStep = .projectSelect
        codeSessionMessages = []
    }

    private func processCodeStream(_ stream: AsyncThrowingStream<ClaudeEvent, Error>) async {
        var accumulatedText = ""
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

                case .toolUse(let name, _):
                    if !accumulatedText.isEmpty { accumulatedText = "" }
                    codeCurrentToolName = name
                    codeSessionMessages.append(CodeMessage(role: .tool, text: "Using \(name)…"))

                case .toolResult(let name, let output):
                    codeCurrentToolName = nil
                    let summary = output.isEmpty ? "\(name) done" : "\(name): \(String(output.prefix(120)))"
                    codeSessionMessages.append(CodeMessage(role: .tool, text: summary))

                case .result(let text):
                    if !accumulatedText.isEmpty { accumulatedText = "" }
                    if !text.isEmpty {
                        codeSessionMessages.append(CodeMessage(role: .assistant, text: text))
                    }
                    codeIsStreaming = false

                case .status(let msg):
                    codeSessionMessages.append(CodeMessage(role: .status, text: msg))

                case .error(let msg):
                    codeSessionMessages.append(CodeMessage(role: .error, text: msg))

                case .sessionInit:
                    break
                }
            }
        } catch {
            codeSessionMessages.append(
                CodeMessage(role: .error, text: error.localizedDescription)
            )
        }
        codeIsStreaming = false
    }

    // MARK: - WhatsApp

    /// Start WhatsApp sidecar + poller if enabled.
    func startWhatsApp() {
        guard SettingsManager.shared.whatsAppEnabled else { return }
        WhatsAppSidecar.shared.start()
        whatsAppPoller.start(appState: self)
        Log.info(.system, "WhatsApp integration started")
    }

    /// Stop WhatsApp sidecar + poller.
    func stopWhatsApp() {
        whatsAppPoller.stop()
        WhatsAppSidecar.shared.stop()
        whatsAppStatus = .disconnected
        Log.info(.system, "WhatsApp integration stopped")
    }

    /// Send a message via WhatsApp.
    func sendWhatsAppMessage(jid: String, text: String) async {
        do {
            try await WhatsAppService.shared.sendMessage(jid: jid, text: text)
            Log.info(.system, "[WhatsApp] Sent message to \(jid)")
        } catch {
            Log.warn(.system, "[WhatsApp] Failed to send: \(error)")
        }
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

        // Observe audio level changes
        chunkManager.$chunkIndex
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.audioLevel = self?.chunkManager.audioLevel ?? 0 }
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
            pasteService: pasteService,
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
