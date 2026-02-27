// Sources/AppTheme.swift
import AppKit
import SwiftUI

// MARK: - Theme Palette

struct ThemePalette {
    // Core
    let accent: Color
    let secondary: Color
    let tertiary: Color
    let warning: Color
    let error: Color

    // Surfaces
    let surface: Color
    let glass: Color
    let glassBorder: Color
    let glassHighlight: Color

    // Text
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    // Tags
    let tagProject: Color
    let tagPerson: Color
    let tagPlace: Color
    let tagAction: Color
    let tagStatus: Color

    // Glow
    let glow1: Color
    let glow2: Color

    // Mode
    let isDark: Bool

    // Background gradient stops (2-4 colors for a linear gradient)
    let bgGradientStops: [Color]
}

// MARK: - Theme Key

enum ThemeKey: String, CaseIterable, Identifiable {
    case neon
    case pastel
    case cyber
    case light

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .neon:   return "Neon"
        case .pastel: return "Pastel"
        case .cyber:  return "Purple/Cyan"
        case .light:  return "Light"
        }
    }
}

// MARK: - Static Palette Definitions

extension ThemePalette {

    static let neon = ThemePalette(
        accent:         Color(hex: "#00FF9F"),
        secondary:      Color(hex: "#FF00E5"),
        tertiary:       Color(hex: "#00D4FF"),
        warning:        Color(hex: "#FFE500"),
        error:          Color(hex: "#FF3D3D"),
        surface:        Color(rgba: 10.0/255.0, 10.0/255.0, 18.0/255.0, 0.85),
        glass:          Color(rgba: 18.0/255.0, 18.0/255.0, 30.0/255.0, 0.72),
        glassBorder:    Color(rgba: 1.0,        1.0,        1.0,        0.09),
        glassHighlight: Color(rgba: 1.0,        1.0,        1.0,        0.05),
        textPrimary:    Color(rgba: 1.0,        1.0,        1.0,        0.93),
        textSecondary:  Color(rgba: 1.0,        1.0,        1.0,        0.55),
        textTertiary:   Color(rgba: 1.0,        1.0,        1.0,        0.28),
        tagProject:     Color(hex: "#00D4FF"),
        tagPerson:      Color(hex: "#FF00E5"),
        tagPlace:       Color(hex: "#BF5AF2"),
        tagAction:      Color(hex: "#FFE500"),
        tagStatus:      Color(hex: "#00FF9F"),
        glow1:          Color(hex: "#00FF9F"),
        glow2:          Color(hex: "#FF00E5"),
        isDark:         true,
        bgGradientStops: [
            Color(hex: "#05050d"),
            Color(hex: "#0a0f18"),
            Color(hex: "#080d14"),
            Color(hex: "#0d0818"),
        ]
    )

    static let pastel = ThemePalette(
        accent:         Color(hex: "#A8D8B9"),
        secondary:      Color(hex: "#F2B5D4"),
        tertiary:       Color(hex: "#B8D4E3"),
        warning:        Color(hex: "#F7DC6F"),
        error:          Color(hex: "#E8A0BF"),
        surface:        Color(rgba: 22.0/255.0, 20.0/255.0, 28.0/255.0, 0.88),
        glass:          Color(rgba: 30.0/255.0, 28.0/255.0, 38.0/255.0, 0.75),
        glassBorder:    Color(rgba: 1.0,        1.0,        1.0,        0.07),
        glassHighlight: Color(rgba: 1.0,        1.0,        1.0,        0.04),
        textPrimary:    Color(rgba: 1.0,        1.0,        1.0,        0.88),
        textSecondary:  Color(rgba: 1.0,        1.0,        1.0,        0.52),
        textTertiary:   Color(rgba: 1.0,        1.0,        1.0,        0.26),
        tagProject:     Color(hex: "#B8D4E3"),
        tagPerson:      Color(hex: "#F2B5D4"),
        tagPlace:       Color(hex: "#C9B1FF"),
        tagAction:      Color(hex: "#F7DC6F"),
        tagStatus:      Color(hex: "#A8D8B9"),
        glow1:          Color(hex: "#A8D8B9"),
        glow2:          Color(hex: "#F2B5D4"),
        isDark:         true,
        bgGradientStops: [
            Color(hex: "#12101a"),
            Color(hex: "#181520"),
            Color(hex: "#14121c"),
            Color(hex: "#1a1522"),
        ]
    )

