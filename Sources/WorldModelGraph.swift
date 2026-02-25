import CoreGraphics

// MARK: - Node Kind

enum NodeKind: Equatable {
    case section
    case fact
}

// MARK: - Edge Kind

enum EdgeKind: Equatable {
    case membership      // section → fact (parent owns child)
    case crossReference  // fact ↔ fact (shared keyword detected)
}

// MARK: - GraphNode

struct GraphNode: Identifiable, Equatable {
    let id: String          // e.g. "section-0", "fact-0-2"
    let label: String       // full display text (heading or bullet content)
    let kind: NodeKind
    var position: CGPoint = .zero   // set by layout
    var frame: CGRect = .zero       // set by layout; used for hit-testing
}

// MARK: - GraphEdge

struct GraphEdge: Identifiable, Equatable {
    let id: String
    let fromID: String
    let toID: String
    let kind: EdgeKind
}

// MARK: - GraphModel

struct GraphModel {
    var nodes: [GraphNode] = []
    var edges: [GraphEdge] = []

    var sectionNodes: [GraphNode] { nodes.filter { $0.kind == .section } }
    var factNodes: [GraphNode]    { nodes.filter { $0.kind == .fact    } }
}
