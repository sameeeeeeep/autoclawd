// Sources/AppTheme.swift
import AppKit
import SwiftUI

// MARK: - Font Scale Environment Key

private struct FontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    /// A multiplier (0.85 / 1.0 / 1.2) applied to system font sizes throughout the app.
    var fontScale: CGFloat {
        get { self[FontScaleKey.self] }
        set { self[FontScaleKey.self] = newValue }
    }
}

extension View {
    /// Injects the user's chosen font scale from AppState into the view hierarchy.
    func applyFontScale(_ scale: CGFloat) -> some View {
        environment(\.fontScale, scale)
    }
}

// MARK: - AppTheme

enum AppTheme {
    // Colors — all system-native
    static var background:    Color { Color(NSColor.windowBackgroundColor) }
    static var surface:       Color { Color(NSColor.controlBackgroundColor) }
    static var surfaceHover:  Color { Color(NSColor.controlAccentColor).opacity(0.08) }
    static var textPrimary:   Color { .primary }
    static var textSecondary: Color { .secondary }
    static var textDisabled:  Color { Color(NSColor.tertiaryLabelColor) }
    static var green:         Color { .green }
    static var cyan:          Color { .cyan }
    static var border:        Color { Color(NSColor.separatorColor) }
    static var destructive:   Color { .red }

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
    static let cornerRadius:        CGFloat = 8
    static let sidebarWidth:        CGFloat = 200
    static let selectedAccentWidth: CGFloat = 3
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.label)
            .foregroundColor(.white)
            .padding(.horizontal, AppTheme.md)
            .padding(.vertical, AppTheme.sm)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }
}

struct RunButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.label)
            .foregroundColor(.white)
            .padding(.horizontal, AppTheme.md)
            .padding(.vertical, AppTheme.sm)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.label)
            .foregroundColor(.primary)
            .padding(.horizontal, AppTheme.md)
            .padding(.vertical, AppTheme.sm)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.label)
            .foregroundColor(.red)
            .padding(.horizontal, AppTheme.md)
            .padding(.vertical, AppTheme.sm)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(Color.red.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
