import Foundation
import SwiftUI

enum PillMode: String, CaseIterable {
    case ambientIntelligence = "ambientIntelligence"
    case transcription       = "transcription"
    case aiSearch            = "aiSearch"
    case tasks               = "tasks"
    case code                = "code"

    var displayName: String {
        switch self {
        case .ambientIntelligence: return "Ambient"
        case .transcription:       return "Transcribe"
        case .aiSearch:            return "AI Search"
        case .tasks:               return "Tasks"
        case .code:                return "Code"
        }
    }

    var icon: String {
        switch self {
        case .ambientIntelligence: return "brain"
        case .transcription:       return "text.cursor"
        case .aiSearch:            return "magnifyingglass"
        case .tasks:               return "checklist"
        case .code:                return "chevron.left.forwardslash.chevron.right"
        }
    }

    var shortLabel: String {
        switch self {
        case .ambientIntelligence: return "[AMB]"
        case .transcription:       return "[TRS]"
        case .aiSearch:            return "[SRC]"
        case .tasks:               return "[TSK]"
        case .code:                return "[COD]"
        }
    }

    var color: Color {
        switch self {
        case .ambientIntelligence: return .green
        case .transcription:       return .accentColor
        case .aiSearch:            return .accentColor
        case .tasks:               return .orange
        case .code:                return .blue
        }
    }

    func next() -> PillMode {
        let all = PillMode.allCases
        let idx = all.firstIndex(of: self)!
        return all[(idx + 1) % all.count]
    }
}
