import Foundation
import SwiftUI

// MARK: - CallModeSession

/// Direct Anthropic API conversation session for Call Mode.
///
/// Bypasses Llama entirely — voice transcript → Claude directly.
/// Claude proactively calls screen/cursor/selection tools to see what the user is looking at.
///
/// Pipeline for call mode:
///   Mic → SFSpeech/Groq transcript → send() → Anthropic messages API
///         ↑ Claude calls tools ↓
///   ScreenGrabService.captureScreen / captureCursorContext / captureSelection
///         ↓ Claude responds
///   @Published messages → CallModeView
@MainActor
final class CallModeSession: ObservableObject {

    @Published var messages:      [CallMessage] = []
    @Published var isProcessing:  Bool          = false

    private var history: [[String: Any]] = []
    private let screenGrab = ScreenGrabService()
    private var transcriptProvider: (() -> String)?

    // MARK: - Configuration

    func configure(transcriptProvider: @escaping () -> String) {
        self.transcriptProvider = transcriptProvider
    }

    // MARK: - Send

    /// Send a user message (typically from voice transcript) to Claude.
    /// Claude may call screen tools before responding.
    func send(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let apiKey = SettingsManager.shared.anthropicAPIKey
        guard !apiKey.isEmpty else {
            messages.append(CallMessage(role: .error,
                                        text: "Anthropic API key not configured."))
            return
        }

        messages.append(CallMessage(role: .user, text: trimmed))
        history.append(["role": "user", "content": trimmed])

        isProcessing = true
        defer { isProcessing = false }

        do {
            let reply = try await runAgentLoop(apiKey: apiKey)
            if !reply.isEmpty {
                messages.append(CallMessage(role: .assistant, text: reply))
                history.append(["role": "assistant", "content": reply])
            }
        } catch {
            messages.append(CallMessage(role: .error, text: error.localizedDescription))
        }
    }

    func clearHistory() {
        messages.removeAll()
        history.removeAll()
    }

    /// Append a message from an external source (e.g. Claude Code via MCP autoclawd_set_canvas).
    func appendExternalMessage(_ text: String) {
        messages.append(CallMessage(role: .external, text: text))
    }

    // MARK: - Agent Loop

    /// Tool-use loop: request → if tool_use → execute → continue → until end_turn.
    private func runAgentLoop(apiKey: String) async throws -> String {
        while true {
            let body     = makeRequestBody()
            let response = try await callAnthropic(body: body, apiKey: apiKey)

            guard let stopReason = response["stop_reason"] as? String else {
                throw CallModeError.invalidResponse
            }

            let content = response["content"] as? [[String: Any]] ?? []

            if stopReason == "end_turn" {
                return content
                    .filter { $0["type"] as? String == "text" }
                    .compactMap { $0["text"] as? String }
                    .joined(separator: "\n")
            }

            if stopReason == "tool_use" {
                // Append Claude's tool-use turn to history
                history.append(["role": "assistant", "content": content])

                // Execute all tool calls in parallel, then collect results
                var results: [[String: Any]] = []
                for block in content where block["type"] as? String == "tool_use" {
                    guard let toolID   = block["id"]   as? String,
                          let toolName = block["name"] as? String
                    else { continue }

                    let args   = block["input"] as? [String: Any] ?? [:]
                    let output = await executeTool(name: toolName, args: args)

                    // Show tool use in messages for transparency
                    messages.append(CallMessage(
                        role: .tool,
                        text: "[\(toolName)]"
                    ))

                    results.append([
                        "type":        "tool_result",
                        "tool_use_id": toolID,
                        "content":     output
                    ])
                }

                history.append(["role": "user", "content": results])
                continue
            }

            // Unexpected stop reason — return whatever text we have
            return content
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
        }
    }

    // MARK: - Tool Execution

