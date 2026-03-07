import Foundation

// MARK: - PipelineOrchestrator

/// Central coordinator for the multi-stage pipeline.
/// Called by ChunkManager instead of ExtractionService.classifyChunk().
///
/// Pipeline modes:
/// - Per-chunk (during session): raw text fires callback for display only. No Ollama.
/// - Session-end: full accumulated text → Clean → Analyze → Task Create → Execute.
///
/// A serial `SerialJobQueue` ensures Ollama is never hammered concurrently.
/// Jobs queue up and drain one-at-a-time, with a 1.5 s stagger between jobs
/// so the local model has time to settle before the next request arrives.
final class PipelineOrchestrator: @unchecked Sendable {
    private let cleaningService: TranscriptCleaningService
    private let analysisService: TranscriptAnalysisService
    private let taskCreationService: TaskCreationService
    private let taskExecutionService: TaskExecutionService

    var onPipelineUpdated: (() -> Void)?
    /// Called per-chunk with raw transcribed text for live display.
    /// No Ollama cleaning — just the raw SFSpeech/Groq transcript.
    var onTranscriptionCleaned: ((String) -> Void)?
    /// Called when session-end processing starts/finishes.
    /// True = actively cleaning or analysing. Used for widget glow.
    var onSessionProcessingChanged: ((Bool) -> Void)?

    /// Serial queue — never runs two Ollama calls in parallel.
    private var jobQueue: SerialJobQueue!

    init(cleaningService: TranscriptCleaningService,
         analysisService: TranscriptAnalysisService,
         taskCreationService: TaskCreationService,
         taskExecutionService: TaskExecutionService) {
        self.cleaningService = cleaningService
        self.analysisService = analysisService
        self.taskCreationService = taskCreationService
        self.taskExecutionService = taskExecutionService
        setup()
    }

    private func setup() {
        jobQueue = SerialJobQueue(stagger: 1.5) { [weak self] job in
            await self?._execute(job)
        }
    }

    // MARK: - Public API

    /// Enqueue a new transcript chunk for per-chunk processing (display only, no Ollama).
    /// Jobs are processed one-at-a-time with a 1.5 s stagger.
    func processTranscript(
        text: String,
        transcriptID: Int64,
        sessionID: String?,
        sessionChunkSeq: Int,
        durationSeconds: Int,
        speakerName: String?,
        source: PipelineSource = .ambient
    ) async {
        let job = PipelineJob(
            text: text, transcriptID: transcriptID,
            sessionID: sessionID, sessionChunkSeq: sessionChunkSeq,
            durationSeconds: durationSeconds, speakerName: speakerName,
            source: source
        )
        await jobQueue.enqueue(job)
    }

    /// Enqueue a session-end job. Full pipeline: Clean → Analyze → Tasks → Execute.
    /// Called when the user stops a session.
    func processSessionEnd(
        fullText: String,
        sessionID: String?,
        sessionContext: SessionConfig?,
        source: PipelineSource = .ambient
    ) async {
        let job = PipelineJob(
            text: fullText, transcriptID: 0,
            sessionID: sessionID, sessionChunkSeq: 0,
            durationSeconds: 0, speakerName: nil,
            source: source,
            isSessionEnd: true,
            sessionContext: sessionContext
        )
        await jobQueue.enqueue(job)
    }

    /// Execute a task that was manually accepted by the user.
    func executeAcceptedTask(_ task: PipelineTaskRecord) async {
        Log.info(.pipeline, "Pipeline: executing accepted task \(task.id)")
        await taskExecutionService.execute(task: task)
        await notifyUpdate()
    }

    // MARK: - Internal Execution

