import Foundation

final class TodoService: @unchecked Sendable {
    private let storage = FileStorageManager.shared
    private let queue = DispatchQueue(label: "com.autoclawd.todos", qos: .utility)

    func read() -> String {
        (try? String(contentsOf: storage.todosURL, encoding: .utf8)) ?? ""
    }

    func write(_ content: String) {
        queue.async { [self] in
            do {
                try content.write(to: storage.todosURL, atomically: true, encoding: .utf8)
                Log.info(.todo, "To-do list updated (\(content.count) chars)")
            } catch {
                Log.error(.todo, "Failed to write todos: \(error.localizedDescription)")
            }
        }
    }
}
