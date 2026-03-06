import Foundation

// MARK: - TaskExecutionService

/// Stage 4: Executes tasks based on their workflow. Logs steps progressively.
/// Now uses interactive streaming (stream-json) for real-time progress.
/// Supports OpenClaw skill instruction injection for expanded execution capabilities.
final class TaskExecutionService: @unchecked Sendable {
    private let pipelineStore: PipelineStore
    private let claudeCodeRunner: ClaudeCodeRunner
    private let projectStore: ProjectStore
    private let skillStore: SkillStore

    /// Active sessions keyed by task ID — allows follow-up messages.
    private var activeSessions: [String: ClaudeSession] = [:]
    private let sessionsLock = NSLock()

    /// Callback fired when execution steps change (for UI refresh).
    var onStepUpdated: (() -> Void)?

    init(pipelineStore: PipelineStore, claudeCodeRunner: ClaudeCodeRunner,
         projectStore: ProjectStore, skillStore: SkillStore) {
        self.pipelineStore = pipelineStore
        self.claudeCodeRunner = claudeCodeRunner
        self.projectStore = projectStore
        self.skillStore = skillStore
    }

    // MARK: - Public API

    func execute(task: PipelineTaskRecord) async {
        guard task.status == .upcoming || task.status == .ongoing else { return }

        // Mark as ongoing (if not already) and log start
        if task.status == .upcoming {
            pipelineStore.updateTaskStatus(id: task.id, status: .ongoing, startedAt: Date())
        }
        logStep(taskID: task.id, index: 0, description: "Task execution started")

        // Resolve project path
        guard let projectID = task.projectID,
              let project = projectStore.all().first(where: { $0.id == projectID }) else {
            logStep(taskID: task.id, index: 1, description: "No project path resolved", status: "failed")
            pipelineStore.updateTaskStatus(id: task.id, status: .needs_input)
            Log.warn(.taskExec, "Task \(task.id): no project path, marking needs_input")
            return
        }

        // Route based on workflow (default to claude-code for nil/unknown)
        let effectiveWorkflow = task.workflowID ?? "autoclawd-claude-code"
        switch effectiveWorkflow {
        case "autoclawd-claude-code", "autoclawd-claude-code-linear", "autoclawd-claude-code-meta":
            await executeViaClaude(task: task, project: project)
        case "autoclawd-openclaw":
            await executeViaOpenClaw(task: task, project: project)
        default:
            logStep(taskID: task.id, index: 1,
                    description: "No executable workflow for '\(effectiveWorkflow)'",
                    status: "failed")
            pipelineStore.updateTaskStatus(id: task.id, status: .needs_input)
            Log.info(.taskExec, "Task \(task.id): no executable workflow '\(effectiveWorkflow)', marking needs_input")
        }
    }

    /// Send a follow-up message to an active Claude session (with optional attachments).
    func sendMessage(taskID: String, message: String, attachments: [Attachment] = []) {
        let session = sessionsLock.withLock { activeSessions[taskID] }

        guard let session = session, session.isRunning else {
            Log.warn(.taskExec, "Task \(taskID): no active session for follow-up")
            return
        }
        session.sendMessage(message, attachments: attachments)
        // Log the user's message as a step (with attachment indicators)
        let steps = pipelineStore.fetchSteps(taskID: taskID)
        let nextIdx = (steps.map(\.stepIndex).max() ?? 0) + 1
        let attachSuffix = attachments.isEmpty ? "" : " [\(attachments.map(\.fileName).joined(separator: ", "))]"
        logStep(taskID: taskID, index: nextIdx, description: "You: \(message)\(attachSuffix)")
    }

    /// Stop an active session.
    func stopSession(taskID: String) {
        let session = sessionsLock.withLock { activeSessions.removeValue(forKey: taskID) }
        session?.stop()
    }

    /// Check if a task has an active session.
    func hasActiveSession(taskID: String) -> Bool {
        return sessionsLock.withLock { activeSessions[taskID]?.isRunning == true }
    }

    // MARK: - Claude Code Execution (Interactive Streaming)

    private func executeViaClaude(task: PipelineTaskRecord, project: Project) async {
        // Load any context capture attachments associated with this task
        let attachments: [Attachment] = task.attachmentPaths.compactMap { path in
            ContextCaptureStore.loadAttachment(path: path)
        }
        if !attachments.isEmpty {
            logStep(taskID: task.id, index: 1,
                    description: "Starting Claude Code session with \(attachments.count) attachment(s)...")
        } else {
            logStep(taskID: task.id, index: 1, description: "Starting Claude Code session...")
        }
        Log.info(.taskExec, "Task \(task.id): executing via Claude Code in \(project.localPath)" +
                 (attachments.isEmpty ? "" : " with \(attachments.count) attachment(s)"))

        guard let (session, eventStream) = claudeCodeRunner.startSession(
            prompt: task.prompt,
            in: project,
            attachments: attachments
        ) else {
            logStep(taskID: task.id, index: 2, description: "Failed to start Claude CLI", status: "failed")
            pipelineStore.updateTaskStatus(id: task.id, status: .needs_input)
            return
        }

        // Store session for follow-up messages
        sessionsLock.withLock { activeSessions[task.id] = session }

        // Stream events using shared logic
        await streamClaudeEvents(taskID: task.id, session: session, eventStream: eventStream, startStepIdx: 2)
    }

