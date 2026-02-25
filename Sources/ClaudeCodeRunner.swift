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
                process.arguments = ["--print", todo.content]
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
}
