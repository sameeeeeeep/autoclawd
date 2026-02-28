import AppKit
import Foundation

// MARK: - ClaudeCodeError

enum ClaudeCodeError: LocalizedError {
    case notFound
    case exitCode(Int32)
    case authFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "claude CLI not found. Install via: npm install -g @anthropic-ai/claude-code"
        case .exitCode(let code):
            return "claude exited with code \(code)"
        case .authFailed(let msg):
            return "Authentication failed: \(msg)"
        }
    }
}

// MARK: - Claude Event (Stream JSON)

/// Structured events parsed from `--output-format stream-json`.
enum ClaudeEvent {
    case sessionInit(sessionID: String)
    case text(String)                                 // assistant text being generated
    case toolUse(name: String, input: String)         // tool call started
    case toolResult(name: String, output: String)     // tool call result
    case result(text: String)                         // final result
    case error(String)                                // error message
    case status(String)                               // progress/status update
}

// MARK: - Claude Session

/// An interactive streaming session with the Claude CLI.
/// Uses `--output-format stream-json --input-format stream-json` for real-time events.
final class ClaudeSession: @unchecked Sendable {
    let sessionID: String
    private let process: Process
    private let stdinPipe: Pipe
    private let stdoutPipe: Pipe
    var isRunning = true

    init(sessionID: String, process: Process, stdinPipe: Pipe, stdoutPipe: Pipe) {
        self.sessionID = sessionID
        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
    }

    /// Send a follow-up message to Claude (for back-and-forth conversation).
    func sendMessage(_ text: String) {
        guard isRunning else { return }
        let msg: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": text
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: msg),
              let json = String(data: data, encoding: .utf8) else { return }
        let line = json + "\n"
        stdinPipe.fileHandleForWriting.write(line.data(using: .utf8)!)
        Log.info(.taskExec, "ClaudeSession: sent follow-up message (\(text.prefix(60))...)")
    }

    /// Stop the session.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        stdinPipe.fileHandleForWriting.closeFile()
        if process.isRunning { process.terminate() }
    }

    deinit {
        stop()
    }
}

// MARK: - ClaudeCodeRunner

final class ClaudeCodeRunner: Sendable {

    // MARK: - CLI Discovery

