// Sources/HotWordConfig.swift
import Foundation

enum HotWordAction: String, Codable, CaseIterable {
    case executeImmediately = "executeImmediately"
    case addTodo = "addTodo"
    case addWorldModelInfo = "addWorldModelInfo"
    case logOnly = "logOnly"

    var displayName: String {
        switch self {
        case .executeImmediately: return "Execute Immediately"
        case .addTodo:            return "Add to Project Todos"
        case .addWorldModelInfo:  return "Add to Project World Model"
        case .logOnly:            return "Log Only"
        }
    }
}

struct HotWordConfig: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var keyword: String          // e.g. "p0", "p1", "info"
    var action: HotWordAction
    var label: String            // e.g. "Critical Execute"
    var skipPermissions: Bool    // only relevant for executeImmediately

    static var defaults: [HotWordConfig] {
        [
            HotWordConfig(keyword: "p0", action: .executeImmediately, label: "Critical Execute", skipPermissions: true),
            HotWordConfig(keyword: "p1", action: .addTodo, label: "Add Todo", skipPermissions: false),
            HotWordConfig(keyword: "info", action: .addWorldModelInfo, label: "Add Info", skipPermissions: false),
        ]
    }
}
