import SwiftUI

// MARK: - AgentsView
//
// "My Agents" — panel-level dashboard of all built FUCBC capabilities.
// Mirrors Cofia's "Henry's Agents" grid: 3-col card layout, one click to run.
//
// Lives in the main panel sidebar as its own "Agents" tab — separate from the
// Canvas/learn flow. Persistent, always accessible.

struct AgentsView: View {

    @ObservedObject var appState: AppState
    @State private var capabilities: [Capability] = []
    @State private var runningID: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.2)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .capabilityStoreDidChange)) { _ in
            reload()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("My Agents")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Workflows that run on your behalf — one click to activate")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !capabilities.isEmpty {
                Text("\(capabilities.count) agent\(capabilities.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if capabilities.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ],
                    spacing: 14
                ) {
                    ForEach(capabilities) { cap in
                        AgentCard(
                            capability: cap,
                            isRunning: runningID == cap.id,
                            onRun: { runCapability(cap) }
                        )
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            VStack(spacing: 6) {
                Text("No agents yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Switch to Canvas and record a session.\nAutoClawd will build your first agent automatically.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Actions

    private func reload() {
        capabilities = CapabilityStore.shared.all()
    }

    private func runCapability(_ cap: Capability) {
        runningID = cap.id
        appState.executeCapability(cap)
        // Clear running indicator after a moment (canvas takes over)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if runningID == cap.id { runningID = nil }
        }
    }
}

// MARK: - AgentCard

/// A single capability card in the Agents grid.
/// Design mirrors Cofia "Henry's Agents": app icons, bold title, muted description, Run button.
struct AgentCard: View {

    let capability: Capability
    let isRunning: Bool
    let onRun: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Top: app icon strip + run button
            HStack(alignment: .center, spacing: 0) {
                appIconStrip
                Spacer()
                runButton
            }
            .padding(.bottom, 12)

            // Title
            Text(capability.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 5)

            // Description
            Text(capability.description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 10)

            // Footer: step count + category
            HStack(spacing: 6) {
                Label("\(capability.subWorkflows.count) step\(capability.subWorkflows.count == 1 ? "" : "s")",
                      systemImage: "arrow.trianglehead.branch")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(capability.category.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(categoryColor(capability.category).opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(categoryColor(capability.category).opacity(0.08))
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .frame(minHeight: 150)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isHovered ? Color.primary.opacity(0.15) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(isHovered ? 0.10 : 0.04), radius: isHovered ? 12 : 4, x: 0, y: 2)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
    }

    // MARK: - Sub-views

    private var appIconStrip: some View {
        HStack(spacing: 5) {
            if capability.triggers.apps.isEmpty {
                // Fallback: capability emoji in a square
                Text(capability.emoji)
                    .font(.system(size: 18))
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                ForEach(Array(capability.triggers.apps.prefix(3)), id: \.self) { app in
                    appIcon(for: app)
                }
                if capability.triggers.apps.count > 3 {
                    Text("+\(capability.triggers.apps.count - 3)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
    }

    private func appIcon(for app: String) -> some View {
        let l = app.lowercased()
        let symbol: String
        let color: Color
        switch true {
        case l.contains("safari"):                        symbol = "safari.fill";     color = .blue
        case l.contains("chrome"), l.contains("arc"):    symbol = "globe";            color = .blue
        case l.contains("mail"):                          symbol = "envelope.fill";   color = .red
        case l.contains("slack"):                         symbol = "message.fill";    color = .purple
        case l.contains("notion"):                        symbol = "note.text";       color = .orange
        case l.contains("github"):                        symbol = "chevron.left.forwardslash.chevron.right"; color = .primary
        case l.contains("twitter"), l.contains("x.com"): symbol = "bird";            color = .cyan
        case l.contains("threads"):                       symbol = "at.circle.fill";  color = .primary
        case l.contains("reddit"):                        symbol = "arrow.up.circle.fill"; color = .orange
        case l.contains("youtube"):                       symbol = "play.rectangle.fill"; color = .red
        case l.contains("figma"):                         symbol = "paintbrush.fill"; color = .purple
        case l.contains("xcode"):                         symbol = "hammer.fill";     color = .blue
        case l.contains("sheet"), l.contains("excel"):   symbol = "tablecells.fill"; color = .green
        case l.contains("linear"), l.contains("jira"):   symbol = "checklist";       color = .blue
        case l.contains("terminal"):                      symbol = "terminal.fill";   color = .green
        default:                                          symbol = "app.fill";        color = .secondary
        }
        return Image(systemName: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color.opacity(0.85))
            .frame(width: 26, height: 26)
            .background(color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var runButton: some View {
        Button(action: onRun) {
            Group {
                if isRunning {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundStyle(isHovered ? Color.primary : Color.secondary)
            .frame(width: 28, height: 28)
            .background(isHovered ? Color.primary.opacity(0.10) : Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
    }

    private var cardBackground: some ShapeStyle {
        Color(NSColor.controlBackgroundColor)
    }

    // MARK: - Helpers

    private func categoryColor(_ cat: CapabilityCategory) -> Color {
        switch cat {
        case .research:      return .blue
        case .automation:    return .purple
        case .communication: return .green
        case .development:   return .orange
        case .discovery:     return .cyan
        case .organization:  return .indigo
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let capabilityStoreDidChange = Notification.Name("capabilityStoreDidChange")
}
