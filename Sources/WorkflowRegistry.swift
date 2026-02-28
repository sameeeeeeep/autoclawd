import Foundation

// MARK: - Workflow

/// Defines a tool chain for executing tasks.
struct Workflow: Identifiable {
    let id: String
    let name: String
    let steps: [String]
    let requiredConnections: [String]
}

// MARK: - WorkflowRegistry

/// Registry of available workflows for task execution.
final class WorkflowRegistry {
    static let shared = WorkflowRegistry()

    private let workflows: [String: Workflow]

    private init() {
        let list: [Workflow] = [
            Workflow(
                id: "autoclawd-claude-code",
                name: "AutoClawd \u{2192} Claude Code CLI",
                steps: [
                    "AutoClawd captures requirement",
                    "Prompt dispatched to Claude Code CLI",
                    "Claude Code executes in project directory",
                    "Results logged back to AutoClawd",
                ],
                requiredConnections: ["claude-cli"]
            ),
            Workflow(
                id: "autoclawd-freepik",
                name: "AutoClawd \u{2192} Freepik (Gemini \u{2192} Sora)",
                steps: [
                    "AutoClawd captures creative brief",
                    "Gemini generates first and last frame images",
                    "Sora generates video from frame pair",
                    "Video delivered to project assets",
                ],
                requiredConnections: ["freepik-api"]
            ),
            Workflow(
                id: "autoclawd-claude-code-linear",
                name: "AutoClawd \u{2192} Claude Code \u{2192} Linear",
                steps: [
                    "AutoClawd captures project management task",
                    "Prompt dispatched to Claude Code CLI",
                    "Claude Code prepares Linear API calls",
                    "Linear tasks updated via API",
                ],
                requiredConnections: ["claude-cli", "linear-api"]
            ),
            Workflow(
                id: "autoclawd-claude-code-meta",
                name: "AutoClawd \u{2192} Claude Code \u{2192} Meta MCP",
                steps: [
                    "AutoClawd captures campaign requirement",
                    "Prompt dispatched to Claude Code CLI",
                    "Claude Code interfaces with Meta MCP server",
                    "Campaign activated on Meta platforms",
                ],
                requiredConnections: ["claude-cli", "meta-mcp"]
            ),
        ]

        var map: [String: Workflow] = [:]
        for w in list { map[w.id] = w }
        workflows = map
    }

    func workflow(for id: String) -> Workflow? {
        workflows[id]
    }

    func allWorkflows() -> [Workflow] {
        Array(workflows.values).sorted { $0.id < $1.id }
    }

    /// Returns the name of the first missing connection, or nil if all are present.
    func checkConnections(for workflow: Workflow) -> String? {
        for conn in workflow.requiredConnections {
            if !isConnectionAvailable(conn) {
                return conn
            }
        }
        return nil
    }

    private func isConnectionAvailable(_ connection: String) -> Bool {
        switch connection {
        case "claude-cli":
            // Check if claude CLI is available
            return FileManager.default.isExecutableFile(atPath: "/usr/local/bin/claude")
                || FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/claude")
                || commandExists("claude")
        default:
            // Other connections not yet implemented
            return false
        }
    }

    private func commandExists(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
