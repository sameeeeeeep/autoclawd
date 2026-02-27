import Foundation

final class ToolRegistry {
    let todoStore: MCPTodoStore
    let projectStore: MCPProjectStore
    let transcriptStore: MCPTranscriptStore
    let worldModel: MCPWorldModel

    init(todoStore: MCPTodoStore, projectStore: MCPProjectStore,
         transcriptStore: MCPTranscriptStore, worldModel: MCPWorldModel) {
        self.todoStore = todoStore
        self.projectStore = projectStore
        self.transcriptStore = transcriptStore
        self.worldModel = worldModel
    }

    // MARK: - tools/list

    func toolsList() -> [String: Any] {
        ["tools": [
            makeToolDefinition(
                name: "list_todos",
                description: "List all todos from AutoClawd. Optionally filter by project or status.",
                properties: [
                    "project_id": ["type": "string", "description": "Filter by project ID"],
                    "status": ["type": "string", "enum": ["pending", "executed", "all"],
                               "description": "Filter by execution status (default: all)"]
                ]
            ),
            makeToolDefinition(
                name: "create_todo",
                description: "Create a new todo in AutoClawd.",
                properties: [
                    "content": ["type": "string", "description": "The todo text"],
                    "priority": ["type": "string", "enum": ["HIGH", "MEDIUM", "LOW"],
                                 "description": "Priority level"],
                    "project_id": ["type": "string", "description": "Assign to a project by ID"]
                ],
                required: ["content"]
            ),
            makeToolDefinition(
                name: "update_todo",
                description: "Update an existing todo's content, priority, or project assignment.",
                properties: [
                    "id": ["type": "string", "description": "The todo ID to update"],
                    "content": ["type": "string", "description": "New todo text"],
                    "priority": ["type": "string", "enum": ["HIGH", "MEDIUM", "LOW"],
                                 "description": "New priority level"],
                    "project_id": ["type": "string", "description": "New project ID (null to unassign)"]
                ],
                required: ["id"]
            ),
            makeToolDefinition(
                name: "mark_todo_done",
                description: "Mark a todo as executed/completed with output.",
                properties: [
                    "id": ["type": "string", "description": "The todo ID to mark done"],
                    "output": ["type": "string", "description": "Execution output or summary"]
                ],
                required: ["id", "output"]
            ),
            makeToolDefinition(
                name: "delete_todo",
                description: "Delete a todo from AutoClawd.",
                properties: [
                    "id": ["type": "string", "description": "The todo ID to delete"]
                ],
                required: ["id"]
            ),
            makeToolDefinition(
                name: "read_world_model",
                description: "Read AutoClawd's world model — a knowledge base of facts about the user's life, projects, people, preferences, and decisions. Optionally read a project-specific world model.",
                properties: [
                    "project_id": ["type": "string",
                                   "description": "If provided, read the project-specific world model instead of the global one"]
                ]
            ),
            makeToolDefinition(
                name: "update_world_model",
                description: "Write to AutoClawd's world model. This replaces the entire content of the global or project-specific world model file.",
                properties: [
                    "content": ["type": "string", "description": "The new world model content (markdown)"],
                    "project_id": ["type": "string",
                                   "description": "If provided, update the project-specific world model"]
                ],
                required: ["content"]
            ),
            makeToolDefinition(
                name: "list_projects",
                description: "List all projects registered in AutoClawd with their names, paths, and tags.",
                properties: [:]
            ),
            makeToolDefinition(
                name: "search_transcripts",
                description: "Full-text search through AutoClawd's voice transcripts. Returns matching transcript snippets.",
                properties: [
                    "query": ["type": "string", "description": "Search query (FTS5 syntax supported)"],
                    "limit": ["type": "integer", "description": "Max results to return (default: 20)"]
                ],
                required: ["query"]
            )
        ]]
    }

    // MARK: - tools/call

    func callTool(name: String, arguments: [String: Any]) -> [String: Any] {
        switch name {
        case "list_todos":
            return ToolHandlers.listTodos(args: arguments, store: todoStore)
        case "create_todo":
            return ToolHandlers.createTodo(args: arguments, store: todoStore)
        case "update_todo":
            return ToolHandlers.updateTodo(args: arguments, store: todoStore)
        case "mark_todo_done":
            return ToolHandlers.markTodoDone(args: arguments, store: todoStore)
        case "delete_todo":
            return ToolHandlers.deleteTodo(args: arguments, store: todoStore)
        case "read_world_model":
            return ToolHandlers.readWorldModel(args: arguments, worldModel: worldModel)
        case "update_world_model":
            return ToolHandlers.updateWorldModel(args: arguments, worldModel: worldModel)
        case "list_projects":
            return ToolHandlers.listProjects(args: arguments, store: projectStore)
        case "search_transcripts":
            return ToolHandlers.searchTranscripts(args: arguments, store: transcriptStore)
        default:
            return makeToolResult(text: "Unknown tool: \(name)", isError: true)
        }
    }
}
