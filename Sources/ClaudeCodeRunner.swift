import AppKit
import Foundation

// MARK: - ClaudeCodeError

enum ClaudeCodeError: LocalizedError {
    case notFound
    case exitCode(Int32)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "claude CLI not found. Install via: npm install -g @anthropic-ai/claude-code"
        case .exitCode(let code):
            return "claude exited with code \(code)"
        }
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

    // MARK: - Run

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
                if let key = apiKey, !key.isEmpty {
                    env["ANTHROPIC_API_KEY"] = key
                }
                process.environment = env

                let outPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = outPipe  // merge stderr into same pipe

                do {
                    try process.run()
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

                // Read lines as they arrive
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

    /// Streams stdout+stderr lines from `claude --print <prompt>` run in `project.localPath`.
    /// Used by hot-word processing to execute arbitrary prompts directly.
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
                let apiKeyVal = SettingsManager.shared.anthropicAPIKey
                if !apiKeyVal.isEmpty {
                    env["ANTHROPIC_API_KEY"] = apiKeyVal
                }
                process.environment = env

                let outPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = outPipe  // merge stderr into same pipe

                do {
                    try process.run()
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

                // Read lines as they arrive
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

    // MARK: - Open in Terminal

    func openInTerminal(prompt: String, in project: Project, dangerouslySkipPermissions: Bool = false) {
        guard let claudeURL = ClaudeCodeRunner.findCLI() else {
            Log.warn(.system, "Claude CLI not found — cannot open in Terminal")
            return
        }
        let claudeExec = claudeURL.path.replacingOccurrences(of: "'", with: "'\\''")
        // Shell-safe: escape single quotes in prompt using the POSIX technique
        let safePrompt = prompt.replacingOccurrences(of: "'", with: "'\\''")
        let safePath = project.localPath.replacingOccurrences(of: "'", with: "'\\''")
        var mcpFlag = ""
        if let mcpPath = MCPConfigManager.configPath() {
            let safeMCP = mcpPath.replacingOccurrences(of: "'", with: "'\\''")
            mcpFlag = " --mcp-config '\(safeMCP)'"
        }
        let permFlag = dangerouslySkipPermissions ? " --dangerously-skip-permissions" : ""
        let fullCmd = "cd '\(safePath)' && '\(claudeExec)'\(mcpFlag)\(permFlag) '\(safePrompt)'"

        // Write to a uniquely-named temp script so concurrent calls don't collide
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