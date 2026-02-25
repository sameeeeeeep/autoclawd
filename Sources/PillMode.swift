import Foundation

enum PillMode: String, CaseIterable {
    case ambientIntelligence = "ambientIntelligence"
    case transcription       = "transcription"
    case aiSearch            = "aiSearch"

    var displayName: String {
        switch self {
        case .ambientIntelligence: return "Ambient"
        case .transcription:       return "Transcribe"
        case .aiSearch:            return "AI Search"
        }
    }

    var icon: String {
        switch self {
        case .ambientIntelligence: return "brain"
        case .transcription:       return "text.cursor"
        case .aiSearch:            return "magnifyingglass"
        }
    }

    var shortLabel: String {
        switch self {
        case .ambientIntelligence: return "[AMB]"
        case .transcription:       return "[TRS]"
        case .aiSearch:            return "[SRC]"
        }
    }

    func next() -> PillMode {
        let all = PillMode.allCases
        let idx = all.firstIndex(of: self)!
        return all[(idx + 1) % all.count]
    }
}
