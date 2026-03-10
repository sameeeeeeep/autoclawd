import SwiftUI

// MARK: - Liquid Glass Design System
//
// Reusable glass components, tokens, and view modifiers for the liquid glass aesthetic.
// Backward-compatible with macOS 13+ — no macOS 26 APIs required.

// MARK: - Glass Tokens

enum Glass {
    // MARK: Corner Radii
    static let radiusSmall:  CGFloat = 12
    static let radiusMedium: CGFloat = 16
    static let radiusLarge:  CGFloat = 24
    static let radiusXL:     CGFloat = 32

    // MARK: Colors
    static let backgroundDark  = Color.white.opacity(0.06)
    static let backgroundLight = Color.white.opacity(0.04)
    static let textPrimary     = Color.white.opacity(0.90)
    static let textSecondary   = Color.white.opacity(0.55)
    static let textTertiary    = Color.white.opacity(0.30)
    static let divider         = Color.white.opacity(0.08)

    // MARK: Gradients

    /// Top-left–to–bottom-right border gradient simulating light catching a glass rim.
    static let borderGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.18),
            Color.white.opacity(0.08),
            Color.white.opacity(0.03)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Specular highlight — bright at top, fading down.
    static let specularGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.12),
            Color.white.opacity(0.04),
            Color.clear
        ],
        startPoint: .top,
        endPoint: .init(x: 0.5, y: 0.35)
    )

    /// Ambient background gradient for full-screen dark surfaces.
    static let ambientGradient = LinearGradient(
        colors: [
            Color(red: 0.06, green: 0.08, blue: 0.14),
            Color(red: 0.03, green: 0.04, blue: 0.08),
            Color(red: 0.02, green: 0.02, blue: 0.05)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Colored tint overlay (for semantic cards).
    static func tint(_ color: Color, opacity: Double = 0.08) -> Color {
        color.opacity(opacity)
    }
}

// MARK: - Glass Card View

/// A card with liquid glass treatment: translucent background, gradient border,
/// specular highlight, and subtle shadow.
struct LiquidGlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let tint: Color?
    let padding: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        cornerRadius: CGFloat = Glass.radiusMedium,
        tint: Color? = nil,
        padding: CGFloat = 20,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(
                ZStack {
                    // Base: translucent dark fill
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Glass.backgroundDark)

                    // Tint overlay (optional)
                    if let tint {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.08))
                    }

                    // Specular highlight (top region glow)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Glass.specularGradient)
                }
            )
            .overlay(
                // Light-catching border
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Glass.borderGradient, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
            .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Glass Icon Badge

/// Circular glass container for an SF Symbol icon.
struct GlassIconBadge: View {
    let systemImage: String
    let size: CGFloat
    let tint: Color

    init(_ systemImage: String, size: CGFloat = 52, tint: Color = .cyan) {
        self.systemImage = systemImage
        self.size = size
        self.tint = tint
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Glass.backgroundDark)
            Circle()
                .fill(tint.opacity(0.12))
            Circle()
                .fill(Glass.specularGradient)
            Circle()
                .strokeBorder(Glass.borderGradient, lineWidth: 1)

            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.4), radius: 6, x: 0, y: 0)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
    }
}

// MARK: - Glass Button

/// A button with liquid glass background and hover glow.
struct GlassButton: View {
    let title: String
    let icon: String?
    let tint: Color
    let isLarge: Bool
    let action: () -> Void

    @State private var isHovered = false