    static func findCLI() -> URL? {
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/bin/claude",
        ]
        // Check ~/.local/bin first (common install path)
        let localBin = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/claude").path
        if FileManager.default.isExecutableFile(atPath: localBin) {
            return URL(fileURLWithPath: localBin)
        }
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        // Fall back to `which claude` in login shell (picks up nvm / volta / etc.)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-l", "-c", "which claude"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let found = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !found.isEmpty,
           FileManager.default.isExecutableFile(atPath: found) {
            return URL(fileURLWithPath: found)
        }
        return nil
    }

    // MARK: - Interactive Streaming Session

    /// Starts an interactive streaming session with Claude Code CLI.
    /// Returns a tuple of (session, event stream) for real-time processing.
    /// Uses `--output-format stream-json --input-format stream-json`.
    func startSession(
        prompt: String,
        in project: Project,
        resumeSessionID: String? = nil
    ) -> (ClaudeSession, AsyncThrowingStream<ClaudeEvent, Error>)? {
        guard let claudeURL = ClaudeCodeRunner.findCLI() else {
            Log.error(.taskExec, "Claude CLI not found")
            return nil
        }

        let process = Process()
        process.executableURL = claudeURL

        var args: [String] = [
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--dangerously-skip-permissions",
        ]
        if let mcpConfigPath = MCPConfigManager.configPath() {
            args += ["--mcp-config", mcpConfigPath]
        }
        if let sid = resumeSessionID {
            args += ["--resume", sid]
        }
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: project.localPath)

        // Set up environment
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_OAUTH_TOKEN")
        env.removeValue(forKey: "ANTHROPIC_API_KEY")
        let apiKeyVal = SettingsManager.shared.anthropicAPIKey
        if !apiKeyVal.isEmpty {
            Self.setAuthEnv(apiKeyVal, into: &env)
        } else {
            Log.warn(.taskExec, "Claude CLI: NO API key in settings")
        }
        process.environment = env

        // Set up pipes
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            Log.error(.taskExec, "Failed to start Claude CLI: \(error)")
            return nil
        }

        let sessionPlaceholder = UUID().uuidString
        let session = ClaudeSession(
            sessionID: sessionPlaceholder,
            process: process,
            stdinPipe: stdinPipe,
            stdoutPipe: stdoutPipe
        )

        // Send initial prompt via stdin
        let initialMsg: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": prompt
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: initialMsg),
           let json = String(data: data, encoding: .utf8) {
            let line = json + "\n"
            stdinPipe.fileHandleForWriting.write(line.data(using: .utf8)!)
            Log.info(.taskExec, "ClaudeSession: sent initial prompt (\(prompt.count) chars)")
        }

        // Create event stream by parsing NDJSON from stdout using readabilityHandler
        // (FileHandle.bytes.lines doesn't work reliably with Process Pipes on macOS)
        let eventStream = AsyncThrowingStream<ClaudeEvent, Error> { continuation in
            var stdoutBuffer = Data()

            // Read stderr in background for debugging
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let text = String(data: data, encoding: .utf8) {
                    for line in text.components(separatedBy: "\n") where !line.isEmpty {
                        Log.warn(.taskExec, "Claude CLI stderr: \(line)")
                    }
                }
            }

            // Read stdout and parse NDJSON events
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    // EOF — process finished
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    session.isRunning = false
                    let status = process.terminationStatus
                    if status != 0 {
                        continuation.finish(throwing: ClaudeCodeError.exitCode(status))
                    } else {
                        continuation.finish()
                    }
                    return
                }

                stdoutBuffer.append(data)

                // Split buffer on newlines and process complete lines
                while let newlineRange = stdoutBuffer.range(of: Data("\n".utf8)) {
                    let lineData = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<newlineRange.lowerBound)
                    stdoutBuffer.removeSubrange(stdoutBuffer.startIndex..<newlineRange.upperBound)

                    guard let line = String(data: lineData, encoding: .utf8),
                          !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

                    guard let jsonData = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                          let type = json["type"] as? String else {
                        Log.info(.taskExec, "Claude stream (non-JSON): \(line.prefix(200))")
                        continuation.yield(.error(line))
                        continue
                    }

                    let subtype = (json["subtype"] as? String) ?? ""
                    Log.info(.taskExec, "Claude stream event: type=\(type) subtype=\(subtype)")

                    if let event = Self.parseEvent(type: type, json: json) {
                        continuation.yield(event)
                    }
                }
            }

            // Handle process termination
            process.terminationHandler = { proc in
                // Give readabilityHandler a moment to process remaining data
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    session.isRunning = false
                    let status = proc.terminationStatus
                    if status != 0 {
                        continuation.finish(throwing: ClaudeCodeError.exitCode(status))
                    } else {
                        continuation.finish()
                    }
                }
            }
        }

        return (session, eventStream)
    }

    // MARK: - Event Parsing

    /// Parse an NDJSON event from the stream-json output.
    /// Returns one or more events (using an array internally, yielding first).
    private static func parseEvent(type: String, json: [String: Any]) -> ClaudeEvent? {
        switch type {
        case "system":
            let subtype = json["subtype"] as? String
            if subtype == "init", let sid = json["session_id"] as? String {
                return .sessionInit(sessionID: sid)
            }
            if subtype == "compact_boundary" {
                return .status("Compacting conversation context...")
            }
            return nil

        case "assistant":
            // Complete assistant message — extract text and tool use from content blocks
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                var texts: [String] = []
                var toolNames: [String] = []
                for block in content {
                    let blockType = block["type"] as? String
                    if blockType == "text", let text = block["text"] as? String {
                        texts.append(text)
                    } else if blockType == "tool_use" {
                        let name = block["name"] as? String ?? "unknown"
                        let input = block["input"] as? [String: Any]
                        let inputStr = Self.formatToolInput(name: name, input: input)
                        toolNames.append(name)
                        // We don't return individual tool events from assistant messages
                        // because they're also sent as stream_events with more detail.
                        // But log them for the user.
                        if !inputStr.isEmpty {
                            texts.append("[\(name)] \(inputStr)")
                        }
                    }
                }
                if !texts.isEmpty {
                    return .text(texts.joined(separator: "\n"))
                }
                if !toolNames.isEmpty {
                    return .status("Claude is using: \(toolNames.joined(separator: ", "))")
                }
            }
            return nil

        case "result":
            let subtype = json["subtype"] as? String
            let resultText = json["result"] as? String ?? ""
            if subtype == "error" {
                let errMsg = json["error"] as? String ?? resultText
                return .error(errMsg)
            }
            return .result(text: resultText)

        case "stream_event":
            // Partial streaming — extract from the raw Anthropic API event
            guard let event = json["event"] as? [String: Any],
                  let eventType = event["type"] as? String else { return nil }

            switch eventType {
            case "content_block_start":
                if let block = event["content_block"] as? [String: Any] {
                    let blockType = block["type"] as? String
                    if blockType == "tool_use", let name = block["name"] as? String {
                        return .toolUse(name: name, input: "")
                    }
                    if blockType == "text" {
                        return .status("Claude is thinking...")
                    }
                }
            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any] {
                    let deltaType = delta["type"] as? String
                    if deltaType == "text_delta", let text = delta["text"] as? String {
                        return .text(text)
                    }
                    if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                        // Tool input being streamed — try to extract useful info
                        if partial.contains("file_path") || partial.contains("command") || partial.contains("pattern") {
                            return .status("...")
                        }
                    }
                }
            case "message_start":
                return .status("Claude is responding...")
            case "message_stop":
                return nil // Will be followed by assistant or result event
            default:
                break
            }
            return nil

        // Tool use summary events from verbose mode
        case "tool_use_summary":
            let toolName = json["tool_name"] as? String ?? "tool"
            let status = json["status"] as? String ?? ""
            if status == "started" {
                return .status("Running \(toolName)...")
            } else if status == "completed" {
                return .toolResult(name: toolName, output: "done")
            }
            return nil

        default:
            // Unknown event type — log as status if it has useful info
            return nil
        }
    }

    /// Format tool input into a human-readable summary.
    private static func formatToolInput(name: String, input: [String: Any]?) -> String {
        guard let input = input else { return "" }
        switch name {
        case "Read":
            return input["file_path"] as? String ?? ""
        case "Write":
            let path = input["file_path"] as? String ?? ""
            return path
        case "Edit":
            let path = input["file_path"] as? String ?? ""
            return path
        case "Bash":
            let cmd = input["command"] as? String ?? ""
            return String(cmd.prefix(120))
        case "Glob":
            return input["pattern"] as? String ?? ""
        case "Grep":
            return input["pattern"] as? String ?? ""
        default:
            // Generic: show first key=value
            if let first = input.first {
                return "\(first.key)=\(String(describing: first.value).prefix(80))"
            }
            return ""
        }
    }

    // MARK: - Legacy Run (--print mode)

    /// Streams stdout+stderr lines from `claude --print <todo.content>` run in `project.localPath`.
    func run(
        todo: StructuredTodo,
        project: Project,
        apiKey: String?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task.detached {
                guard let claudeURL = ClaudeCodeRunner.findCLI() else {
                    continuation.finish(throwing: ClaudeCodeError.notFound)
                    return
                }

                let process = Process()
                process.executableURL = claudeURL
                var args: [String] = []
                if let mcpConfigPath = MCPConfigManager.configPath() {
                    args += ["--mcp-config", mcpConfigPath]
                }
                args += ["--print", todo.content]
                process.arguments = args
                process.currentDirectoryURL = URL(fileURLWithPath: project.localPath)

                var env = ProcessInfo.processInfo.environment
                env.removeValue(forKey: "CLAUDECODE")
                env.removeValue(forKey: "CLAUDE_CODE_OAUTH_TOKEN")
                env.removeValue(forKey: "ANTHROPIC_API_KEY")
                if let key = apiKey, !key.isEmpty {
                    Self.setAuthEnv(key, into: &env)
                }
                process.environment = env

                let outPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = outPipe

                do {
                    try process.run()
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

                for try await line in outPipe.fileHandleForReading.bytes.lines {
                    continuation.yield(line)
                }

                process.waitUntilExit()
                let status = process.terminationStatus
                if status != 0 {
                    continuation.finish(throwing: ClaudeCodeError.exitCode(status))
                } else {
                    continuation.finish()
                }
            }
        }
    }

    /// Legacy: Streams stdout+stderr lines from `claude --print <prompt>`.
    func run(
        _ prompt: String,
        in project: Project,
        dangerouslySkipPermissions: Bool = false
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task.detached {
                guard let claudeURL = ClaudeCodeRunner.findCLI() else {
                    continuation.finish(throwing: ClaudeCodeError.notFound)
                    return
                }

                let process = Process()
                process.executableURL = claudeURL
                var args: [String] = []
                if let mcpConfigPath = MCPConfigManager.configPath() {
                    args += ["--mcp-config", mcpConfigPath]
                }
                args += ["--print", prompt]
                if dangerouslySkipPermissions {
                    args.append("--dangerously-skip-permissions")
                }
                process.arguments = args
                process.currentDirectoryURL = URL(fileURLWithPath: project.localPath)

                var env = ProcessInfo.processInfo.environment
                env.removeValue(forKey: "CLAUDECODE")
                env.removeValue(forKey: "CLAUDE_CODE_OAUTH_TOKEN")
                env.removeValue(forKey: "ANTHROPIC_API_KEY")
                let apiKeyVal = SettingsManager.shared.anthropicAPIKey
                if !apiKeyVal.isEmpty {
                    Self.setAuthEnv(apiKeyVal, into: &env)
                } else {
                    Log.warn(.taskExec, "Claude CLI: NO API key in settings")
                }
                process.environment = env

                let outPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = outPipe

                do {
                    try process.run()
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

                for try await line in outPipe.fileHandleForReading.bytes.lines {
                    continuation.yield(line)
                }

                process.waitUntilExit()
                let status = process.terminationStatus
                if status != 0 {
                    continuation.finish(throwing: ClaudeCodeError.exitCode(status))
                } else {
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Auth Helper

    /// Detects token type and sets the correct env var:
    /// - OAuth tokens (sk-ant-oat*) → CLAUDE_CODE_OAUTH_TOKEN
    /// - API keys (sk-ant-api*) → ANTHROPIC_API_KEY
    static func setAuthEnv(_ key: String, into env: inout [String: String]) {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
        if cleaned.hasPrefix("sk-ant-oat") {
            env["CLAUDE_CODE_OAUTH_TOKEN"] = cleaned
            Log.info(.taskExec, "Claude CLI: using OAuth token (len=\(cleaned.count))")
        } else {
            env["ANTHROPIC_API_KEY"] = cleaned
            Log.info(.taskExec, "Claude CLI: using API key (len=\(cleaned.count))")
        }
    }

    // MARK: - Open in Terminal

    func openInTerminal(prompt: String, in project: Project, dangerouslySkipPermissions: Bool = false) {
        guard let claudeURL = ClaudeCodeRunner.findCLI() else {
            Log.warn(.system, "Claude CLI not found — cannot open in Terminal")
            return
        }
        let claudeExec = claudeURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let safePrompt = prompt.replacingOccurrences(of: "'", with: "'\\''")
        let safePath = project.localPath.replacingOccurrences(of: "'", with: "'\\''")
        var mcpFlag = ""
        if let mcpPath = MCPConfigManager.configPath() {
            let safeMCP = mcpPath.replacingOccurrences(of: "'", with: "'\\''")
            mcpFlag = " --mcp-config '\(safeMCP)'"
        }
        let permFlag = dangerouslySkipPermissions ? " --dangerously-skip-permissions" : ""
        let fullCmd = "cd '\(safePath)' && '\(claudeExec)'\(mcpFlag)\(permFlag) '\(safePrompt)'"

        let scriptName = "autoclawd-\(UUID().uuidString.prefix(8)).sh"
        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(scriptName)
        let script = "#!/bin/bash\n\(fullCmd)\n"
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            Log.warn(.system, "Failed to write Terminal script: \(error)")
            return
        }

        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open(
            [scriptURL],
            withApplicationAt: terminalURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error = error {
                Log.warn(.system, "Failed to open Terminal: \(error)")
            }
        }
    }
}
