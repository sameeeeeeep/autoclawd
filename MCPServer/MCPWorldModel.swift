import Foundation

struct MCPWorldModel {
    let rootDir: URL

    func read(projectID: String?) -> String {
        let url: URL
        if let pid = projectID {
            url = rootDir.appendingPathComponent("world-model-\(pid).md")
        } else {
            url = rootDir.appendingPathComponent("world-model.md")
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func write(content: String, projectID: String?) {
        let url: URL
        if let pid = projectID {
            url = rootDir.appendingPathComponent("world-model-\(pid).md")
        } else {
            url = rootDir.appendingPathComponent("world-model.md")
        }
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
}
