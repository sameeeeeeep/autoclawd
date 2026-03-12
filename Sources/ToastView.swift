import SwiftUI

/// Capability suggestion toast — shown in top-right corner when `AppState.detectedCapability` is set.
struct CapabilityToastView: View {
    let capability: Capability
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Emoji icon
                Text(capability.emoji.isEmpty ? "⚡" : capability.emoji)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(capability.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Glass.textPrimary)
                        .lineLimit(1)

                    Text("Automate this?")
                        .font(.system(size: 11))
                        .foregroundStyle(Glass.textSecondary)
                }

                Spacer()

                // Dismiss button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Glass.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 260, height: 52)
            .background(glassBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var glassBackground: some View {
#if NATIVE_GLASS_AVAILABLE
        if #available(macOS 26, *) {
            Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                LinearGradient(colors: [Color.white.opacity(0.10), Color.clear],
                               startPoint: .top, endPoint: .center)
            }
        }
#else
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
            LinearGradient(colors: [Color.white.opacity(0.10), Color.clear],
                           startPoint: .top, endPoint: .center)
        }
#endif
    }
}

/// Legacy log entry toast — kept for pipeline log display on the pill.
struct ToastView: View {
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 6) {
            Text(badge)
                .font(AppTheme.caption)
                .foregroundColor(badgeColor)

            Text(entry.message)
                .font(AppTheme.caption)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Text("[\(entry.component.rawValue)]")
                .font(AppTheme.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 40)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(colors: [Color.white.opacity(0.10), Color.clear],
                               startPoint: .top, endPoint: .center)
            }
        )
        .overlay(
            Rectangle()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private var badge: String {
        switch entry.level {
        case .warn, .error: return "[!]"
        default:            return "[●]"
        }
    }

    private var badgeColor: Color {
        switch entry.level {
        case .warn, .error: return .red
        default:            return Color.green
        }
    }
}
