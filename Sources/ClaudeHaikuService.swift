// Sources/ClaudeHaikuService.swift
import Foundation

/// Lightweight inference via `claude --print --model claude-haiku-4-5-20251001`.
///
/// Uses the same claude CLI + OAuth/API-key auth as ClaudeCodeRunner — no extra credentials needed.
/// Designed for short, structured prompts (suggestion reasoning, classification) where you want
/// Claude-quality output without spinning up a full agentic session.
///
/// Not @MainActor — safe to call from any async context.
final class ClaudeHaikuService: @unchecked Sendable {

    static let model = "claude-haiku-4-5-20251001"

    /// Hard limit on how long a single Haiku call may take before the process is killed.
    static let timeoutSeconds: TimeInterval = 30

    enum HaikuError: Error, LocalizedError {
        case cliNotFound
        case timeout
        case exitCode(Int32, String)

        var errorDescription: String? {
            switch self {
            case .cliNotFound:              return "claude CLI not found"
            case .timeout:                  return "claude haiku timed out after \(Int(ClaudeHaikuService.timeoutSeconds))s"
            case .exitCode(let c, let msg): return "claude exited \(c): \(msg)"
            }
        }
    }

    /// Sends `prompt` to claude-haiku via `--print` (non-interactive) and returns the response.
    /// Throws `HaikuError` if the CLI is missing, exits non-zero, or exceeds `timeoutSeconds`.
    func generate(prompt: String) async throws -> String {
        guard let claudeURL = ClaudeCodeRunner.findCLI() else {
            throw HaikuError.cliNotFound
        }

        return try await withTimeout(seconds: Self.timeoutSeconds) {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                process.executableURL = claudeURL
                // --model before --print; prompt as final positional arg
                process.arguments = ["--model", Self.model, "--print", prompt]

                // Mirror ClaudeCodeRunner env setup:
                // 1. Strip CLAUDECODE so the nested-session guard doesn't fire when AutoClawd
                //    was itself launched from a Claude Code session (e.g. `make run` in dev).
                // 2. Strip CLAUDE_CODE_ENTRYPOINT for the same reason.
                // 3. Inject API key if configured; otherwise claude falls back to OAuth creds.
                var env = ProcessInfo.processInfo.environment
                env.removeValue(forKey: "CLAUDECODE")
                env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
                env.removeValue(forKey: "CLAUDE_CODE_OAUTH_TOKEN")
                let apiKey = SettingsManager.shared.anthropicAPIKey
                if !apiKey.isEmpty {
                    env["ANTHROPIC_API_KEY"] = apiKey
                }
                process.environment = env

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError  = errPipe

                process.terminationHandler = { proc in
                    let outData  = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let response = String(data: outData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    if proc.terminationStatus == 0 {
                        continuation.resume(returning: response)
                    } else {
                        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        let errMsg  = String(data: errData, encoding: .utf8)?.prefix(200).description ?? "unknown"
                        continuation.resume(throwing: HaikuError.exitCode(proc.terminationStatus, errMsg))
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Timeout Helper

    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw HaikuError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
