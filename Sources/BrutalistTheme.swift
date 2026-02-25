import SwiftUI

// MARK: - Brutalist Design Tokens

enum BrutalistTheme {
    // Colors
    static let neonGreen       = Color(red: 0.0, green: 1.0, blue: 0.255)  // #00FF41
    static let divider         = Color.white.opacity(0.10)
    static let selectedBG      = Color.white.opacity(0.06)
    static let selectedAccent  = neonGreen

    // Typography — JetBrains Mono everywhere
    static let monoSM          = Font.custom("JetBrains Mono", size: 10)
    static let monoMD          = Font.custom("JetBrains Mono", size: 12)
    static let monoLG          = Font.custom("JetBrains Mono", size: 13).weight(.bold)
    static let monoHeader      = Font.custom("JetBrains Mono", size: 11).weight(.bold)

    // Geometry
    static let cornerRadius: CGFloat        = 0    // ZERO everywhere
    static let selectedAccentWidth: CGFloat = 4
    static let borderWidth: CGFloat         = 1
}

// MARK: - Brutalist Button Style

struct BrutalistButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BrutalistTheme.monoMD)
            .foregroundColor(configuration.isPressed
                ? (isDestructive ? .red : BrutalistTheme.neonGreen)
                : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black)
            .overlay(
                Rectangle()
                    .stroke(configuration.isPressed
                        ? (isDestructive ? Color.red : BrutalistTheme.neonGreen)
                        : Color.white.opacity(0.35),
                            lineWidth: BrutalistTheme.borderWidth)
            )
    }
}
