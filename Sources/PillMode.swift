import Foundation
import SwiftUI

enum PillMode: String, CaseIterable {
    case ambient  = "ambient"       // Passive sensing: suggest existing capabilities, discover new use cases
    case aiSearch = "aiSearch"
    case learn    = "learn"         // Active walkthrough: user shows workflow → build capabilities + workflow

    var displayName: String {
        switch self {
        case .ambient:  return "Ambient"
        case .aiSearch: return "AI Search"
        case .learn:    return "Learn"
        }
    }

    var icon: String {
        switch self {
        case .ambient:  return "checklist"
        case .aiSearch: return "magnifyingglass"
        case .learn:    return "brain.head.profile"
        }
    }

    var shortLabel: String {
        switch self {
        case .ambient:  return "[AMB]"
        case .aiSearch: return "[SRC]"
        case .learn:    return "[LRN]"
        }
    }

    var color: Color {
        switch self {
        case .ambient:  return .green
        case .aiSearch: return .accentColor
        case .learn:    return .cyan
        }
    }

    func next() -> PillMode {
        let all = PillMode.allCases
        let idx = all.firstIndex(of: self)!
        return all[(idx + 1) % all.count]
    }
}
