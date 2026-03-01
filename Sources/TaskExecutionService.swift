import Foundation

// MARK: - TaskExecutionService

/// Stage 4: Executes tasks based on their workflow. Logs steps progressively.
/// Now uses interactive streaming (stream-json) for real-time progress.
final class TaskExecutionService: @unchecked Sendable {
    private let pipelineStore: PipelineStore
    private let claudeCodeRunner: ClaudeCodeRunner
    private let projectStore: ProjectStore

    /// Active sessions keyed by task ID — allows follow-up messages.
    private var activeSessions: [String: ClaudeSession] = [:]
    private let sessionsLock = NSLock()

    /// Callback fired when execution steps change (for UI refresh).
    var onStepUpdated: (() -> Void)?

    init(pipelineStore: PipelineStore, claudeCodeRunner: ClaudeCodeRunner,
         projectStore: ProjectStore) {
        self.pipelineStore = pipelineStore
        self.claudeCodeRunner = claudeCodeRunner
        self.projectStore = projectStore
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
        sessionsLock.lock()
        let session = activeSessions[taskID]
        sessionsLock.unlock()

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
        sessionsLock.lock()
        let session = activeSessions.removeValue(forKey: taskID)
        sessionsLock.unlock()
        session?.stop()
    }

    /// Check if a task has an active session.
    func hasActiveSession(taskID: String) -> Bool {
        sessionsLock.lock()
        defer { sessionsLock.unlock() }
        return activeSessions[taskID]?.isRunning == true
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
        sessionsLock.lock()
        activeSessions[task.id] = session
        sessionsLock.unlock()

        var stepIdx = 2
        var currentToolName: String? = nil
        var accumulatedText = ""
        var lastTextFlushTime = Date()

        do {
            for try await event in eventStream {
                switch event {
                case .sessionInit(let sid):
                    logStep(taskID: task.id, index: stepIdx, description: "Session: \(sid.prefix(12))...")
                    stepIdx += 1

                case .toolUse(let name, let input):
                    // Flush any accumulated text first
                    if !accumulatedText.isEmpty {
                        logStep(taskID: task.id, index: stepIdx, description: accumulatedText)
                        stepIdx += 1
                        accumulatedText = ""
                    }
                    currentToolName = name
                    let desc = input.isEmpty ? "Using \(name)..." : "Using \(name): \(input.prefix(120))"
                    logStep(taskID: task.id, index: stepIdx, description: desc)
                    stepIdx += 1
                    notifyUI()

                case .toolResult(_, let output):
                    if let tool = currentToolName {
                        let desc = "\(tool) done" + (output.isEmpty ? "" : ": \(output.prefix(200))")
                        logStep(taskID: task.id, index: stepIdx, description: desc)
                        stepIdx += 1
                        currentToolName = nil
                        notifyUI()
                    }

                case .text(let text):
                    accumulatedText += text
                    // Flush text periodically (every 2s or at newlines)
                    let now = Date()
                    if now.timeIntervalSince(lastTextFlushTime) > 2.0 || accumulatedText.contains("\n") {
                        let trimmed = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            logStep(taskID: task.id, index: stepIdx, description: trimmed)
                            stepIdx += 1
                            notifyUI()
                        }
                        accumulatedText = ""
                        lastTextFlushTime = now
                    }

                case .result(let text):
                    // Flush remaining text
                    if !accumulatedText.isEmpty {
                        let trimmed = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            logStep(taskID: task.id, index: stepIdx, description: trimmed)
                            stepIdx += 1
                        }
                        accumulatedText = ""
                    }
                    // Log final result
                    if !text.isEmpty {
                        logStep(taskID: task.id, index: stepIdx, description: text)
                        stepIdx += 1
                    }
                    logStep(taskID: task.id, index: stepIdx, description: "Task completed successfully")
                    pipelineStore.updateTaskStatus(id: task.id, status: .completed, completedAt: Date())
                    Log.info(.taskExec, "Task \(task.id): completed")
                    notifyUI()

                case .status(let msg):
                    // Update the latest step or add a new one for status messages
                    logStep(taskID: task.id, index: stepIdx, description: msg, status: "running")
                    stepIdx += 1
                    notifyUI()

                case .error(let msg):
                    logStep(taskID: task.id, index: stepIdx, description: "Error: \(msg)", status: "failed")
                    stepIdx += 1
                    notifyUI()
                }
            }

            // Stream ended — if no explicit result event, mark as complete
            let currentStatus = pipelineStore.fetchRecentTasks().first { $0.id == task.id }?.status
            if currentStatus == .ongoing {
                // Flush remaining text
                if !accumulatedText.isEmpty {
                    let trimmed = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        logStep(taskID: task.id, index: stepIdx, description: trimmed)
                        stepIdx += 1
                    }
                }
                logStep(taskID: task.id, index: stepIdx, description: "Task completed successfully")
                pipelineStore.updateTaskStatus(id: task.id, status: .completed, completedAt: Date())
                Log.info(.taskExec, "Task \(task.id): completed (stream ended)")
                notifyUI()
            }

        } catch {
            logStep(taskID: task.id, index: stepIdx,
                    description: "Execution failed: \(error.localizedDescription)", status: "failed")
            pipelineStore.updateTaskStatus(id: task.id, status: .needs_input)
            Log.error(.taskExec, "Task \(task.id): execution failed: \(error.localizedDescription)")
            notifyUI()
        }

        // Clean up session
        sessionsLock.lock()
        activeSessions.removeValue(forKey: task.id)
        sessionsLock.unlock()
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
