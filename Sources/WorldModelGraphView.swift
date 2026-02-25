import SwiftUI

// MARK: - WorldModelGraphView (container)

struct WorldModelGraphView: View {
    @ObservedObject var appState: AppState
    @State private var showRawEditor = false
    @State private var rawContent: String = ""
    @State private var model: GraphModel = GraphModel()
    @State private var selectedNodeID: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(BrutalistTheme.divider)
            if showRawEditor {
                rawEditor
            } else {
                graphArea
            }
        }
        .onAppear { refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("WORLD MODEL")
                .font(BrutalistTheme.monoLG)
                .foregroundColor(.white)
            Spacer()
            Button(showRawEditor ? "SHOW GRAPH" : "EDIT RAW") {
                if showRawEditor {
                    // Save raw edits back to disk before switching to graph
                    appState.saveWorldModel(rawContent)
                    refresh()
                } else {
                    rawContent = appState.worldModelContent
                }
                showRawEditor.toggle()
            }
            .buttonStyle(BrutalistButtonStyle())

            if !showRawEditor {
                Button("REFRESH") { refresh() }
                    .buttonStyle(BrutalistButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Raw Editor

    private var rawEditor: some View {
        TextEditor(text: $rawContent)
            .font(.custom("JetBrains Mono", size: 12))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
            .onChange(of: rawContent) { newVal in
                appState.saveWorldModel(newVal)
            }
    }

    // MARK: - Graph Area

    private var graphArea: some View {
        VStack(spacing: 0) {
            ScrollView([.horizontal, .vertical]) {
                WorldModelCanvasView(
                    model: model,
                    selectedNodeID: $selectedNodeID
                )
                .frame(
                    width: requiredCanvasWidth,
                    height: requiredCanvasHeight
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let nodeID = selectedNodeID,
               let node = model.nodes.first(where: { $0.id == nodeID }) {
                Divider().background(BrutalistTheme.divider)
                WorldModelDetailPanel(node: node)
                    .frame(height: 60)
            }
        }
    }

    // MARK: - Helpers

    private var requiredCanvasWidth: CGFloat {
        let maxX = model.nodes.map { $0.frame.maxX }.max() ?? 400
        return max(600, maxX + 60)
    }

    private var requiredCanvasHeight: CGFloat {
        let maxY = model.nodes.map { $0.frame.maxY }.max() ?? 400
        return max(500, maxY + 60)
    }

    private func refresh() {
        let content = appState.worldModelContent
        var parsed = WorldModelGraphParser.parse(content)
        let size = CGSize(width: max(800, requiredCanvasWidth), height: max(600, requiredCanvasHeight))
        WorldModelGraphLayout.apply(to: &parsed, in: size)
        model = parsed
        selectedNodeID = nil
    }
}

// MARK: - WorldModelCanvasView

struct WorldModelCanvasView: View {
    let model: GraphModel
    @Binding var selectedNodeID: String?

    var body: some View {
        Canvas { ctx, size in
            // Black background
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

            // Draw edges
            for edge in model.edges {
                guard
                    let fromNode = model.nodes.first(where: { $0.id == edge.fromID }),
                    let toNode   = model.nodes.first(where: { $0.id == edge.toID })
                else { continue }

                var path = Path()
                path.move(to: fromNode.position)
                path.addLine(to: toNode.position)

                let color: Color = edge.kind == .crossReference
                    ? BrutalistTheme.neonGreen
                    : Color.white.opacity(0.20)
                ctx.stroke(path, with: .color(color), lineWidth: 1)
            }

            // Draw nodes
            for node in model.nodes {
                let isSelected = node.id == selectedNodeID
                let nodeColor: Color = isSelected ? BrutalistTheme.neonGreen : Color.white.opacity(0.70)
                let borderWidth: CGFloat = isSelected ? 2 : 1

                // Rectangle fill (black) + border
                let rect = node.frame
                ctx.fill(Path(rect), with: .color(.black))
                ctx.stroke(Path(rect), with: .color(nodeColor), lineWidth: borderWidth)

                // Label — truncate if too long
                let label = String(node.label.prefix(node.kind == .section ? 18 : 15))
                let fontSize: CGFloat = node.kind == .section ? 10 : 9
                let resolvedText = Text(label)
                    .font(.custom("JetBrains Mono", size: fontSize).weight(node.kind == .section ? .bold : .regular))
                    .foregroundColor(nodeColor)

                ctx.draw(resolvedText, at: node.position, anchor: .center)
            }
        }
        .background(Color.black)
        .gesture(
            SpatialTapGesture()
                .onEnded { event in
                    let loc = event.location
                    if let hit = model.nodes.first(where: { $0.frame.contains(loc) }) {
                        selectedNodeID = hit.id == selectedNodeID ? nil : hit.id
                    } else {
                        selectedNodeID = nil
                    }
                }
        )
    }
}

// MARK: - WorldModelDetailPanel

struct WorldModelDetailPanel: View {
    let node: GraphNode

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Kind badge
            Text(node.kind == .section ? "[SECTION]" : "[FACT]")
                .font(BrutalistTheme.monoMD)
                .foregroundColor(BrutalistTheme.neonGreen)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(Rectangle().stroke(BrutalistTheme.neonGreen, lineWidth: 1))

            // Full label
            Text(node.label)
                .font(BrutalistTheme.monoMD)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
    }
}
