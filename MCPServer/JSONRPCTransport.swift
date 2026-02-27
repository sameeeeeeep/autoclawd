import Foundation

struct JSONRPCTransport {

    func handle(request: [String: Any], registry: ToolRegistry) -> [String: Any]? {
        let method = request["method"] as? String ?? ""
        let id = request["id"]  // can be Int, String, or absent
        let params = request["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            return makeResult(id: id, result: initializeResponse())

        case "notifications/initialized":
            // Notification — no response required
            return nil

        case "tools/list":
            return makeResult(id: id, result: registry.toolsList())

        case "tools/call":
            let toolName = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let result = registry.callTool(name: toolName, arguments: arguments)
            return makeResult(id: id, result: result)

        case "ping":
            return makeResult(id: id, result: [:] as [String: Any])

        default:
            // For unknown methods, only respond if there's an id (i.e., it's a request, not a notification)
            if id != nil {
                return makeError(id: id, code: -32601, message: "Method not found: \(method)")
            }
            return nil
        }
    }

    private func initializeResponse() -> [String: Any] {
        [
            "protocolVersion": "2024-11-05",
            "capabilities": [
                "tools": [:] as [String: Any]
            ] as [String: Any],
            "serverInfo": [
                "name": "autoclawd",
                "version": "0.1.0"
            ] as [String: Any]
        ]
    }
}