    init(_ title: String, icon: String? = nil, tint: Color = .cyan, isLarge: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.isLarge = isLarge
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: isLarge ? 16 : 13, weight: .medium))
                }
                Text(title)
                    .font(.system(size: isLarge ? 16 : 13, weight: .semibold))
            }
            .foregroundStyle(Glass.textPrimary)
            .padding(.horizontal, isLarge ? 32 : 20)
            .padding(.vertical, isLarge ? 14 : 10)
            .background(
                ZStack {
                    Capsule(style: .continuous)
                        .fill(tint.opacity(isHovered ? 0.25 : 0.15))
                    Capsule(style: .continuous)
                        .fill(Glass.specularGradient)
                }
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                tint.opacity(isHovered ? 0.5 : 0.3),
                                tint.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: tint.opacity(isHovered ? 0.25 : 0.1), radius: isHovered ? 12 : 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.2), value: isHovered)
    }
}

// MARK: - Glass Chip

/// Small pill-shaped glass element for tags, skip buttons, etc.
struct GlassChip: View {
    let title: String
    let icon: String?
    let action: (() -> Void)?

    @State private var isHovered = false

    init(_ title: String, icon: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        let label = HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
            }
            Text(title)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(Glass.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.08 : 0.04))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .onHover { isHovered = $0 }

        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }
}

// MARK: - Glass Progress Dots

/// Page indicator dots with glass treatment.
struct GlassProgressDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current
                        ? Color.cyan.opacity(0.8)
                        : Color.white.opacity(0.15)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                index == current
                                    ? Color.cyan.opacity(0.4)
                                    : Color.white.opacity(0.08),
                                lineWidth: 0.5
                            )
                    )
                    .frame(width: index == current ? 8 : 6,
                           height: index == current ? 8 : 6)
                    .shadow(color: index == current ? .cyan.opacity(0.3) : .clear,
                            radius: 4, x: 0, y: 0)
                    .animation(.easeInOut(duration: 0.3), value: current)
            }
        }
    }
}

// MARK: - Glass Divider

struct GlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(Glass.divider)
            .frame(height: 0.5)
    }
}

// MARK: - Animated Waveform

/// Animated waveform bars for the "Speak Naturally" onboarding card.
struct GlassWaveform: View {
    let barCount: Int
    let tint: Color
    @State private var isAnimating = false

    init(barCount: Int = 7, tint: Color = .cyan) {
        self.barCount = barCount
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.8), tint.opacity(0.3)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: isAnimating ? barHeight(for: i) : 6)
                    .animation(
                        .easeInOut(duration: duration(for: i))
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.08),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let heights: [CGFloat] = [14, 28, 20, 36, 24, 32, 16]
        return heights[index % heights.count]
    }

    private func duration(for index: Int) -> Double {
        let durations: [Double] = [0.5, 0.7, 0.6, 0.8, 0.55, 0.65, 0.45]
        return durations[index % durations.count]
    }
}

// MARK: - Pipeline Flow Graphic

/// Simplified 3-step flow: Mic → Brain → Tasks
struct GlassPipelineFlow: View {
    var body: some View {
        HStack(spacing: 16) {
            flowStep(icon: "mic.fill", label: "Listen", tint: .cyan)
            flowArrow()
            flowStep(icon: "brain.head.profile", label: "Analyze", tint: .purple)
            flowArrow()
            flowStep(icon: "checkmark.circle.fill", label: "Execute", tint: .green)
        }
    }

    private func flowStep(icon: String, label: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            GlassIconBadge(icon, size: 40, tint: tint)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Glass.textSecondary)
        }
    }

    private func flowArrow() -> some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Glass.textTertiary)
    }
}

// MARK: - View Modifiers

extension View {
    /// Applies full liquid glass card treatment.
    func liquidGlass(cornerRadius: CGFloat = Glass.radiusMedium, tint: Color? = nil) -> some View {
        self
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Glass.backgroundDark)
                    if let tint {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.08))
                    }
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Glass.specularGradient)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Glass.borderGradient, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
            .shadow(color: .black.opacity(0.06), radius: 1, x: 0, y: 1)
    }

    /// Applies only the glass gradient border.
    func liquidGlassBorder(cornerRadius: CGFloat = Glass.radiusMedium) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Glass.borderGradient, lineWidth: 1)
        )
    }
}
