import Foundation

enum ToolHandlers {

    // MARK: - Todos

    static func listTodos(args: [String: Any], store: MCPTodoStore) -> [String: Any] {
        let projectID = args["project_id"] as? String
        let status = args["status"] as? String
        let todos = store.all(projectID: projectID, status: status)
        let json = jsonString(from: todos)
        return makeToolResult(text: json)
    }

    static func createTodo(args: [String: Any], store: MCPTodoStore) -> [String: Any] {
        guard let content = args["content"] as? String, !content.isEmpty else {
            return makeToolResult(text: "Error: 'content' is required", isError: true)
        }
        let priority = args["priority"] as? String
        let projectID = args["project_id"] as? String
        let todo = store.insert(content: content, priority: priority, projectID: projectID)
        let json = jsonString(from: todo)
        return makeToolResult(text: json)
    }

    static func updateTodo(args: [String: Any], store: MCPTodoStore) -> [String: Any] {
        guard let id = args["id"] as? String, !id.isEmpty else {
            return makeToolResult(text: "Error: 'id' is required", isError: true)
        }
        if let content = args["content"] as? String {
            store.updateContent(id: id, content: content)
        }
        if let priority = args["priority"] as? String {
            store.updatePriority(id: id, priority: priority)
        }
        if args.keys.contains("project_id") {
            let projectID = args["project_id"] as? String
            store.setProject(id: id, projectID: projectID)
        }
        return makeToolResult(text: "Updated todo \(id)")
    }

    static func markTodoDone(args: [String: Any], store: MCPTodoStore) -> [String: Any] {
        guard let id = args["id"] as? String, !id.isEmpty else {
            return makeToolResult(text: "Error: 'id' is required", isError: true)
        }
        let output = args["output"] as? String ?? ""
        store.markExecuted(id: id, output: output)
        return makeToolResult(text: "Marked todo \(id) as done")
    }

    static func deleteTodo(args: [String: Any], store: MCPTodoStore) -> [String: Any] {
        guard let id = args["id"] as? String, !id.isEmpty else {
            return makeToolResult(text: "Error: 'id' is required", isError: true)
        }
        store.delete(id: id)
        return makeToolResult(text: "Deleted todo \(id)")
    }

    // MARK: - World Model

    static func readWorldModel(args: [String: Any], worldModel: MCPWorldModel) -> [String: Any] {
        let projectID = args["project_id"] as? String
        let content = worldModel.read(projectID: projectID)
        if content.isEmpty {
            return makeToolResult(text: "(empty — no world model content yet)")
        }
        return makeToolResult(text: content)
    }

    static func updateWorldModel(args: [String: Any], worldModel: MCPWorldModel) -> [String: Any] {
        guard let content = args["content"] as? String else {
            return makeToolResult(text: "Error: 'content' is required", isError: true)
        }
        let projectID = args["project_id"] as? String
        worldModel.write(content: content, projectID: projectID)
        let scope = projectID != nil ? "project \(projectID!)" : "global"
        return makeToolResult(text: "Updated \(scope) world model (\(content.count) chars)")
    }

    // MARK: - Projects

    static func listProjects(args: [String: Any], store: MCPProjectStore) -> [String: Any] {
        let projects = store.all()
        let json = jsonString(from: projects)
        return makeToolResult(text: json)
    }

    // MARK: - Transcripts

    static func searchTranscripts(args: [String: Any], store: MCPTranscriptStore) -> [String: Any] {
        guard let query = args["query"] as? String, !query.isEmpty else {
            return makeToolResult(text: "Error: 'query' is required", isError: true)
        }
        let limit = (args["limit"] as? Int) ?? 20
        let results = store.search(query: query, limit: limit)
        if results.isEmpty {
            return makeToolResult(text: "No transcripts matching '\(query)'")
        }
        let json = jsonString(from: results)
        return makeToolResult(text: json)
    }
}
