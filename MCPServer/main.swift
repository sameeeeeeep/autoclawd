import Foundation
import SQLite3

// Disable stdout buffering so Claude Code receives responses immediately
setbuf(stdout, nil)

// All data lives under ~/.autoclawd/
let rootDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".autoclawd")

// Ensure the directory exists
try? FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)

// Open stores once at startup
let todoStore = MCPTodoStore(url: rootDir.appendingPathComponent("structured_todos.db"))
let projectStore = MCPProjectStore(url: rootDir.appendingPathComponent("projects.db"))
let transcriptStore = MCPTranscriptStore(url: rootDir.appendingPathComponent("transcripts.db"))
let worldModel = MCPWorldModel(rootDir: rootDir)

let registry = ToolRegistry(
    todoStore: todoStore,
    projectStore: projectStore,
    transcriptStore: transcriptStore,
    worldModel: worldModel
)

let transport = JSONRPCTransport()

mcpLog("started, reading from stdin")

// Main loop: read newline-delimited JSON-RPC from stdin
while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty else { continue }
    guard let data = line.data(using: .utf8) else { continue }

    do {
        guard let request = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            continue
        }
        if let response = transport.handle(request: request, registry: registry) {
            let responseData = try JSONSerialization.data(withJSONObject: response)
            if let responseStr = String(data: responseData, encoding: .utf8) {
                print(responseStr)
            }
        }
    } catch {
        mcpLog("parse error: \(error)")
    }
}
