import SwiftUI

struct ToastView: View {
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 6) {
            // Level badge
            Text(badge)
                .font(BrutalistTheme.monoSM)
                .foregroundColor(badgeColor)

            // Message — one line, truncated
            Text(entry.message)
                .font(BrutalistTheme.monoSM)
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            // Component tag
            Text("[\(entry.component.rawValue)]")
                .font(BrutalistTheme.monoSM)
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 0)
        .frame(height: 36)
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
        default:            return BrutalistTheme.neonGreen
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
