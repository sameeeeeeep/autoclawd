import CoreGraphics
import Foundation

struct WorldModelGraphLayout {

    // Fixed node sizes
    static let sectionSize = CGSize(width: 120, height: 30)
    static let factSize    = CGSize(width: 100, height: 24)

    // Grid spacing between section centres
    static let gridSpacingX: CGFloat = 260
    static let gridSpacingY: CGFloat = 200

    // Orbit radius for facts around their section
    static let orbitRadius: CGFloat = 90

    static func apply(to model: inout GraphModel, in canvasSize: CGSize) {
        let sections = model.sectionNodes
        guard !sections.isEmpty else { return }

        // Compute grid dimensions
        let cols = max(1, Int(ceil(sqrt(Double(sections.count)))))
        let totalW = CGFloat(cols) * gridSpacingX
        let rows = Int(ceil(Double(sections.count) / Double(cols)))
        let totalH = CGFloat(rows) * gridSpacingY

        // Offset so grid is roughly centred in canvas
        let offsetX = max(gridSpacingX / 2, (canvasSize.width  - totalW) / 2 + gridSpacingX / 2)
        let offsetY = max(gridSpacingY / 2, (canvasSize.height - totalH) / 2 + gridSpacingY / 2)

        // Place section nodes
        var sectionPositions: [String: CGPoint] = [:]
        for (idx, section) in sections.enumerated() {
            let col = idx % cols
            let row = idx / cols
            let centre = CGPoint(
                x: offsetX + CGFloat(col) * gridSpacingX,
                y: offsetY + CGFloat(row) * gridSpacingY
            )
            sectionPositions[section.id] = centre
            setNode(id: section.id, centre: centre, size: sectionSize, in: &model)
        }

        // Place fact nodes in orbit around their parent section
        // Group facts by parent section
        var factsBySection: [String: [GraphNode]] = [:]
        for fact in model.factNodes {
            let parentID = model.edges
                .first(where: { $0.toID == fact.id && $0.kind == .membership })?
                .fromID ?? ""
            factsBySection[parentID, default: []].append(fact)
        }

        for (sectionID, facts) in factsBySection {
            guard let centre = sectionPositions[sectionID] else { continue }
            let count = facts.count
            for (i, fact) in facts.enumerated() {
                // Distribute evenly; start from top (-π/2)
                let angle = -CGFloat.pi / 2 + CGFloat(i) * (2 * CGFloat.pi / CGFloat(max(count, 1)))
                let factCentre = CGPoint(
                    x: centre.x + orbitRadius * cos(angle),
                    y: centre.y + orbitRadius * sin(angle)
                )
                setNode(id: fact.id, centre: factCentre, size: factSize, in: &model)
            }
        }
    }

    // MARK: - Helper

    private static func setNode(id: String, centre: CGPoint, size: CGSize, in model: inout GraphModel) {
        guard let idx = model.nodes.firstIndex(where: { $0.id == id }) else { return }
        model.nodes[idx].position = centre
        model.nodes[idx].frame = CGRect(
            x: centre.x - size.width / 2,
            y: centre.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
