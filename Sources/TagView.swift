import SwiftUI

// MARK: - Tag Types

enum TagType {
    case project, person, place, action, status
}

// MARK: - TagView

struct TagView: View {
    let type: TagType
    let label: String
    var small: Bool = false

    private var color: Color {
        switch type {
        case .project: return .blue
        case .person:  return .pink
        case .place:   return .purple
        case .action:  return .orange
        case .status:  return .green
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: small ? 9 : 10, weight: .medium))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, small ? 6 : 8)
            .padding(.vertical, small ? 2 : 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - InfoButton

struct InfoButton: View {
    var action: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        Button(action: { action?() }) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundColor(isHovered ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - LiveBadge

struct LiveBadge: View {
    @State private var pulse = true

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.red)
                .frame(width: 5, height: 5)
                .opacity(pulse ? 1.0 : 0.3)

            Text("LIVE")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .foregroundColor(.red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Color.red.opacity(0.1), in: Capsule())
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                pulse = false
            }
        }
    }
}

// MARK: - ModeBadge

struct ModeBadge: View {
    enum Mode {
        case auto, ask, user
    }

    let mode: Mode

    private var icon: String {
        switch mode {
        case .auto: return "bolt.fill"
        case .ask:  return "questionmark.circle"
        case .user: return "person.fill"
        }
    }

    private var label: String {
        switch mode {
        case .auto: return "Auto"
        case .ask:  return "Ask"
        case .user: return "User"
        }
    }

    private var color: Color {
        switch mode {
        case .auto: return .accentColor
        case .ask:  return .orange
        case .user: return .cyan
        }
    }

    var body: some View {
        Label(label, systemImage: icon)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }
}

// MARK: - StatusDot

struct StatusDot: View {
    let status: String

    private var color: Color {
        switch status {
        case "completed":        return .green
        case "ongoing":          return .orange
        case "pending_approval": return .orange
        case "needs_input":      return .purple
        case "upcoming":         return Color(NSColor.tertiaryLabelColor)
        case "filtered":         return Color(NSColor.tertiaryLabelColor)
        default:                 return Color(NSColor.tertiaryLabelColor)
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }
}

// MARK: - GlassCard ViewModifier (now uses system material)

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color(.separatorColor), lineWidth: 0.5)
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 10) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}
