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
        let theme = ThemeManager.shared.current
        switch type {
        case .project: return theme.tagProject
        case .person:  return theme.tagPerson
        case .place:   return theme.tagPlace
        case .action:  return theme.tagAction
        case .status:  return theme.tagStatus
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: small ? 9 : 10, weight: .semibold))
            .tracking(0.3)
            .foregroundColor(color)
            .padding(.horizontal, small ? 7 : 10)
            .padding(.vertical, small ? 2 : 3)
            .background(
                Capsule()
                    .fill(color.opacity(0.09))
            )
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.17), lineWidth: 0.5)
            )
            .clipShape(Capsule())
    }
}

// MARK: - InfoButton

struct InfoButton: View {
    var action: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        let theme = ThemeManager.shared.current

        Button(action: { action?() }) {
            Text("i")
                .font(.custom("Georgia", size: 9).bold().italic())
                .foregroundColor(isHovered ? theme.accent : theme.textTertiary)
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(theme.isDark
                              ? Color.white.opacity(0.03)
                              : Color.black.opacity(0.03))
                )
                .overlay(
                    Circle()
                        .stroke(theme.glassBorder, lineWidth: 0.5)
                )
                .shadow(color: isHovered ? theme.accent.opacity(0.4) : .clear, radius: 6)
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
        let theme = ThemeManager.shared.current

        HStack(spacing: 4) {
            Circle()
                .fill(theme.error)
                .frame(width: 5, height: 5)
                .opacity(pulse ? 1.0 : 0.3)
                .shadow(color: pulse ? theme.error.opacity(0.6) : .clear, radius: 3)

            Text("LIVE")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .foregroundColor(theme.error)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(theme.error.opacity(0.09))
        )
        .overlay(
            Capsule()
                .stroke(theme.error.opacity(0.21), lineWidth: 0.5)
        )
        .clipShape(Capsule())
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
        case .auto: return "\u{26A1}"
        case .ask:  return "\u{2753}"
        case .user: return "\u{1F464}"
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
        let theme = ThemeManager.shared.current
        switch mode {
        case .auto: return theme.accent
        case .ask:  return theme.warning
        case .user: return theme.tertiary
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(icon)
                .font(.system(size: 9))
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.3)
        }
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(color.opacity(0.09))
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(0.15), lineWidth: 0.5)
        )
        .clipShape(Capsule())
    }
}

// MARK: - StatusDot

struct StatusDot: View {
    let status: String

    private var color: Color {
        let theme = ThemeManager.shared.current
        switch status {
        case "completed":        return theme.accent
        case "ongoing":          return theme.warning
        case "pending_approval": return theme.warning
        case "needs_input":      return theme.secondary
        case "upcoming":         return theme.textTertiary
        case "filtered":         return theme.textTertiary
        default:                 return theme.textTertiary
        }
    }

    private var showGlow: Bool {
        status == "completed"
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .shadow(color: showGlow ? color.opacity(0.5) : .clear, radius: 4)
    }
}

// MARK: - GlassCard ViewModifier

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        let theme = ThemeManager.shared.current
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(theme.glass)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(theme.glassBorder, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}
