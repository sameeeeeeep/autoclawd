import Foundation

struct WorldModelGraphParser {

    static func parse(_ markdown: String) -> GraphModel {
        var model = GraphModel()
        var currentSectionID: String? = nil
        var sectionIndex = 0
        var factIndex = 0

        let lines = markdown.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") {
                // Section heading
                let heading = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let nodeID = "section-\(sectionIndex)"
                model.nodes.append(GraphNode(id: nodeID, label: heading, kind: .section))
                currentSectionID = nodeID
                sectionIndex += 1

            } else if trimmed.hasPrefix("- "), let sectionID = currentSectionID {
                // Fact bullet
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                guard !content.isEmpty else { continue }
                let nodeID = "fact-\(factIndex)"
                model.nodes.append(GraphNode(id: nodeID, label: content, kind: .fact))
                // Membership edge: section → fact
                let edgeID = "edge-mem-\(factIndex)"
                model.edges.append(GraphEdge(id: edgeID, fromID: sectionID, toID: nodeID, kind: .membership))
                factIndex += 1
            }
            // Ignore other lines (top-level #, blank lines, etc.)
        }

        // Cross-reference detection
        let facts = model.factNodes
        for i in 0..<facts.count {
            for j in (i+1)..<facts.count {
                let nodeA = facts[i]
                let nodeB = facts[j]
                // Skip if they share the same parent section
                let parentA = parentSectionID(for: nodeA.id, in: model)
                let parentB = parentSectionID(for: nodeB.id, in: model)
                guard let parentA, let parentB, parentA != parentB else { continue }
                // Find shared tokens ≥5 chars
                let tokensA = tokens(in: nodeA.label)
                let tokensB = tokens(in: nodeB.label)
                if !tokensA.intersection(tokensB).isEmpty {
                    let edgeID = "edge-xref-\(i)-\(j)"
                    model.edges.append(GraphEdge(id: edgeID, fromID: nodeA.id, toID: nodeB.id, kind: .crossReference))
                }
            }
        }

        return model
    }

    // MARK: - Helpers

    private static func tokens(in text: String) -> Set<String> {
        let words = text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count >= 5 }
        return Set(words)
    }

    private static func parentSectionID(for factID: String, in model: GraphModel) -> String? {
        model.edges
            .first(where: { $0.toID == factID && $0.kind == .membership })?
            .fromID
    }
}
