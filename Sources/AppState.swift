import AVFoundation
import Combine
import Foundation
import SwiftUI

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

    @Published var pendingUnknownSSID: String? = nil
    @Published var wifiLabelInput: String = ""

    @Published var extractionItems: [ExtractionItem] = []
    @Published var pendingExtractionCount: Int = 0
    @Published var synthesizeThreshold: Int {
        didSet { SettingsManager.shared.synthesizeThreshold = synthesizeThreshold }
    }

    // MARK: - Services

    private let storage = FileStorageManager.shared
    let chunkManager: ChunkManager
    let locationService = LocationService.shared
    private let ollama = OllamaService()
    private let worldModelService = WorldModelService()
    private let todoService = TodoService()
    private var transcriptionService: TranscriptionService?
    private let transcriptStore: TranscriptStore
    let extractionStore: ExtractionStore
    private let extractionService: ExtractionService
    private let pasteService: TranscriptionPasteService
    private let qaService: QAService
    let qaStore: QAStore

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

        let savedMode = UserDefaults.standard.string(forKey: "pillMode")
            .flatMap { PillMode(rawValue: $0) } ?? .ambientIntelligence
        pillMode = savedMode

        transcriptStore = TranscriptStore(url: FileStorageManager.shared.transcriptsDatabaseURL)
        let exStore = ExtractionStore(url: FileStorageManager.shared.intelligenceDatabaseURL)
        extractionStore = exStore
        extractionService = ExtractionService(
            ollama: OllamaService(),
            worldModel: WorldModelService(),
            todos: TodoService(),
            store: exStore
        )
        pasteService = TranscriptionPasteService()
        qaService    = QAService(ollama: OllamaService())
        qaStore      = QAStore()
        chunkManager = ChunkManager()

        setupLogger()
        buildTranscriptionService()
        configureChunkManager()
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
        hotkeys.onTranscribeNow = { [weak self] in
            Task { @MainActor in self?.chunkManager.pause() }
        }
        hotkeys.onToggleMic = { [weak self] in
            Task { @MainActor in self?.toggleListening() }
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
        await MainActor.run { refreshExtractionItems() }
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
        let key = groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            transcriptionService = TranscriptionService(apiKey: key)
        } else {
            transcriptionService = nil
        }
        reconfigureChunkManager()
    }

    private func rebuildTranscriptionService() {
        buildTranscriptionService()
    }

    private func configureChunkManager() {
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
}