    private func executeTool(name: String, args: [String: Any]) async -> [[String: Any]] {
        switch name {

        case "get_screen":
            var region: CGRect?
            if let r = args["region"] as? [String: Any],
               let x = r["x"] as? CGFloat, let y = r["y"] as? CGFloat,
               let w = r["width"] as? CGFloat, let h = r["height"] as? CGFloat {
                region = CGRect(x: x, y: y, width: w, height: h)
            }
            let grab = await screenGrab.captureScreen(region: region)
            return imageBlocks(from: grab)

        case "get_cursor_context":
            let grab = await screenGrab.captureCursorContext()
            return imageBlocks(from: grab)

        case "get_selection":
            let sel = await screenGrab.captureSelection()
            if sel.selectedText.isEmpty && sel.contextImageJPEGData == nil {
                return [["type": "text", "text": "No text currently selected."]]
            }
            var blocks: [[String: Any]] = []
            if !sel.selectedText.isEmpty {
                blocks.append(["type": "text",
                               "text": "Selected text:\n\(sel.selectedText)"])
            }
            if let jpeg = sel.contextImageJPEGData {
                blocks.append(imageBlock(jpeg))
            }
            return blocks

        case "get_audio_transcript":
            let maxChars   = args["max_chars"] as? Int ?? 2_000
            let transcript = transcriptProvider?() ?? ""
            let trimmed    = transcript.count > maxChars
                ? String(transcript.suffix(maxChars))
                : transcript
            return [["type": "text",
                     "text": trimmed.isEmpty ? "No transcript available." : trimmed]]

        default:
            return [["type": "text", "text": "Unknown tool: \(name)"]]
        }
    }

    // MARK: - Content Block Helpers

    private func imageBlocks(from grab: ScreenGrab) -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        let textParts = [
            grab.metadata.isEmpty ? nil : grab.metadata,
            grab.ocrText.isEmpty  ? nil : "Screen text:\n\(grab.ocrText)"
        ].compactMap { $0 }
        if !textParts.isEmpty {
            blocks.append(["type": "text", "text": textParts.joined(separator: "\n\n")])
        }
        if let jpeg = grab.imageJPEGData {
            blocks.append(imageBlock(jpeg))
        }
        return blocks
    }

    private func imageBlock(_ jpeg: Data) -> [String: Any] {
        [
            "type": "image",
            "source": [
                "type":       "base64",
                "media_type": "image/jpeg",
                "data":       jpeg.base64EncodedString()
            ]
        ]
    }

    // MARK: - Anthropic API

    private func makeRequestBody() -> [String: Any] {
        [
            "model":      "claude-opus-4-6",
            "max_tokens": 4096,
            "system": """
                You are an AI assistant running inside AutoClawd with real-time access \
                to the user's screen and microphone. You can see their screen, read OCR text, \
                and grab screenshots. Always call get_screen at the start of a new topic to \
                orient yourself. Use get_cursor_context when the user says "this" or "here" \
                without specifying. Use get_selection whenever the user has highlighted text. \
                Be concise, direct, and action-oriented.
                """,
            "tools":    toolDefinitions(),
            "messages": history
        ]
    }

    private func toolDefinitions() -> [[String: Any]] {
        [
            [
                "name": "get_screen",
                "description": "Capture the screen with OCR text and a JPEG screenshot. Optionally crop to a region.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "region": [
                            "type": "object",
                            "properties": [
                                "x":      ["type": "number"],
                                "y":      ["type": "number"],
                                "width":  ["type": "number"],
                                "height": ["type": "number"]
                            ]
                        ]
                    ]
                ] as [String: Any]
            ],
            [
                "name": "get_cursor_context",
                "description": "Capture 600×400 region around the cursor with OCR. Use when user points at something.",
                "input_schema": ["type": "object", "properties": [:] as [String: Any]]
            ],
            [
                "name": "get_selection",
                "description": "Get selected text and screenshot of selection. Use when user highlights something.",
                "input_schema": ["type": "object", "properties": [:] as [String: Any]]
            ],
            [
                "name": "get_audio_transcript",
                "description": "Get recent spoken audio transcript from the user's microphone.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "max_chars": ["type": "number"]
                    ]
                ] as [String: Any]
            ]
        ]
    }

    private func callAnthropic(body: [String: Any], apiKey: String) async throws -> [String: Any] {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown API error"
            throw CallModeError.apiError(msg)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CallModeError.invalidResponse
        }
        return json
    }
}

// MARK: - Supporting Types

struct CallMessage: Identifiable {
    let id   = UUID()
    let role: Role
    let text: String

    enum Role { case user, assistant, tool, error, external }
}

enum CallModeError: Error, LocalizedError {
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid API response from Anthropic."
        case .apiError(let m): return m
        }
    }
}
