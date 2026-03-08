import Foundation
import Network

// MARK: - MCPServer

/// Embeds a lightweight HTTP MCP server into AutoClawd so any Claude Code session
/// can call screen-grab tools directly — without a separate process.
///
/// Configure Claude Code once (in ~/.claude/mcp.json or .mcp.json in project root):
/// ```json
/// {
///   "mcpServers": {
///     "autoclawd": {
///       "type": "http",
///       "url": "http://localhost:7892/mcp"
///     }
///   }
/// }
/// ```
///
/// Available tools:
///   autoclawd_get_screen          — full screen or region: OCR text + JPEG screenshot
///   autoclawd_get_cursor_context  — 600×400 crop around cursor: OCR + AX element
///   autoclawd_get_selection       — currently selected text + selection screenshot
///   autoclawd_get_audio_transcript— rolling mic transcript buffer
///
/// Transport: HTTP/1.1, JSON-RPC 2.0, single-response (no SSE needed for these tools).
final class MCPServer: @unchecked Sendable {

    static let shared = MCPServer()

    let port: UInt16 = 7892

    private var listener: NWListener?
    private var screenGrab: ScreenGrabService?
    /// Called on @MainActor — returns the current session transcript text.
    private var transcriptProvider: (@MainActor () -> String)?
    /// Called on @MainActor — true if Claude Code participant is paused; gates transcript.
    private var isPausedProvider: (@MainActor () -> Bool)?
    /// Called on @MainActor — pushes text to the call mode canvas.
    private var canvasWriter: (@MainActor (String) -> Void)?
    /// Fired on @MainActor when a Claude Code session calls `initialize`.
    private var onJoined: (@MainActor () -> Void)?
    /// Fired on @MainActor when no MCP activity for `leaveTimeoutSeconds`.
    private var onLeft: (@MainActor () -> Void)?
    /// Invite a plugin/tool as a call participant: (id, name, systemImage).
    private var onInviteParticipant: (@MainActor (String, String, String) -> Void)?
    /// Set a participant's state: (id, stateString).
    private var onSetParticipantState: (@MainActor (String, String) -> Void)?
    /// Append a feed message attributed to a participant: (id, name, text).
    private var onParticipantMessage: (@MainActor (String, String, String) -> Void)?
    /// Remove a participant from the call: (id).
    private var onRemoveParticipant: (@MainActor (String) -> Void)?

    /// Last time any MCP request was received from a Claude Code session.
    private var lastActivityDate: Date?
    private var leaveTimer: Timer?
    private let leaveTimeoutSeconds: TimeInterval = 60

    // MARK: - Lifecycle

