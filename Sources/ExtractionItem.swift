import Foundation

enum ExtractionType: String, Codable, CaseIterable {
    case fact, todo
}

enum ExtractionBucket: String, Codable, CaseIterable {
    case projects, people, plans, preferences, decisions, other
    var displayName: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .projects:    return "folder"
        case .people:      return "person.2"
        case .plans:       return "calendar"
        case .preferences: return "slider.horizontal.3"
        case .decisions:   return "checkmark.seal"
        case .other:       return "tag"
        }
    }
    static func parse(_ raw: String) -> ExtractionBucket {
        ExtractionBucket(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased()) ?? .other
    }
}

struct ExtractionItem: Identifiable, Equatable {
    let id: String
    let chunkIndex: Int
    let timestamp: Date
    let sourcePhrase: String
    let content: String
    let type: ExtractionType
    var bucket: ExtractionBucket
    let priority: String?
    let modelDecision: String
    var userOverride: String?
    var applied: Bool = false

    var effectiveState: String  { userOverride ?? modelDecision }
    var isAccepted: Bool        { effectiveState == "relevant" || effectiveState == "accepted" }
    var isDismissed: Bool       { effectiveState == "nonrelevant" || effectiveState == "dismissed" }
    var priorityLabel: String {
        switch priority {
        case "HIGH":   return "↑H"
        case "MEDIUM": return "↑M"
        case "LOW":    return "↑L"
        default:       return ""
        }
    }
}
