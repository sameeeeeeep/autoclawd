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
            Log.info(.system, "Pill mode → \(pillMode.rawValue)")
        }
    }

    @Published var showAmbientWidget: Bool {
        didSet { SettingsManager.shared.showAmbientWidget = showAmbientWidget }
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

    // MARK: - Services

    private let storage = FileStorageManager.shared
    let chunkManager: ChunkManager
    private(set) var projectStore: ProjectStore
    private(set) var structuredTodoStore: StructuredTodoStore
    let locationService = LocationService.shared
    let nowPlaying = NowPlayingService()
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

        setupLogger()
        buildTranscriptionService()
        configureChunkManager()

        // Auto-activate Music person when NowPlayingService detects a song
        nowPlaying.$isPlaying
            .combineLatest(nowPlaying.$currentTitle)
            .receive(on: RunLoop.main)
            .sink { [weak self] isPlaying, title in
                guard let self else { return }
                guard let musicPerson = self.people.first(where: { $0.isMusic }) else { return }
                if isPlaying {
                    self.currentSpeakerID    = musicPerson.id
                    self.nowPlayingSongTitle = title
                } else if self.currentSpeakerID == musicPerson.id {
                    self.currentSpeakerID    = nil
                    self.nowPlayingSongTitle = nil
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
        hotkeys.start()

        if micEnabled {
            startListening()
        }

        refreshExtractionItems()
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
        // Ensure exactly one isMusic person exists (upgrade migration)
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