    static let cyber = ThemePalette(
        accent:         Color(hex: "#00F0FF"),
        secondary:      Color(hex: "#B44AFF"),
        tertiary:       Color(hex: "#7B68EE"),
        warning:        Color(hex: "#FF9F43"),
        error:          Color(hex: "#FF4757"),
        surface:        Color(rgba: 8.0/255.0,   6.0/255.0,   20.0/255.0,  0.88),
        glass:          Color(rgba: 16.0/255.0,  12.0/255.0,  32.0/255.0,  0.75),
        glassBorder:    Color(rgba: 140.0/255.0, 120.0/255.0, 255.0/255.0, 0.10),
        glassHighlight: Color(rgba: 140.0/255.0, 120.0/255.0, 255.0/255.0, 0.04),
        textPrimary:    Color(rgba: 230.0/255.0, 225.0/255.0, 255.0/255.0, 0.93),
        textSecondary:  Color(rgba: 200.0/255.0, 195.0/255.0, 230.0/255.0, 0.55),
        textTertiary:   Color(rgba: 180.0/255.0, 175.0/255.0, 210.0/255.0, 0.30),
        tagProject:     Color(hex: "#00F0FF"),
        tagPerson:      Color(hex: "#B44AFF"),
        tagPlace:       Color(hex: "#7B68EE"),
        tagAction:      Color(hex: "#FF9F43"),
        tagStatus:      Color(hex: "#00F0FF"),
        glow1:          Color(hex: "#00F0FF"),
        glow2:          Color(hex: "#B44AFF"),
        isDark:         true,
        bgGradientStops: [
            Color(hex: "#06041a"),
            Color(hex: "#0c0824"),
            Color(hex: "#08061e"),
            Color(hex: "#100a28"),
        ]
    )

    static let light = ThemePalette(
        accent:         Color(hex: "#059669"),
        secondary:      Color(hex: "#D946EF"),
        tertiary:       Color(hex: "#2563EB"),
        warning:        Color(hex: "#D97706"),
        error:          Color(hex: "#DC2626"),
        surface:        Color(rgba: 1.0,        1.0,        1.0,        0.92),
        glass:          Color(rgba: 1.0,        1.0,        1.0,        0.80),
        glassBorder:    Color(rgba: 0.0,        0.0,        0.0,        0.08),
        glassHighlight: Color(rgba: 0.0,        0.0,        0.0,        0.02),
        textPrimary:    Color(rgba: 15.0/255.0, 23.0/255.0, 42.0/255.0, 0.92),
        textSecondary:  Color(rgba: 51.0/255.0, 65.0/255.0, 85.0/255.0, 0.70),
        textTertiary:   Color(rgba: 100.0/255.0, 116.0/255.0, 139.0/255.0, 0.55),
        tagProject:     Color(hex: "#2563EB"),
        tagPerson:      Color(hex: "#D946EF"),
        tagPlace:       Color(hex: "#7C3AED"),
        tagAction:      Color(hex: "#D97706"),
        tagStatus:      Color(hex: "#059669"),
        glow1:          Color(hex: "#059669"),
        glow2:          Color(hex: "#D946EF"),
        isDark:         false,
        bgGradientStops: [
            Color(hex: "#F8FAFC"),
            Color(hex: "#F1F5F9"),
            Color(hex: "#E2E8F0"),
            Color(hex: "#F8FAFC"),
        ]
    )

    /// Look up a palette by its key.
    static func palette(for key: ThemeKey) -> ThemePalette {
        switch key {
        case .neon:   return .neon
        case .pastel: return .pastel
        case .cyber:  return .cyber
        case .light:  return .light
        }
    }
}

// MARK: - Theme Manager

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private static let defaultsKey = "selectedThemeKey"

    @Published var key: ThemeKey {
        didSet {
            current = ThemePalette.palette(for: key)
            UserDefaults.standard.set(key.rawValue, forKey: Self.defaultsKey)
        }
    }

    @Published var current: ThemePalette

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        let initialKey = ThemeKey(rawValue: stored) ?? .neon
        self.key = initialKey
        self.current = ThemePalette.palette(for: initialKey)
    }
}

// MARK: - Legacy AppTheme Bridge
// Provides backward-compatible static accessors so existing views
// continue to compile while they are incrementally migrated.

