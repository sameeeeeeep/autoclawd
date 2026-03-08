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

// MARK: - ToolParticipant

/// A tool (MCP server) that used as a participant in the call room feed.
struct ToolParticipant {
    let id:          String   // e.g. "pencil"
    let name:        String   // e.g. "Pencil"
    let systemImage: String   // SF symbol
}

// MARK: - NarrationBundle

/// Rich narration package returned for each hook event.
/// Contains everything needed to post a multi-message "conversation" in the call feed.
struct NarrationBundle {
    /// What Claw'd says (real, solid-border message).
    let narration: String
    /// The tool participant derived from the MCP tool name (nil for built-in tools).
    let toolParticipant: ToolParticipant?
    /// Short summary of the tool's response text (optional).
    let toolResponseText: String?
    /// Image bytes extracted from the tool response (e.g. Pencil screenshot).
    let imageData: Data?
    /// AutoClawd's generated reaction — rendered as a dashed/faint generated message.
    let autoClawdReaction: String?
}

// MARK: - HookNarrationService

/// Translates raw Claude Code hook events into NarrationBundles for the call-room feed.
///
/// Pipeline:
///   1. Parse the raw JSON from `/hook` into a `HookEvent`.
///   2. Extract tool participant (for MCP tools like `mcp__pencil__*`).
///   3. Extract image data from the tool response if present.
///   4. `narrate(_:)` calls Ollama Llama for a short narration; falls back to template.
///   5. Optionally generates an AutoClawd reaction via a second Ollama call.
///
/// The bundle is then used by AppDelegate to auto-join tool participants and post
/// a two-sided conversation in the feed (Claw'd speaks, tool responds, AutoClawd reacts).
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

    /// Returns a NarrationBundle describing what just happened.
    func narrate(_ event: HookEvent) async -> NarrationBundle {
        if event.isStop {
            return NarrationBundle(
                narration: "Claw'd finished the task.",
                toolParticipant: nil,
                toolResponseText: nil,
                imageData: nil,
                autoClawdReaction: nil
            )
        }

        let tp        = HookNarrationService.toolParticipant(from: event.toolName)
        let imageData = HookNarrationService.extractImageData(from: event.toolResponse)
        let summary   = templateSummary(event)

        // Ask Llama for a casual narration sentence
        var narration = summary
        do {
            let prompt = """
                You are a narrator watching an AI coding assistant named "Claw'd" work. \
                In one short, casual sentence (10–15 words max), narrate what it just did. \
                Be specific. Never start with "The AI" — always use "Claw'd". \
                Don't add quotes around the sentence.

                Event: \(summary)

                Narration:
                """
            var llm = try await ollama.generate(prompt: prompt, numPredict: 60)
            llm = llm.components(separatedBy: "\n").first ?? llm
            llm = llm
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !llm.isEmpty { narration = llm }
        } catch {}

        // Generate AutoClawd reaction for interesting MCP events or image results
        var reaction: String? = nil
        if tp != nil || imageData != nil {
            reaction = await generateAutoClawdReaction(for: narration, hasImage: imageData != nil)
        }

        return NarrationBundle(
            narration:         narration,
            toolParticipant:   tp,
            toolResponseText:  nil,
            imageData:         imageData,
            autoClawdReaction: reaction
        )
    }

    // MARK: - Tool Participant Extraction

    /// Parses `mcp__server__tool` tool names and returns a ToolParticipant.
    static func toolParticipant(from toolName: String?) -> ToolParticipant? {
        guard let name = toolName, name.hasPrefix("mcp__") else { return nil }
        let parts = name.components(separatedBy: "__")
        guard parts.count >= 2 else { return nil }
        let serverID = parts[1]
        return ToolParticipant(
            id:          serverID,
            name:        serverID.capitalized,
            systemImage: systemImageForServer(serverID)
        )
    }

    private static func systemImageForServer(_ server: String) -> String {
        switch server {
        case "pencil":        return "paintpalette"
        case "figma":         return "rectangle.3.group"
        case "github":        return "cat"
        case "linear":        return "square.and.pencil"
        case "notion":        return "doc.text"
        case "googlesheets":  return "tablecells"
        default:              return "cable.connector"
        }
    }

    // MARK: - Image Extraction

    /// Extracts raw JPEG/PNG bytes from a tool_response JSON payload.
    /// Handles several content formats used by MCP tools.
    static func extractImageData(from toolResponse: [String: Any]?) -> Data? {
        guard let resp = toolResponse else { return nil }

        // Pattern 1: {"type": "image", "data": "base64..."} (direct)
        if resp["type"] as? String == "image",
           let dataStr = resp["data"] as? String,
           let d = Data(base64Encoded: dataStr) {
            return d
        }

        // Pattern 2: {"content": [{"type": "image", "data": "..."}]}
        if let content = resp["content"] as? [[String: Any]] {
            for item in content {
                if item["type"] as? String == "image" {
                    if let dataStr = item["data"] as? String,
                       let d = Data(base64Encoded: dataStr) { return d }
                    if let source = item["source"] as? [String: Any],
                       let dataStr = source["data"] as? String,
                       let d = Data(base64Encoded: dataStr) { return d }
                }
            }
        }

        // Pattern 3: {"result": [{"type": "image", "source": {"data": "..."}}]}
        if let result = resp["result"] as? [[String: Any]] {
            for item in result {
                if item["type"] as? String == "image",
                   let source = item["source"] as? [String: Any],
                   let dataStr = source["data"] as? String,
                   let d = Data(base64Encoded: dataStr) { return d }
            }
        }

        return nil
    }

    // MARK: - AutoClawd Reaction

    private func generateAutoClawdReaction(for narration: String, hasImage: Bool) async -> String? {
        let imageHint = hasImage ? " A screenshot or image was returned." : ""
        let prompt = """
            You are AutoClawd, an AI project manager watching Claw'd (your coding AI) work.
            In one casual, short sentence (8–12 words), react to what just happened.\(imageHint)
            Be observant — sometimes curious, sometimes encouraging, sometimes dry.
            Never start with "I". Don't add quotes.

            What happened: \(narration)

            Your reaction:
            """
        do {
            var reaction = try await ollama.generate(prompt: prompt, numPredict: 40)
            reaction = reaction.components(separatedBy: "\n").first ?? reaction
            reaction = reaction
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return reaction.isEmpty ? nil : reaction
        } catch {
            return nil
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
            // MCP tools: mcp__server__action -> "Using Pencil: batch_design"
            if tool.hasPrefix("mcp__") {
                let parts = tool.components(separatedBy: "__")
                if parts.count >= 3 {
                    return "Using \(parts[1].capitalized): \(parts[2...].joined(separator: "_"))"
                }
            }
            return "Using \(tool)"
        }
    }

    private func fileName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}
