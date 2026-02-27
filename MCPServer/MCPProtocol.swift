import Foundation

// MARK: - Tool Definition Helpers

func makeToolDefinition(
    name: String,
    description: String,
    properties: [String: [String: Any]],
    required: [String] = []
) -> [String: Any] {
    [
        "name": name,
        "description": description,
        "inputSchema": [
            "type": "object",
            "properties": properties,
            "required": required
        ] as [String: Any]
    ]
}

// MARK: - Tool Result Helpers

func makeToolResult(text: String, isError: Bool = false) -> [String: Any] {
    var result: [String: Any] = [
        "content": [
            ["type": "text", "text": text] as [String: Any]
        ]
    ]
    if isError { result["isError"] = true }
    return result
}

// MARK: - JSON-RPC Response Helpers

func makeResult(id: Any?, result: Any) -> [String: Any] {
    var resp: [String: Any] = ["jsonrpc": "2.0", "result": result]
    if let id = id { resp["id"] = id }
    return resp
}

func makeError(id: Any?, code: Int, message: String) -> [String: Any] {
    var resp: [String: Any] = [
        "jsonrpc": "2.0",
        "error": ["code": code, "message": message] as [String: Any]
    ]
    if let id = id { resp["id"] = id }
    return resp
}

// MARK: - JSON Serialization

func jsonString(from object: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: []),
          let str = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return str
}