enum AppTheme {
    private static var t: ThemePalette { ThemeManager.shared.current }

    // Colors (bridged from active palette)
    static var background:    Color { t.bgGradientStops.first ?? t.surface }
    static var surface:       Color { t.surface }
    static var surfaceHover:  Color { t.glassHighlight }
    static var textPrimary:   Color { t.textPrimary }
    static var textSecondary: Color { t.textSecondary }
    static var textDisabled:  Color { t.textTertiary }
    static var green:         Color { t.accent }
    static var cyan:          Color { t.tertiary }
    static var border:        Color { t.glassBorder }
    static var destructive:   Color { t.error }

    // MARK: Typography
    static let caption  = Font.system(size: 12, weight: .regular)
    static let body     = Font.system(size: 13, weight: .regular)
    static let label    = Font.system(size: 13, weight: .medium)
    static let heading  = Font.system(size: 15, weight: .semibold)
    static let title    = Font.system(size: 18, weight: .bold)
    static let mono     = Font.system(size: 12, design: .monospaced)

    // MARK: Spacing (8px grid)
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 24
    static let xxl: CGFloat = 32

    // MARK: Geometry
    static let cornerRadius:        CGFloat = 6
    static let sidebarWidth:        CGFloat = 60
    static let selectedAccentWidth: CGFloat = 3
}

// MARK: - Typography Tokens

enum AppTypo {
    static let caption  = Font.system(size: 12, weight: .regular)
    static let body     = Font.system(size: 13, weight: .regular)
    static let label    = Font.system(size: 13, weight: .medium)
    static let heading  = Font.system(size: 15, weight: .semibold)
    static let title    = Font.system(size: 18, weight: .bold)
    static let mono     = Font.system(size: 12, design: .monospaced)
}

// MARK: - Spacing Tokens

enum AppSpacing {
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 24
    static let xxl: CGFloat = 32
}

// MARK: - Color Extensions

extension Color {
    /// Create a Color from a hex string like "#00FF9F" or "00FF9F".
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >>  8) & 0xFF) / 255
        let b = Double( int        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// Create a Color from RGBA components (each 0-1).
    init(rgba r: Double, _ g: Double, _ b: Double, _ a: Double) {
        self.init(red: r, green: g, blue: b, opacity: a)
    }

    /// Adaptive color that switches between light and dark appearances.
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        }))
    }
}

// MARK: - Glass Background View Modifier

struct GlassBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        let theme = ThemeManager.shared.current
        content
            .background(
                theme.surface
            )
            .background(.ultraThinMaterial)
    }
}

extension View {
    /// Applies the surface background with a vibrancy blur behind it.
    func glassBackground() -> some View {
        modifier(GlassBackgroundModifier())
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let theme = ThemeManager.shared.current
        configuration.label
            .font(AppTheme.label)
            .foregroundColor(theme.isDark ? .white : .white)
            .padding(.horizontal, AppTheme.md)
            .padding(.vertical, AppTheme.sm)
            .background(theme.accent.opacity(configuration.isPressed ? 0.75 : 1))
            .cornerRadius(AppTheme.cornerRadius)
    }
}

struct RunButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let theme = ThemeManager.shared.current
        configuration.label
            .font(AppTheme.label)
            .foregroundColor(theme.isDark ? .black : .white)
            .padding(.horizontal, AppTheme.md)
            .padding(.vertical, AppTheme.sm)
            .background(theme.accent.opacity(configuration.isPressed ? 0.75 : 1))
            .cornerRadius(AppTheme.cornerRadius)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let theme = ThemeManager.shared.current
        configuration.label
            .font(AppTheme.label)
            .foregroundColor(theme.textPrimary)
            .padding(.horizontal, AppTheme.md)
            .padding(.vertical, AppTheme.sm)
            .background(theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(theme.glassBorder, lineWidth: 1)
            )
            .cornerRadius(AppTheme.cornerRadius)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let theme = ThemeManager.shared.current
        configuration.label
            .font(AppTheme.label)
            .foregroundColor(theme.error)
            .padding(.horizontal, AppTheme.md)
            .padding(.vertical, AppTheme.sm)
            .background(theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(theme.error, lineWidth: 1)
            )
            .cornerRadius(AppTheme.cornerRadius)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
