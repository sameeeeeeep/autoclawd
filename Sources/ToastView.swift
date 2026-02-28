import SwiftUI

struct ToastView: View {
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 6) {
            // Level badge
            Text(badge)
                .font(AppTheme.caption)
                .foregroundColor(badgeColor)

            // Message — one line, truncated
            Text(entry.message)
                .font(AppTheme.caption)
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            // Component tag
            Text("[\(entry.component.rawValue)]")
                .font(AppTheme.caption)
                .foregroundColor(AppTheme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 40)
        .background(glassBackground)
        .overlay(
            Rectangle()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private var badge: String {
        switch entry.level {
        case .warn, .error: return "[!]"
        default:            return "[●]"
        }
    }

    private var badgeColor: Color {
        switch entry.level {
        case .warn, .error: return .red
        default:            return AppTheme.green
        }
    }

    private var glassBackground: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            // Specular sheen: white → clear top-to-center
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
        }
    }
}
