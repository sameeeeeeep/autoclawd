import Foundation

// MARK: - PipelineOrchestrator

/// Central coordinator for the multi-stage pipeline.
/// Called by ChunkManager instead of ExtractionService.classifyChunk().
///
/// Pipeline: Raw Transcript → Cleaning → Analysis → Task Creation → Task Execution
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
    /// Called after cleaning completes for transcription-mode chunks.
    /// Receives the cleaned text so AppState can accumulate it for the live transcript display.
    var onTranscriptionCleaned: ((String) -> Void)?

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

    /// Enqueue a new transcript for serial pipeline processing.
    /// Jobs are processed one-at-a-time with a 1.5 s stagger so Ollama is never
    /// hit concurrently. Old unprocessed jobs are still run (FIFO order).
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
        let transcriptID     = job.transcriptID
        let sessionID        = job.sessionID
        let sessionChunkSeq  = job.sessionChunkSeq
        let durationSeconds  = job.durationSeconds
        let speakerName      = job.speakerName
        let source           = job.source

        Log.info(.pipeline, "Pipeline[\(source.rawValue)]: processing transcript (\(text.count) chars, session=\(sessionID ?? "none"), seq=\(sessionChunkSeq))")

        // Code mode: the widget manages its own execution — no pipeline stages needed.
        if source == .code {
            Log.info(.pipeline, "Pipeline[code]: skipping all stages (code widget handles execution)")
            await notifyUpdate()
            return
        }

        // Stage 1: Clean (runs for all non-code sources)
        guard let cleaned = await cleaningService.processNewTranscript(
            text: text,
            transcriptID: transcriptID,
            sessionID: sessionID,
            sessionChunkSeq: sessionChunkSeq,
            durationSeconds: durationSeconds,
            speakerName: speakerName
        ) else {
            Log.info(.pipeline, "Pipeline: cleaning returned nil (likely waiting for more chunks)")
            return
        }

        await notifyUpdate()

        // Always fire the cleaned callback so the transcript widget accumulates text for all modes.
        // This enables session-long transcript retention regardless of pill mode.
        if !cleaned.cleanedText.isEmpty {
            onTranscriptionCleaned?(cleaned.cleanedText)
        }

        // Transcription mode: clean only — stop here.
        if source == .transcription {
            Log.info(.pipeline, "Pipeline[transcription]: stopping after cleaning stage")
            return
        }

        // Ollama disabled: ambient transcripts stop after cleaning to save battery/tokens.
        let ollamaOn = SettingsManager.shared.isOllamaEnabled
        if !ollamaOn && source == .ambient {
            Log.info(.pipeline, "Pipeline[ambient]: Ollama disabled — stopping after cleaning stage")
            return
        }

        // Stage 2: Analyze (ambient + whatsapp + tasks)
        guard let analysis = await analysisService.analyze(cleaned: cleaned) else {
            Log.info(.pipeline, "Pipeline: analysis returned nil")
            return
        }

        await notifyUpdate()

        // Grab any context captures (screenshots, clipboard images) from this session
        let captures = ContextCaptureStore.shared.recentUnattached(sessionID: sessionID)
        let capturePaths = captures.map(\.filePath).filter { !$0.isEmpty }
        if !captures.isEmpty {
            Log.info(.pipeline, "Pipeline: found \(captures.count) context capture(s) for session")
            ContextCaptureStore.shared.markAttached(ids: captures.map(\.id))
        }

        // Stage 3: Create tasks (with attached context captures)
        let tasks = await taskCreationService.createTasks(from: analysis, attachmentPaths: capturePaths)

        await notifyUpdate()

        if tasks.isEmpty {
            Log.info(.pipeline, "Pipeline: no tasks created (non-actionable transcript)")
            return
        }

        Log.info(.pipeline, "Pipeline: \(tasks.count) task(s) created" +
                 (capturePaths.isEmpty ? "" : " with \(capturePaths.count) attachment(s)"))

        // Tasks mode: stop after task creation — no auto-execution.
        if source == .tasks {
            Log.info(.pipeline, "Pipeline[tasks]: task creation complete — skipping execution")
            return
        }

        // Stage 4: Execute auto tasks (respects isCodeExecutionEnabled toggle)
        let execOn = SettingsManager.shared.isCodeExecutionEnabled
        guard execOn else {
            Log.info(.pipeline, "Pipeline: code execution disabled — tasks created but not run")
            return
        }

        for task in tasks where task.mode == .auto {
            await taskExecutionService.execute(task: task)
            await notifyUpdate()
        }

        Log.info(.pipeline, "Pipeline: complete")
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
