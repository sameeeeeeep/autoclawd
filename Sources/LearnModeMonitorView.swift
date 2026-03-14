import SwiftUI
import AppKit

// MARK: - Learn Mode Monitor View
//
// A compact floating panel that shows the live list of CanvasNodes captured
// during a FUCBC learn session. Displayed in a small window positioned in the
// top-right corner of the screen while Learn Mode is active.
//
// Wired by AppDelegate (Task 9) — shown when learnModeService.isActive turns true.

struct LearnModeMonitorView: View {
    @ObservedObject var service: LearnModeService

    var body: some View {
        VStack(spacing: 0) {
            header
            GlassDivider()
            nodeList
            GlassDivider()
            buildButton
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if service.isActive {
                CanvasPulsingDot(color: .red)
                Text("Recording")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Glass.textPrimary)
            } else {
                Text("Captured")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Glass.textSecondary)
            }
            Text("·")
                .foregroundStyle(Glass.textTertiary)
            Text("\(nodeCount) node\(nodeCount == 1 ? "" : "s")")
                .font(.system(size: 12))
                .foregroundStyle(Glass.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var nodeCount: Int { service.session?.nodes.count ?? 0 }

    // MARK: - Node List

    private var nodeList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let nodes = service.session?.nodes, !nodes.isEmpty {
                    ForEach(nodes) { node in
                        nodeRow(node)
                        GlassDivider()
                    }
                } else {
                    Text("Watching your screen…")
                        .font(.system(size: 12))
                        .foregroundStyle(Glass.textTertiary)
                        .padding(20)
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private func nodeRow(_ node: CanvasNode) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AppIconView(appName: node.app, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.app)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Glass.textPrimary)
                Text(node.displayTitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Glass.textSecondary)
                    .lineLimit(1)
                if let summary = node.workSummary {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(Glass.textTertiary)
                        .lineLimit(2)
                } else {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.55)
                        Text("Capturing…")
                            .font(.system(size: 11))
                            .foregroundStyle(Glass.textTertiary)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Build Button

    private var isBuilding: Bool {
        guard let phase = service.session?.phase else { return false }
        switch phase {
        case .building:   return true
        case .done:       return true
        case .failed:     return true
        case .collecting: return false
        }
    }

    private var buildButton: some View {
        GlassButton("Stop & Build", icon: "wand.and.stars", tint: .green, isLarge: false) {
            Task { await service.buildCapability() }
        }
        .disabled(isBuilding)
        .padding(12)
    }
}
