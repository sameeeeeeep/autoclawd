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

    enum HaikuError: Error, LocalizedError {
        case cliNotFound
        case exitCode(Int32, String)

        var errorDescription: String? {
            switch self {
            case .cliNotFound:   return "claude CLI not found"
            case .exitCode(let c, let msg): return "claude exited \(c): \(msg)"
            }
        }
    }

    /// Sends `prompt` to claude-haiku via `--print` (non-interactive) and returns the response.
    /// Throws `HaikuError` if the CLI is missing or exits non-zero.
    func generate(prompt: String) async throws -> String {
        guard let claudeURL = ClaudeCodeRunner.findCLI() else {
            throw HaikuError.cliNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = claudeURL
            process.arguments = ["--print", "--model", Self.model, prompt]

            // Auth: mirror ClaudeCodeRunner — API key from settings takes priority;
            // if absent, claude CLI falls back to its own OAuth credentials (~/.config/claude/).
            var env = ProcessInfo.processInfo.environment
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
