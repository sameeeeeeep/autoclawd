import SwiftUI

// MARK: - Shared Widget Panel Background

struct WidgetGlassBackground: View {
    var cornerRadius: CGFloat = 16
    var isActive: Bool = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Transcription Widget

struct TranscriptionWidgetView: View {
    let latestText: String
    let isListening: Bool
    let onApply: () -> Void

    private let widgetWidth: CGFloat = 220
    private let widgetHeight: CGFloat = 140

    var body: some View {
        ZStack(alignment: .top) {
            WidgetGlassBackground(isActive: isListening)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.accentColor)

                    Text("TRANSCRIBING")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentColor.opacity(0.8))

                    Spacer()

                    if isListening {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                            .modifier(PulsingDot())
                    }
                }

                ScrollView(.vertical, showsIndicators: false) {
                    Text(latestText.isEmpty ? "Listening..." : latestText)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(latestText.isEmpty ? .secondary : .primary)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)

                if !latestText.isEmpty {
                    Button(action: onApply) {
                        HStack(spacing: 4) {
                            Image(systemName: "text.insert")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Apply to Field")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.accentColor, in: Capsule())
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

struct QAWidgetView: View {
    let latestItem: QAItem?
    let isListening: Bool

    private let widgetWidth: CGFloat = 220
    private let widgetHeight: CGFloat = 150

    var body: some View {
        ZStack(alignment: .top) {
            WidgetGlassBackground(isActive: isListening)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.accentColor)

                    Text("AI SEARCH")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentColor.opacity(0.8))

                    Spacer()

                    if isListening {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                            .modifier(PulsingDot())
                    }
                }

                if let item = latestItem {
                    HStack(alignment: .top, spacing: 4) {
                        Text("Q")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.purple)
                        Text(item.question)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Divider()

                    ScrollView(.vertical, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 4) {
                            Text("A")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.accentColor)
                            Text(item.answer)
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineSpacing(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "mic.circle")
                            .font(.system(size: 20, weight: .thin))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("Ask a question...")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.4))
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
