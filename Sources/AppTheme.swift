// Sources/AppTheme.swift
import SwiftUI

// MARK: - App Design Tokens

enum AppTheme {
    // MARK: Colors
    static let background    = Color(hex: "#FFFFFF")
    static let surface       = Color(hex: "#F7F7F7")
    static let surfaceHover  = Color(hex: "#EBEBEB")
    static let textPrimary   = Color(hex: "#0A0A0A")
    static let textSecondary = Color(hex: "#6B6B6B")
    static let green         = Color(hex: "#16C172")
    static let cyan          = Color(hex: "#06B6D4")
    static let border        = Color(hex: "#E4E4E4")
    static let destructive   = Color(hex: "#EF4444")

    // MARK: Typography
    static let caption  = Font.system(size: 11, weight: .regular)
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
    static let sidebarWidth:        CGFloat = 52
    static let selectedAccentWidth: CGFloat = 3
}

// MARK: - Color Hex Init

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >>  8) & 0xFF) / 255
        let b = Double( int        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.label)
            .foregroundColor(.white)
            .padding(.horizontal, AppTheme.md)
            .padding(.vertical, AppTheme.sm)
            .background(AppTheme.textPrimary.opacity(configuration.isPressed ? 0.75 : 1))
            .cornerRadius(AppTheme.cornerRadius)
    }
}

struct RunButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.label)
            .foregroundColor(AppTheme.textPrimary)
            .padding(.horizontal, AppTheme.md)
            .padding(.vertical, AppTheme.sm)
            .background(AppTheme.green.opacity(configuration.isPressed ? 0.75 : 1))
            .cornerRadius(AppTheme.cornerRadius)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.label)
            .foregroundColor(AppTheme.textPrimary)
            .padding(.horizontal, AppTheme.md)
            .padding(.vertical, AppTheme.sm)
            .background(Color.white)
            .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                        .stroke(AppTheme.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.label)
            .foregroundColor(AppTheme.destructive)
            .padding(.horizontal, AppTheme.md)
            .padding(.vertical, AppTheme.sm)
            .background(Color.white)
            .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                        .stroke(AppTheme.destructive, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