    // MARK: - OpenClaw Skill Execution

    /// Execute a task using an OpenClaw skill. Loads the skill's SKILL.md instructions
    /// and prepends them to the Claude Code prompt so Claude has the skill context.
    private func executeViaOpenClaw(task: PipelineTaskRecord, project: Project) async {
        // Load the matched skill and its instructions
        let skill = task.skillID.flatMap { skillStore.load(id: $0) }
        let instructions = skill?.instructions ?? ""

        if !instructions.isEmpty {
            logStep(taskID: task.id, index: 1,
                    description: "Loading OpenClaw skill: \(skill?.name ?? task.skillID ?? "unknown")")
        } else {
            logStep(taskID: task.id, index: 1,
                    description: "OpenClaw skill has no instructions, falling back to direct execution")
        }

        // Build the enhanced prompt with skill instructions prepended
        let enhancedPrompt: String
        if !instructions.isEmpty {
            enhancedPrompt = """
            # Skill Instructions

            You have been given a specific skill with detailed instructions on how to complete this type of task. Follow these instructions carefully.

            \(instructions)

            ---

            # Task

            \(task.prompt)
            """
        } else {
            enhancedPrompt = task.prompt
        }

        // Inject skill-specific environment variables if present
        let skillEnvVars = skill?.envVars

        // Load context capture attachments
        let attachments: [Attachment] = task.attachmentPaths.compactMap { path in
            ContextCaptureStore.loadAttachment(path: path)
        }

        let attachDesc = attachments.isEmpty ? "" : " with \(attachments.count) attachment(s)"
        logStep(taskID: task.id, index: 2,
                description: "Starting Claude Code session with OpenClaw skill context\(attachDesc)...")
        Log.info(.taskExec, "Task \(task.id): executing via OpenClaw skill '\(skill?.name ?? "?")' in \(project.localPath)")

        guard let (session, eventStream) = claudeCodeRunner.startSession(
            prompt: enhancedPrompt,
            in: project,
            attachments: attachments,
            extraEnvVars: skillEnvVars
        ) else {
            logStep(taskID: task.id, index: 3, description: "Failed to start Claude CLI", status: "failed")
            pipelineStore.updateTaskStatus(id: task.id, status: .needs_input)
            return
        }

        // Store session for follow-up messages
        sessionsLock.withLock { activeSessions[task.id] = session }

        // Stream events (reuse the same streaming logic as executeViaClaude)
        await streamClaudeEvents(taskID: task.id, session: session, eventStream: eventStream, startStepIdx: 3)
    }

    // MARK: - Shared Claude Streaming

    /// Shared event streaming logic used by both executeViaClaude and executeViaOpenClaw.
    private func streamClaudeEvents(
        taskID: String,
        session: ClaudeSession,
        eventStream: AsyncThrowingStream<ClaudeEvent, Error>,
        startStepIdx: Int
    ) async {
        var stepIdx = startStepIdx
        var currentToolName: String? = nil
        var accumulatedText = ""
        var lastTextFlushTime = Date()

        do {
            for try await event in eventStream {
                switch event {
                case .sessionInit(let sid):
                    logStep(taskID: taskID, index: stepIdx, description: "Session: \(sid.prefix(12))...")
                    stepIdx += 1

                case .toolUse(let name, let input):
                    if !accumulatedText.isEmpty {
                        logStep(taskID: taskID, index: stepIdx, description: accumulatedText)
                        stepIdx += 1
                        accumulatedText = ""
                    }
                    currentToolName = name
                    let desc = input.isEmpty ? "Using \(name)..." : "Using \(name): \(input.prefix(120))"
                    logStep(taskID: taskID, index: stepIdx, description: desc)
                    stepIdx += 1
                    notifyUI()

                case .toolResult(_, let output):
                    if let tool = currentToolName {
                        let desc = "\(tool) done" + (output.isEmpty ? "" : ": \(output.prefix(200))")
                        logStep(taskID: taskID, index: stepIdx, description: desc)
                        stepIdx += 1
                        currentToolName = nil
                        notifyUI()
                    }

                case .text(let text):
                    accumulatedText += text
                    let now = Date()
                    if now.timeIntervalSince(lastTextFlushTime) > 2.0 || accumulatedText.contains("\n") {
                        let trimmed = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            logStep(taskID: taskID, index: stepIdx, description: trimmed)
                            stepIdx += 1
                            notifyUI()
                        }
                        accumulatedText = ""
                        lastTextFlushTime = now
                    }

                case .result(let text):
                    if !accumulatedText.isEmpty {
                        let trimmed = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            logStep(taskID: taskID, index: stepIdx, description: trimmed)
                            stepIdx += 1
                        }
                        accumulatedText = ""
                    }
                    if !text.isEmpty {
                        logStep(taskID: taskID, index: stepIdx, description: text)
                        stepIdx += 1
                    }
                    logStep(taskID: taskID, index: stepIdx, description: "Task completed successfully")
                    pipelineStore.updateTaskStatus(id: taskID, status: .completed, completedAt: Date())
                    Log.info(.taskExec, "Task \(taskID): completed")
                    notifyUI()

                case .status(let msg):
                    logStep(taskID: taskID, index: stepIdx, description: msg, status: "running")
                    stepIdx += 1
                    notifyUI()

                case .error(let msg):
                    logStep(taskID: taskID, index: stepIdx, description: "Error: \(msg)", status: "failed")
                    stepIdx += 1
                    notifyUI()
                }
            }

