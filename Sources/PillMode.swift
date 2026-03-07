import Foundation
import SwiftUI

enum PillMode: String, CaseIterable {
    case ambientIntelligence = "ambientIntelligence"  // Tasks mode: text → clean → extract → execute
    case transcription       = "transcription"
    case aiSearch            = "aiSearch"
    case meeting             = "meeting"              // Meeting notes: accumulate → analyse at end

    var displayName: String {
        switch self {
        case .ambientIntelligence: return "Tasks"
        case .transcription:       return "Transcribe"
        case .aiSearch:            return "AI Search"
        case .meeting:             return "Meeting"
        }
    }

    var icon: String {
        switch self {
        case .ambientIntelligence: return "checklist"
        case .transcription:       return "text.cursor"
        case .aiSearch:            return "magnifyingglass"
        case .meeting:             return "person.2.wave.2"
        }
    }

    var shortLabel: String {
        switch self {
        case .ambientIntelligence: return "[TSK]"
        case .transcription:       return "[TRS]"
        case .aiSearch:            return "[SRC]"
        case .meeting:             return "[MTG]"
        }
    }

    var color: Color {
        switch self {
        case .ambientIntelligence: return .green
        case .transcription:       return .accentColor
        case .aiSearch:            return .accentColor
        case .meeting:             return .purple
        }
    }

    func next() -> PillMode {
        let all = PillMode.allCases
        let idx = all.firstIndex(of: self)!
        return all[(idx + 1) % all.count]
    }
}
