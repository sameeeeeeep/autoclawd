import SwiftUI

// MARK: - WorkflowCanvasView
//
// Cofia-style horizontal node chain for displaying task workflows.
//
// Layout:
//   • Horizontal ScrollView with a ZStack of:
//       - Connector layer: Canvas drawing straight arrows between nodes
//       - Node layer: HStack of circle nodes with status overlays
//       - Loop arc: Quadratic curve arc from last→first (when isRecurring)
//   • Node tap → shows a popover with description + invocation details

struct WorkflowCanvasView: View {

    let nodes: [WorkflowNodeViewModel]
    let isRecurring: Bool
    var onNodeTap: ((WorkflowNodeViewModel) -> Void)?

    @State private var selectedNode: WorkflowNodeViewModel?
    @State private var showPopover = false

    private let nodeSize: CGFloat = 56
    private let connectorLength: CGFloat = 40
    private let verticalPadding: CGFloat = 32   // room for the loop arc above

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                connectorLayer
                    .frame(width: canvasWidth, height: nodeSize + verticalPadding * 2)
                nodeLayer
                    .frame(width: canvasWidth, height: nodeSize + verticalPadding * 2)
                if isRecurring && nodes.count >= 2 {
                    loopArc
                        .frame(width: canvasWidth, height: nodeSize + verticalPadding * 2)
                }
            }
            .frame(height: nodeSize + verticalPadding * 2)
            .padding(.horizontal, 20)
        }
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            if let node = selectedNode {
                nodePopover(node: node)
            }
        }
    }

    // MARK: - Canvas Width

    private var canvasWidth: CGFloat {
        let n = max(nodes.count, 1)
        return CGFloat(n) * nodeSize + CGFloat(n - 1) * connectorLength + 40
    }

    // MARK: - Node Layer

    private var nodeLayer: some View {
        HStack(spacing: connectorLength) {
            ForEach(nodes) { node in
                nodeCircle(node: node)
                    .frame(width: nodeSize, height: nodeSize)
                    .onTapGesture {
                        selectedNode = node
                        showPopover = true
                        onNodeTap?(node)
                    }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, verticalPadding)
    }

    // MARK: - Node Circle

    @ViewBuilder
    private func nodeCircle(node: WorkflowNodeViewModel) -> some View {
        ZStack {
            Circle()
                .fill(Glass.backgroundDark)
                .overlay(
                    Circle()
                        .stroke(borderColor(for: node.status), lineWidth: 1.5)
                )

            Image(systemName: node.icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor(for: node.status))

            // Status overlay
            switch node.status {
            case .done:
                Circle()
                    .fill(Color.green.opacity(0.85))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.black)
                    )
                    .offset(x: nodeSize * 0.3, y: -(nodeSize * 0.3))

            case .failed:
                Circle()
                    .fill(Color.red.opacity(0.85))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .offset(x: nodeSize * 0.3, y: -(nodeSize * 0.3))

            case .running:
                CanvasPulsingDot(color: .cyan.opacity(0.8))
                    .offset(x: nodeSize * 0.3, y: -(nodeSize * 0.3))

            default:
                EmptyView()
            }

            // Label below circle
            VStack(spacing: 4) {
                Spacer()
                Text(node.name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Glass.textSecondary)
                    .lineLimit(1)
                    .frame(width: nodeSize + 10)
            }
            .offset(y: nodeSize * 0.6)
        }
    }

    // MARK: - Connector Layer

    private var connectorLayer: some View {
        Canvas { ctx, size in
            guard nodes.count > 1 else { return }
            let yCenter = verticalPadding + nodeSize / 2
            let startX: CGFloat = 20

            for i in 0..<(nodes.count - 1) {
                let x0 = startX + CGFloat(i) * (nodeSize + connectorLength) + nodeSize
                let x1 = x0 + connectorLength
                let y = yCenter

                var path = Path()
                path.move(to: CGPoint(x: x0, y: y))
                path.addLine(to: CGPoint(x: x1 - 6, y: y))

                ctx.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color.cyan.opacity(0.35),
                            Color.cyan.opacity(0.20)
                        ]),
                        startPoint: CGPoint(x: x0, y: y),
                        endPoint: CGPoint(x: x1, y: y)
                    ),
                    lineWidth: 1.5
                )

                // Arrow head
                let arrowPath = arrowHead(
                    at: CGPoint(x: x1 - 2, y: y),
                    angle: 0,
                    size: 5
                )
                ctx.fill(arrowPath, with: .color(Color.cyan.opacity(0.4)))
            }
        }
    }

    // MARK: - Loop Arc

    private var loopArc: some View {
        Canvas { ctx, size in
            let yCenter = verticalPadding + nodeSize / 2
            let startX: CGFloat = 20
            let firstNodeCenter = startX + nodeSize / 2
            let lastNodeCenter  = startX + CGFloat(nodes.count - 1) * (nodeSize + connectorLength) + nodeSize / 2
            let arcTop: CGFloat = verticalPadding - 16

            var path = Path()
            path.move(to: CGPoint(x: lastNodeCenter, y: yCenter - nodeSize / 2))
            path.addQuadCurve(
                to: CGPoint(x: firstNodeCenter, y: yCenter - nodeSize / 2),
                control: CGPoint(x: (firstNodeCenter + lastNodeCenter) / 2, y: arcTop)
            )

            ctx.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [
                        Color.purple.opacity(0.5),
                        Color.cyan.opacity(0.3)
                    ]),
                    startPoint: CGPoint(x: lastNodeCenter, y: yCenter),
                    endPoint: CGPoint(x: firstNodeCenter, y: yCenter)
                ),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
            )

            // Arrow at the first node end
            let arrowPath = arrowHead(
                at: CGPoint(x: firstNodeCenter + 2, y: yCenter - nodeSize / 2),
                angle: .pi / 2,  // pointing downward
                size: 5
            )
            ctx.fill(arrowPath, with: .color(Color.purple.opacity(0.5)))

            // "Repeat" label at midpoint
            let midX = (firstNodeCenter + lastNodeCenter) / 2
            ctx.draw(
                Text("repeat").font(.system(size: 9)).foregroundColor(Color.purple.opacity(0.6)),
                at: CGPoint(x: midX, y: arcTop - 6),
                anchor: .center
            )
        }
    }

    // MARK: - Arrow Head

    private func arrowHead(at point: CGPoint, angle: CGFloat, size: CGFloat) -> Path {
        var path = Path()
        path.move(to: point)
        path.addLine(to: CGPoint(
            x: point.x - size * cos(angle - 0.4),
            y: point.y - size * sin(angle - 0.4)
        ))
        path.addLine(to: CGPoint(
            x: point.x - size * cos(angle + 0.4),
            y: point.y - size * sin(angle + 0.4)
        ))
        path.closeSubpath()
        return path
    }

    // MARK: - Status Helpers

    private func borderColor(for status: NodeStatus) -> Color {
        switch status {
        case .idle:    return Glass.textTertiary
        case .running: return Color.cyan.opacity(0.7)
        case .done:    return Color.green.opacity(0.7)
        case .failed:  return Color.red.opacity(0.7)
        }
    }

    private func iconColor(for status: NodeStatus) -> Color {
        switch status {
        case .idle:    return Glass.textSecondary
        case .running: return Color.cyan
        case .done:    return Color.green
        case .failed:  return Color.red
        }
    }

    // MARK: - Node Popover

    private func statusLabel(for status: NodeStatus) -> String {
        switch status {
        case .idle:    return "Waiting"
        case .running: return "Running"
        case .done:    return "Complete"
        case .failed:  return "Failed"
        }
    }

    private func nodePopover(node: WorkflowNodeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: node.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Glass.textPrimary)
                Text(node.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Glass.textPrimary)
            }

            if !node.description.isEmpty {
                Text(node.description)
                    .font(.system(size: 12))
                    .foregroundStyle(Glass.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let inv = node.invocation, !inv.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Invocation")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Glass.textTertiary)
                        .textCase(.uppercase)
                    Text(inv)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.cyan.opacity(0.85))
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                }
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(borderColor(for: node.status))
                    .frame(width: 6, height: 6)
                Text(statusLabel(for: node.status))
                    .font(.system(size: 10))
                    .foregroundStyle(Glass.textSecondary)
            }
        }
        .padding(14)
        .frame(width: 240)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        .cornerRadius(Glass.radiusMedium)
    }
}

// MARK: - Preview

#if DEBUG
struct WorkflowCanvasView_Previews: PreviewProvider {
    static var previews: some View {
        let nodes: [WorkflowNodeViewModel] = [
            WorkflowNodeViewModel(name: "Fetch", description: "Get data", icon: "map.fill", status: .done),
            WorkflowNodeViewModel(name: "Analyse", description: "Process", icon: "sparkles", status: .running),
            WorkflowNodeViewModel(name: "Post", description: "Publish result", icon: "paperplane.fill", status: .idle),
        ]
        WorkflowCanvasView(nodes: nodes, isRecurring: true)
            .frame(height: 130)
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}
#endif
