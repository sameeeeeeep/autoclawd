import Foundation

enum PillMode: String, CaseIterable {
    case ambientIntelligence = "ambientIntelligence"
    case transcription       = "transcription"
    case aiSearch            = "aiSearch"
    case code                = "code"

    var displayName: String {
        switch self {
        case .ambientIntelligence: return "Ambient"
        case .transcription:       return "Transcribe"
        case .aiSearch:            return "AI Search"
        case .code:                return "Code"
        }
    }

    var icon: String {
        switch self {
        case .ambientIntelligence: return "brain"
        case .transcription:       return "text.cursor"
        case .aiSearch:            return "magnifyingglass"
        case .code:                return "chevron.left.forwardslash.chevron.right"
        }
    }

    var shortLabel: String {
        switch self {
        case .ambientIntelligence: return "[AMB]"
        case .transcription:       return "[TRS]"
        case .aiSearch:            return "[SRC]"
        case .code:                return "[COD]"
        }
    }

    func next() -> PillMode {
        let all = PillMode.allCases
        let idx = all.firstIndex(of: self)!
        return all[(idx + 1) % all.count]
    }
}
