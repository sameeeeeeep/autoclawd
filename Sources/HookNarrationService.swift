import Foundation

// MARK: - HookEvent

/// A parsed Claude Code hook event (PostToolUse, Stop, PreToolUse, etc.).
struct HookEvent {
    let eventName:    String             // "PostToolUse", "Stop", "PreToolUse", …
    let toolName:     String?
    let toolInput:    [String: Any]?
    let toolResponse: [String: Any]?
    let sessionID:    String?
    let rawJSON:      [String: Any]

    /// True when the hook signals the session has finished.
    var isStop: Bool { eventName == "Stop" }

    /// True when the hook signals a tool is about to run (pre-tool).
    var isPreTool: Bool { eventName == "PreToolUse" }
}

// MARK: - HookNarrationService

/// Translates raw Claude Code hook events into one-sentence human-readable narratives.
///
/// Pipeline:
///   1. Parse the raw JSON from `/hook` into a `HookEvent`.
///   2. `narrate(_:)` builds a compact summary string.
///   3. If Ollama is reachable, sends a short prompt to Llama and returns its response.
///   4. If Ollama is unavailable or slow, falls back to the template summary.
///
/// The narrated sentence is then shown in the call-room feed attributed to the
/// Claude Code participant tile — turning the call view into a live running
/// commentary of what Claude Code is doing.
final class HookNarrationService: @unchecked Sendable {

    private let ollama = OllamaService()

    // MARK: - Parse

    /// Parse raw hook JSON into a HookEvent.
    static func parse(_ json: [String: Any]) -> HookEvent {
        HookEvent(
            eventName:    json["hook_event_name"] as? String
                       ?? json["type"]            as? String
                       ?? "Unknown",
            toolName:     json["tool_name"]   as? String,
            toolInput:    json["tool_input"]  as? [String: Any],
            toolResponse: json["tool_response"] as? [String: Any],
            sessionID:    json["session_id"]  as? String,
            rawJSON:      json
        )
    }

    // MARK: - Narrate

    /// Returns a short, natural-language sentence describing what just happened.
    /// Uses Llama if available; falls back to a template description otherwise.
    func narrate(_ event: HookEvent) async -> String {
        // Stop events don't need an LLM call
        if event.isStop {
            return "Claw'd finished the task."
        }

        let summary = templateSummary(event)

        do {
            let prompt = """
                You are a narrator watching an AI coding assistant named "Claw'd" work. \
                In one short, casual sentence (10–15 words max), narrate what it just did. \
                Be specific. Never start with "The AI" — always use "Claw'd". \
                Don't add quotes around the sentence.

                Event: \(summary)

                Narration:
                """
            var narration = try await ollama.generate(prompt: prompt, numPredict: 60)
            // Strip any trailing artefacts that Llama sometimes adds
            narration = narration
                .components(separatedBy: "\n").first ?? narration
            narration = narration
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return narration.isEmpty ? summary : narration
        } catch {
            // Ollama not running — use template
            return summary
        }
    }

    // MARK: - Template Fallback

    private func templateSummary(_ event: HookEvent) -> String {
        guard let tool = event.toolName else {
            return "Working…"
        }
        let input = event.toolInput ?? [:]

        switch tool {

        case "Read":
            if let path = input["file_path"] as? String {
                return "Reading \(fileName(path))"
            }
            return "Reading a file"

        case "Write":
            if let path = input["file_path"] as? String {
                return "Writing \(fileName(path))"
            }
            return "Writing a file"

        case "Edit":
            if let path = input["file_path"] as? String {
                return "Editing \(fileName(path))"
            }
            return "Editing a file"

        case "MultiEdit":
            if let path = input["file_path"] as? String {
                return "Multi-editing \(fileName(path))"
            }
            return "Applying multiple edits"

        case "Bash":
            if let cmd = input["command"] as? String {
                let short = String(cmd.prefix(50))
                return "Running: \(short)\(cmd.count > 50 ? "…" : "")"
            }
            return "Running a shell command"

        case "Glob":
            if let pattern = input["pattern"] as? String {
                return "Searching for files matching '\(pattern)'"
            }
            return "Searching files"

        case "Grep":
            if let pattern = input["pattern"] as? String {
                return "Searching code for '\(String(pattern.prefix(40)))'"
            }
            return "Searching in files"

        case "Task":
            if let desc = input["description"] as? String {
                return "Spawning sub-agent: \(String(desc.prefix(40)))"
            }
            return "Launching a sub-agent"

        case "WebFetch":
            if let urlStr = input["url"] as? String,
               let host = URL(string: urlStr)?.host {
                return "Fetching \(host)"
            }
            return "Fetching a web page"

        case "WebSearch":
            if let query = input["query"] as? String {
                return "Searching the web for '\(String(query.prefix(40)))'"
            }
            return "Searching the web"

        case "TodoWrite":
            return "Updating the task list"

        case "NotebookEdit":
            return "Editing a notebook cell"

        default:
            return "Using \(tool)"
        }
    }

    private func fileName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}