    /// Runs one pipeline job synchronously (called serially by SerialJobQueue).
    private func _execute(_ job: PipelineJob) async {
        let text             = job.text
        let sessionID        = job.sessionID
        let source           = job.source

        // (Code mode removed — all modes use the full pipeline)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // SESSION-END: Full pipeline on accumulated text
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        if job.isSessionEnd {
            Log.info(.pipeline, "Pipeline[session-end]: processing full session (\(text.count) chars, source=\(source.rawValue))")
            await executeSessionEnd(job)
            return
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // PER-CHUNK: Raw text callback for display only — no Ollama
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Log.info(.pipeline, "Pipeline[\(source.rawValue)]: per-chunk raw text (\(text.count) chars, session=\(sessionID ?? "none"))")

        // Fire raw text callback for live display in widget
        if !text.isEmpty {
            onTranscriptionCleaned?(text)
        }

        await notifyUpdate()

        // WhatsApp messages are self-contained — run full pipeline per-message
        if source == .whatsapp {
            Log.info(.pipeline, "Pipeline[whatsapp]: running full per-message pipeline")
            await executeFullPipeline(job)
            return
        }

        // All other per-chunk sources: display only, done.
        Log.info(.pipeline, "Pipeline[\(source.rawValue)]: per-chunk display done (analysis deferred to session end)")
    }

    // MARK: - Session-End Full Pipeline

    /// Run the full pipeline on the accumulated session text.
    private func executeSessionEnd(_ job: PipelineJob) async {
        let text = job.text
        let sessionID = job.sessionID
        let source = job.source
        let sessionContext = job.sessionContext

        // Signal processing started (widget glow)
        await MainActor.run { [weak self] in self?.onSessionProcessingChanged?(true) }

        // Use a local flag to ensure we always signal completion, even on early returns.
        defer {
            // Schedule on MainActor — safe to fire-and-forget from defer.
            let callback = onSessionProcessingChanged
            Task { @MainActor in callback?(false) }
        }

        // Stage 1: Clean the full session text
        Log.info(.pipeline, "Pipeline[session-end]: Stage 1 — cleaning full session text")
        guard let cleaned = await cleaningService.processNewTranscript(
            text: text,
            transcriptID: 0,
            sessionID: sessionID,
            sessionChunkSeq: 0,
            durationSeconds: 0,
            speakerName: nil
        ) else {
            Log.info(.pipeline, "Pipeline[session-end]: cleaning returned nil")
            return
        }
        await notifyUpdate()

        // Transcription mode: clean only — return the polished full-session transcript
        if source == .transcription {
            if !cleaned.cleanedText.isEmpty {
                onTranscriptionCleaned?(cleaned.cleanedText)
            }
            Log.info(.pipeline, "Pipeline[session-end/transcription]: cleaned \(cleaned.cleanedText.count) chars — done")
            return
        }

        // Ambient/other modes: fire the cleaned callback so the ambient review
        // canvas advances from .cleaning → .analyzing phase.
        if !cleaned.cleanedText.isEmpty {
            onTranscriptionCleaned?(cleaned.cleanedText)
        }

        // Ollama disabled: stop after cleaning
        let ollamaOn = SettingsManager.shared.isOllamaEnabled
        if !ollamaOn {
            Log.info(.pipeline, "Pipeline[session-end]: Ollama disabled — stopping after cleaning")
            return
        }

        // Stage 2: Analyze (with session context if available)
        Log.info(.pipeline, "Pipeline[session-end]: Stage 2 — analyzing")
        guard let analysis = await analysisService.analyze(
            cleaned: cleaned,
            sessionContext: sessionContext
        ) else {
            Log.info(.pipeline, "Pipeline[session-end]: analysis returned nil")
            return
        }
        await notifyUpdate()

        // Grab any context captures from this session
        let captures = ContextCaptureStore.shared.recentUnattached(sessionID: sessionID)
        let capturePaths = captures.map(\.filePath).filter { !$0.isEmpty }
        if !captures.isEmpty {
            Log.info(.pipeline, "Pipeline[session-end]: found \(captures.count) context capture(s)")
            ContextCaptureStore.shared.markAttached(ids: captures.map(\.id))
        }

        // Stage 3: Create tasks
        let tasks = await taskCreationService.createTasks(from: analysis, attachmentPaths: capturePaths)
        await notifyUpdate()

        if tasks.isEmpty {
            Log.info(.pipeline, "Pipeline[session-end]: no tasks created (non-actionable)")
            return
        }

        Log.info(.pipeline, "Pipeline[session-end]: \(tasks.count) task(s) created" +
                 (capturePaths.isEmpty ? "" : " with \(capturePaths.count) attachment(s)"))

        // (Tasks-only mode removed — execution proceeds for all pipeline sources)

        // Stage 4: Execute auto tasks
        let execOn = SettingsManager.shared.isCodeExecutionEnabled
        guard execOn else {
            Log.info(.pipeline, "Pipeline[session-end]: code execution disabled — tasks created but not run")
            return
        }

        for task in tasks where task.mode == .auto {
            await taskExecutionService.execute(task: task)
            await notifyUpdate()
        }

        Log.info(.pipeline, "Pipeline[session-end]: complete")
    }

    // MARK: - Legacy Full Pipeline (WhatsApp per-message)

    /// Full pipeline for self-contained messages (WhatsApp).
    private func executeFullPipeline(_ job: PipelineJob) async {
        let text            = job.text
        let transcriptID    = job.transcriptID
        let sessionID       = job.sessionID
        let sessionChunkSeq = job.sessionChunkSeq
        let durationSeconds = job.durationSeconds
        let speakerName     = job.speakerName

        // Stage 1: Clean
        guard let cleaned = await cleaningService.processNewTranscript(
            text: text,
            transcriptID: transcriptID,
            sessionID: sessionID,
            sessionChunkSeq: sessionChunkSeq,
            durationSeconds: durationSeconds,
            speakerName: speakerName
        ) else {
            return
        }
        await notifyUpdate()

        // Stage 2: Analyze
        guard let analysis = await analysisService.analyze(cleaned: cleaned) else {
            return
        }
        await notifyUpdate()

        // Stage 3: Create tasks
        let captures = ContextCaptureStore.shared.recentUnattached(sessionID: sessionID)
        let capturePaths = captures.map(\.filePath).filter { !$0.isEmpty }
        if !captures.isEmpty {
            ContextCaptureStore.shared.markAttached(ids: captures.map(\.id))
        }
        let tasks = await taskCreationService.createTasks(from: analysis, attachmentPaths: capturePaths)
        await notifyUpdate()

        guard !tasks.isEmpty else { return }

        // Stage 4: Execute
        let execOn = SettingsManager.shared.isCodeExecutionEnabled
        guard execOn else { return }

        for task in tasks where task.mode == .auto {
            await taskExecutionService.execute(task: task)
            await notifyUpdate()
        }
    }

    // MARK: - Private

    @MainActor
    private func notifyUpdate() {
        onPipelineUpdated?()
    }
}

// MARK: - PipelineJob

/// Value type that captures all parameters for a single pipeline run.
private struct PipelineJob {
    let text: String
    let transcriptID: Int64
    let sessionID: String?
    let sessionChunkSeq: Int
    let durationSeconds: Int
    let speakerName: String?
    let source: PipelineSource
    let isSessionEnd: Bool
    let sessionContext: SessionConfig?