    /// Start the server. Idempotent — safe to call multiple times.
    func start(screenGrab: ScreenGrabService,
               transcriptProvider: @escaping @MainActor () -> String,
               isPausedProvider: (@MainActor () -> Bool)? = nil,
               canvasWriter: (@MainActor (String) -> Void)? = nil,
               onJoined: (@MainActor () -> Void)? = nil,
               onLeft: (@MainActor () -> Void)? = nil,
               onInviteParticipant: (@MainActor (String, String, String) -> Void)? = nil,
               onSetParticipantState: (@MainActor (String, String) -> Void)? = nil,
               onParticipantMessage: (@MainActor (String, String, String) -> Void)? = nil,
               onRemoveParticipant: (@MainActor (String) -> Void)? = nil) {
        guard listener == nil else { return }
        self.screenGrab              = screenGrab
        self.transcriptProvider      = transcriptProvider
        self.isPausedProvider        = isPausedProvider
        self.canvasWriter            = canvasWriter
        self.onJoined                = onJoined
        self.onLeft                  = onLeft
        self.onInviteParticipant     = onInviteParticipant
        self.onSetParticipantState   = onSetParticipantState
        self.onParticipantMessage    = onParticipantMessage
        self.onRemoveParticipant     = onRemoveParticipant

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener?.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            listener?.stateUpdateHandler   = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    Log.info(.system, "MCPServer: ready — http://localhost:\(self.port)/mcp")
                case .failed(let err):
                    Log.warn(.system, "MCPServer: listener failed — \(err)")
                default:
                    break
                }
            }
            listener?.start(queue: .global(qos: .utility))
        } catch {
            Log.warn(.system, "MCPServer: could not bind port \(port) — \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        leaveTimer?.invalidate()
        leaveTimer = nil
    }

    // MARK: - Activity Tracking

    /// Called on every inbound MCP request so we can detect session disconnection via timeout.
    private func recordActivity() {
        lastActivityDate = Date()
        // Reset the leave timer each time activity is seen.
        leaveTimer?.invalidate()
        leaveTimer = Timer.scheduledTimer(withTimeInterval: leaveTimeoutSeconds,
                                         repeats: false) { [weak self] _ in
            self?.fireLeft()
        }
        RunLoop.main.add(leaveTimer!, forMode: .common)
    }

    private func fireLeft() {
        lastActivityDate = nil
        leaveTimer = nil
        guard let cb = onLeft else { return }
        Task { @MainActor in cb() }
    }

    // MARK: - Connection Handling

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        receiveHTTP(connection: connection, buffer: Data())
    }

    /// Accumulate received bytes until we have a complete HTTP request, then process it.
    private func receiveHTTP(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            if let err = error {
                Log.warn(.system, "MCPServer: receive error \(err)")
                return
            }
            var buf = buffer
            if let chunk { buf.append(chunk) }

            if let (method, path, body) = self.parseHTTPRequest(buf) {
                self.handleRequest(method: method, path: path, body: body, connection: connection)
            } else if !isComplete {
                self.receiveHTTP(connection: connection, buffer: buf)
            }
        }
    }

    // MARK: - HTTP Parsing

    /// Returns (method, path, body) once a complete HTTP/1.1 request is buffered.
    private func parseHTTPRequest(_ data: Data) -> (String, String, Data)? {
        // Headers end at \r\n\r\n
        let sep = Data([0x0d, 0x0a, 0x0d, 0x0a])
        guard let sepRange = data.range(of: sep) else { return nil }

        let headerData = data[data.startIndex..<sepRange.lowerBound]
        guard let headerStr = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        // Request line: METHOD /path HTTP/1.1
        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path   = String(parts[1])

        // Content-Length
        var contentLength = 0
        for line in lines.dropFirst() {
            let kv = line.split(separator: ":", maxSplits: 1)
            if kv.count == 2,
               kv[0].lowercased().trimmingCharacters(in: .whitespaces) == "content-length" {
                contentLength = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }

        let bodyStart = sepRange.upperBound
        let available = data.distance(from: bodyStart, to: data.endIndex)
        guard available >= contentLength else { return nil }  // wait for more data

        let bodyEnd = data.index(bodyStart, offsetBy: contentLength)
        return (method, path, Data(data[bodyStart..<bodyEnd]))
    }

    // MARK: - HTTP Response

    private func sendHTTP(_ body: Data, status: Int = 200, connection: NWConnection) {
        let statusText = status == 200 ? "OK" : "Error"
        let header = [
            "HTTP/1.1 \(status) \(statusText)",
            "Content-Type: application/json",
            "Content-Length: \(body.count)",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "Connection: close",
            "", ""
        ].joined(separator: "\r\n")

        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: - Request Routing

    private func handleRequest(method: String, path: String, body: Data, connection: NWConnection) {
        // CORS preflight
        if method == "OPTIONS" {
            sendHTTP(Data(), connection: connection)
            return
        }

        guard path == "/mcp" || path.hasPrefix("/mcp?") else {
            sendHTTP(rpcError(code: -32_600, message: "Not found"), status: 404, connection: connection)
            return
        }

        guard let rpc  = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let meth = rpc["method"] as? String
        else {
            sendHTTP(rpcError(code: -32_600, message: "Invalid JSON-RPC"), status: 400, connection: connection)
            return
        }

        let id     = rpc["id"] as? Int
        let params = rpc["params"] as? [String: Any] ?? [:]

        Task { [weak self] in
            guard let self else { return }
            self.recordActivity()
            let result   = await self.dispatch(method: meth, params: params)
            let response = self.rpcSuccess(id: id, result: result)
            self.sendHTTP(response, connection: connection)
        }
    }

    // MARK: - MCP Protocol Dispatch

    private func dispatch(method: String, params: [String: Any]) async -> Any {
        switch method {

        case "initialize":
            // Fire join callback — a Claude Code session just connected.
            if let cb = onJoined {
                Task { @MainActor in cb() }
            }
            return [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "autoclawd", "version": "1.0"]
            ] as [String: Any]

        case "notifications/initialized":
            return [:] as [String: Any]

        case "tools/list":
            return ["tools": toolDefinitions()]

        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            return await callTool(name: name, args: args)

        default:
            return ["error": "Unknown method: \(method)"] as [String: Any]
        }
    }

    // MARK: - Tool Definitions

    private func toolDefinitions() -> [[String: Any]] {
        [
            [
                "name": "autoclawd_get_screen",
                "description": """
                    Capture the current screen with Vision OCR text and a JPEG screenshot. \
                    Optionally crop to a pixel region (screen-space, top-left origin). \
                    Returns structured text for reading plus the raw image for visual inspection. \
                    Call this first to get overall screen context.
                    """,
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "region": [
                            "type": "object",
                            "description": "Pixel region to crop. Omit for full screen.",
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
                "name": "autoclawd_get_cursor_context",
                "description": """
                    Capture a 600×400 screenshot centred on the user's current cursor position, \
                    with OCR text and the UI element under the cursor. \
                    Use this when the user points at something on screen without naming it.
                    """,
                "inputSchema": ["type": "object", "properties": [:] as [String: Any]]
            ],
            [
                "name": "autoclawd_get_selection",
                "description": """
                    Get the user's currently highlighted/selected text and a screenshot \
                    of that selection region. Use this when the user selects code, \
                    an error message, a file path, or any text before speaking.
                    """,
                "inputSchema": ["type": "object", "properties": [:] as [String: Any]]
            ],
            [
                "name": "autoclawd_get_audio_transcript",
                "description": """
                    Get the recent spoken audio transcript from the user's microphone session. \
                    Useful to review what was said in the last few minutes without the user \
                    having to repeat themselves.
                    """,
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "max_chars": [
                            "type": "number",
                            "description": "Maximum characters to return (default 2000, most-recent)."
                        ]
                    ]
                ] as [String: Any]
            ],
            [
                "name": "autoclawd_set_canvas",
                "description": """
                    Push a text message to the AutoClawd widget canvas so the user can see it \
                    on the floating pill. Use this to announce your presence ("Claude Code joined \
                    the call"), stream responses, or display status updates directly on the widget.
                    """,
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "text": [
                            "type": "string",
                            "description": "The message to display on the call mode canvas."
                        ]
                    ],
                    "required": ["text"]
                ] as [String: Any]
            ],
        ]
    }

    // NOTE: Participant tile tools (invite/set_state/send_message/remove) are intentionally
    // NOT exposed via tools/list. Tile management is UI-driven (user taps Invite) or will
    // be inferred from Claude Code's existing tool-call stream — never by making Claude Code
    // call extra MCP tools that burn tokens on pure UI bookkeeping.

    // MARK: - Tool Execution

    private func callTool(name: String, args: [String: Any]) async -> [String: Any] {
        var content: [[String: Any]] = []

        switch name {

        case "autoclawd_get_screen":
            var region: CGRect?
            if let r = args["region"] as? [String: Any],
               let x = r["x"] as? CGFloat, let y = r["y"] as? CGFloat,
               let w = r["width"] as? CGFloat, let h = r["height"] as? CGFloat {
                region = CGRect(x: x, y: y, width: w, height: h)
            }
            let grab = await screenGrab?.captureScreen(region: region)
                ?? ScreenGrab(ocrText: "", metadata: "Screen service unavailable",
                              imageJPEGData: nil, capturedAt: Date())
            content = screenGrabBlocks(grab)

        case "autoclawd_get_cursor_context":
            let grab = await screenGrab?.captureCursorContext()
                ?? ScreenGrab(ocrText: "", metadata: "Screen service unavailable",
                              imageJPEGData: nil, capturedAt: Date())
            content = screenGrabBlocks(grab)

        case "autoclawd_get_selection":
            let sel = await screenGrab?.captureSelection()
                ?? SelectionGrab(selectedText: "", contextImageJPEGData: nil, capturedAt: Date())
            if sel.selectedText.isEmpty && sel.contextImageJPEGData == nil {
                content = [["type": "text", "text": "No text currently selected."]]
            } else {
                if !sel.selectedText.isEmpty {
                    content.append(["type": "text",
                                    "text": "Selected text:\n\(sel.selectedText)"])
                }
                if let jpeg = sel.contextImageJPEGData {
                    content.append(["type": "image",
                                    "data": jpeg.base64EncodedString(),
                                    "mimeType": "image/jpeg"])
                }
            }

        case "autoclawd_get_audio_transcript":
            let maxChars = args["max_chars"] as? Int ?? 2_000
            let provider  = transcriptProvider
            let paused    = isPausedProvider
            let (transcript, isPaused) = await MainActor.run {
                (provider?() ?? "", paused?() ?? false)
            }
            if isPaused {
                content = [["type": "text",
                            "text": "Transcript paused — user and AutoClawd are planning. Stand by."]]
            } else {
                let trimmed = transcript.count > maxChars
                    ? String(transcript.suffix(maxChars))
                    : transcript
                content = [["type": "text",
                            "text": trimmed.isEmpty ? "No transcript available." : trimmed]]
            }

        case "autoclawd_set_canvas":
            let text = args["text"] as? String ?? ""
            if !text.isEmpty, let writer = canvasWriter {
                let w = writer
                Task { @MainActor in w(text) }
                content = [["type": "text", "text": "Canvas updated."]]
            } else {
                content = [["type": "text", "text": "No text provided or canvas unavailable."]]
            }

        case "autoclawd_invite_participant":
            let id    = args["id"]           as? String ?? ""
            let name  = args["name"]         as? String ?? ""
            let icon  = args["system_image"] as? String ?? "cable.connector"
            if !id.isEmpty, let cb = onInviteParticipant {
                Task { @MainActor in cb(id, name, icon) }
                content = [["type": "text", "text": "\(name) joined the call."]]
            } else {
                content = [["type": "text", "text": "Could not invite participant."]]
            }

        case "autoclawd_set_participant_state":
            let id        = args["id"]    as? String ?? ""
            let stateStr  = args["state"] as? String ?? "idle"
            if !id.isEmpty, let cb = onSetParticipantState {
                Task { @MainActor in cb(id, stateStr) }
                content = [["type": "text", "text": "State updated."]]
            } else {
                content = [["type": "text", "text": "Could not update participant state."]]
            }

        case "autoclawd_send_participant_message":
            let id   = args["id"]   as? String ?? ""
            let name = args["name"] as? String ?? ""
            let text = args["text"] as? String ?? ""
            if !id.isEmpty, !text.isEmpty, let cb = onParticipantMessage {
                Task { @MainActor in cb(id, name, text) }
                content = [["type": "text", "text": "Message posted."]]
            } else {
                content = [["type": "text", "text": "Could not post participant message."]]
            }

        case "autoclawd_remove_participant":
            let id = args["id"] as? String ?? ""
            if !id.isEmpty, let cb = onRemoveParticipant {
                Task { @MainActor in cb(id) }
                content = [["type": "text", "text": "Participant removed."]]
            } else {
                content = [["type": "text", "text": "Could not remove participant."]]
            }

        default:
            content = [["type": "text", "text": "Unknown tool: \(name)"]]
        }

        return ["content": content]
    }

    /// Build MCP content blocks from a ScreenGrab (text + optional image).
    private func screenGrabBlocks(_ grab: ScreenGrab) -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        let textParts = [
            grab.metadata.isEmpty ? nil : grab.metadata,
            grab.ocrText.isEmpty  ? nil : "Screen text:\n\(grab.ocrText)"
        ].compactMap { $0 }
        if !textParts.isEmpty {
            blocks.append(["type": "text", "text": textParts.joined(separator: "\n\n")])
        }
        if let jpeg = grab.imageJPEGData {
            blocks.append(["type": "image",
                           "data": jpeg.base64EncodedString(),
                           "mimeType": "image/jpeg"])
        }
        return blocks
    }

    // MARK: - JSON-RPC Helpers

    private func rpcSuccess(id: Int?, result: Any) -> Data {
        var obj: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { obj["id"] = id }
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    private func rpcError(code: Int, message: String) -> Data {
        let obj: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message]
        ]
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }
}