            // Stream ended
            let currentStatus = pipelineStore.fetchRecentTasks().first { $0.id == taskID }?.status
            if currentStatus == .ongoing {
                if !accumulatedText.isEmpty {
                    let trimmed = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        logStep(taskID: taskID, index: stepIdx, description: trimmed)
                        stepIdx += 1
                    }
                }
                logStep(taskID: taskID, index: stepIdx, description: "Task completed successfully")
                pipelineStore.updateTaskStatus(id: taskID, status: .completed, completedAt: Date())
                Log.info(.taskExec, "Task \(taskID): completed (stream ended)")
                notifyUI()
            }

        } catch {
            logStep(taskID: taskID, index: stepIdx,
                    description: "Execution failed: \(error.localizedDescription)", status: "failed")
            pipelineStore.updateTaskStatus(id: taskID, status: .needs_input)
            Log.error(.taskExec, "Task \(taskID): execution failed: \(error.localizedDescription)")
            notifyUI()
        }

        // Clean up session
        _ = sessionsLock.withLock { activeSessions.removeValue(forKey: taskID) }
    }

    // MARK: - Helpers

    private func logStep(taskID: String, index: Int, description: String, status: String = "completed") {
        let step = TaskExecutionStep(
            id: UUID().uuidString,
            taskID: taskID,
            stepIndex: index,
            description: description,
            status: status,
            timestamp: Date(),
            output: nil
        )
        pipelineStore.insertStep(step)
    }

    private func notifyUI() {
        onStepUpdated?()
    }

    // MARK: - Self-Rebuild ("robot changes its own batteries")

    /// Check if a project path points to AutoClawd's own source.
    private static func isAutoClawdProject(path: String) -> Bool {
        let normalized = (path as NSString).standardizingPath
        // Check if Package.swift exists and contains "AutoClawd"
        let packageSwift = (normalized as NSString).appendingPathComponent("Package.swift")
        if FileManager.default.fileExists(atPath: packageSwift),
           let contents = try? String(contentsOfFile: packageSwift, encoding: .utf8),
           contents.contains("AutoClawd") {
            return true
        }
        // Fallback: check if the Makefile and AutoClawd-adhoc.entitlements exist
        let makefile = (normalized as NSString).appendingPathComponent("Makefile")
        let entitlements = (normalized as NSString).appendingPathComponent("AutoClawd-adhoc.entitlements")
        return FileManager.default.fileExists(atPath: makefile)
            && FileManager.default.fileExists(atPath: entitlements)
    }

    /// Open Terminal.app with rebuild + re-sign + relaunch commands.
    /// AutoClawd can't rebuild itself inline (it would kill its own parent process),
    /// so we spawn a detached terminal that builds, signs, kills, and relaunches.
    static func openRebuildTerminal(projectPath: String, taskID: String) {
        let script = """
        tell application "Terminal"
            activate
            do script "echo '🔧 AutoClawd self-rebuild (task \(taskID))' && cd '\(projectPath)' && make && codesign --force --sign \\"-\\" --entitlements AutoClawd-adhoc.entitlements build/AutoClawd.app && echo '✅ Build + sign done. Relaunching...' && sleep 1 && pkill -x AutoClawd; sleep 2; open build/AutoClawd.app && echo '🚀 AutoClawd relaunched.'"
        end tell
        """
        Log.info(.taskExec, "Task \(taskID): opening Terminal for self-rebuild")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        try? proc.run()
    }
}
