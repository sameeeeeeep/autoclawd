import SwiftUI

// MARK: - Shared Widget Panel Background

/// Reusable glassmorphic background for all widget panels below the pill.
/// Matches the pill's visual language: glass material + color gradient + border.
struct WidgetGlassBackground: View {
    var cornerRadius: CGFloat = 16
    var isActive: Bool = true

    private var theme: ThemePalette { ThemeManager.shared.current }

    var body: some View {
        ZStack {
            // Glass material
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            // Color gradient tint
            LinearGradient(
                colors: [
                    theme.glow1.opacity(isActive ? 0.06 : 0.02),
                    Color.clear,
                    theme.glow2.opacity(isActive ? 0.04 : 0.01)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Top specular highlight
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.clear],
                startPoint: .top,
                endPoint: .center
            )

            // Border
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.08),
                            theme.accent.opacity(isActive ? 0.14 : 0.04),
                            Color.white.opacity(0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Transcription Widget

/// Shows live transcription text as it gets recognised, plus an "Apply" button
/// to paste into the active text field.
struct TranscriptionWidgetView: View {
    let latestText: String
    let isListening: Bool
    let onApply: () -> Void

    private var theme: ThemePalette { ThemeManager.shared.current }

    private let widgetWidth: CGFloat = 220
    private let widgetHeight: CGFloat = 140

    var body: some View {
        ZStack(alignment: .top) {
            WidgetGlassBackground(isActive: isListening)

            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack(spacing: 5) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(theme.accent)

                    Text("TRANSCRIBING")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.accent.opacity(0.8))

                    Spacer()

                    // Live indicator dot
                    if isListening {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 5, height: 5)
                            .modifier(PulsingDot())
                    }
                }

                // Transcript text area
                ScrollView(.vertical, showsIndicators: false) {
                    Text(latestText.isEmpty ? "Listening..." : latestText)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(latestText.isEmpty
                            ? Color.white.opacity(0.25)
                            : Color.white.opacity(0.82))
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)

                // Apply button
                if !latestText.isEmpty {
                    Button(action: onApply) {
                        HStack(spacing: 4) {
                            Image(systemName: "text.insert")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Apply to Field")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(theme.isDark ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(theme.accent)
                        )
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(12)
        }
        .frame(width: widgetWidth, height: widgetHeight)
        .animation(.easeInOut(duration: 0.2), value: latestText.isEmpty)
    }
}

// MARK: - QA Widget

/// Shows the latest question and answer from AI Search mode as they get recognised.
struct QAWidgetView: View {
    let latestItem: QAItem?
    let isListening: Bool

    private var theme: ThemePalette { ThemeManager.shared.current }

    private let widgetWidth: CGFloat = 220
    private let widgetHeight: CGFloat = 150

    var body: some View {
        ZStack(alignment: .top) {
            WidgetGlassBackground(isActive: isListening)

            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(theme.accent)

                    Text("AI SEARCH")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.accent.opacity(0.8))

                    Spacer()

                    if isListening {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 5, height: 5)
                            .modifier(PulsingDot())
                    }
                }

                if let item = latestItem {
                    // Question
                    HStack(alignment: .top, spacing: 4) {
                        Text("Q")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(theme.secondary.opacity(0.9))
                        Text(item.question)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.55))
                            .lineLimit(2)
                    }

                    // Divider
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)

                    // Answer
                    ScrollView(.vertical, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 4) {
                            Text("A")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(theme.accent.opacity(0.9))
                            Text(item.answer)
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.82))
                                .lineSpacing(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    // Empty state
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "mic.circle")
                            .font(.system(size: 20, weight: .thin))
                            .foregroundColor(Color.white.opacity(0.15))
                        Text("Ask a question...")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.20))
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                }
            }
            .padding(12)
        }
        .frame(width: widgetWidth, height: widgetHeight)
    }
}

// MARK: - Pulsing Dot Modifier

/// Subtle pulsing animation for live indicator dots.
struct PulsingDot: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.35 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