    init(text: String, transcriptID: Int64, sessionID: String?,
         sessionChunkSeq: Int, durationSeconds: Int, speakerName: String?,
         source: PipelineSource, isSessionEnd: Bool = false,
         sessionContext: SessionConfig? = nil) {
        self.text = text
        self.transcriptID = transcriptID
        self.sessionID = sessionID
        self.sessionChunkSeq = sessionChunkSeq
        self.durationSeconds = durationSeconds
        self.speakerName = speakerName
        self.source = source
        self.isSessionEnd = isSessionEnd
        self.sessionContext = sessionContext
    }
}

// MARK: - SerialJobQueue

/// Actor-based serial queue.
/// Drains pipeline jobs one-at-a-time, inserting a brief stagger between them
/// so the local Ollama model is never hit with concurrent requests.
private actor SerialJobQueue {
    private var jobs: [PipelineJob] = []
    private var isDraining = false
    private let stagger: Double
    private let processor: (PipelineJob) async -> Void

    init(stagger: Double = 1.5, processor: @escaping (PipelineJob) async -> Void) {
        self.stagger = stagger
        self.processor = processor
    }

    func enqueue(_ job: PipelineJob) async {
        jobs.append(job)
        guard !isDraining else { return }
        isDraining = true
        await drain()
    }

    private func drain() async {
        while !jobs.isEmpty {
            let job = jobs.removeFirst()
            await processor(job)
            // Stagger only when there are more jobs waiting — avoids unnecessary delay
            // on the last job in the batch.
            if !jobs.isEmpty {
                try? await Task.sleep(for: .seconds(stagger))
            }
        }
        isDraining = false
    }
}
