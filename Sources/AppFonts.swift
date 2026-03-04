import CoreText
import Foundation

// MARK: - AppFonts
//
// Drop any .ttf / .otf files into Resources/fonts/ and rebuild.
// AppFonts.registerAll() is called once at startup (AppDelegate).
// It auto-detects the primary family name and a separate mono family
// (any family whose name contains "Mono", "Code", "Console", or "Nerd").
//
// AppTheme reads AppFonts.primaryFamily / .monoFamily and falls back
// to .system if no custom fonts are bundled.

enum AppFonts {

    /// Family name for the primary UI font (detected automatically from bundled fonts).
    /// nil  →  fall back to SF Pro (system default).
    private(set) static var primaryFamily: String? = nil

    /// Family name for monospaced text. Falls back to primaryFamily, then to SF Mono.
    private(set) static var monoFamily: String? = nil

    // MARK: - Registration

    /// Scans `fonts/` inside the app bundle, registers every .ttf / .otf file,
    /// and auto-detects primaryFamily / monoFamily from the registered descriptors.
    /// Call once in AppDelegate.applicationDidFinishLaunching — before any views render.
    static func registerAll() {
        guard let fontsURL = Bundle.main.resourceURL?.appendingPathComponent("fonts") else {
            Log.info(.system, "AppFonts: no fonts/ directory in bundle — using system fonts")
            return
        }

        let candidates = (try? FileManager.default.contentsOfDirectory(
            at: fontsURL, includingPropertiesForKeys: nil
        )) ?? []

        var detected: [String] = []

        for url in candidates where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            var cfError: Unmanaged<CFError>?
            let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &cfError)
            if !ok, let err = cfError?.takeUnretainedValue() {
                Log.warn(.system, "AppFonts: failed to register \(url.lastPathComponent): \(err)")
                continue
            }

            // Extract family name from the font descriptor
            let attrs = [kCTFontURLAttribute as String: url] as CFDictionary
            let desc = CTFontDescriptorCreateWithAttributes(attrs)
            if let family = CTFontDescriptorCopyAttribute(desc, kCTFontFamilyNameAttribute) as? String {
                if !detected.contains(family) { detected.append(family) }
                Log.info(.system, "AppFonts: registered '\(family)' from \(url.lastPathComponent)")
            }
        }

        // Classify each family as mono or primary
        for family in detected {
            let lower = family.lowercased()
            let isMono = lower.contains("mono") || lower.contains("code")
                      || lower.contains("console") || lower.contains("nerd")
            if isMono {
                if monoFamily == nil { monoFamily = family }
            } else {
                if primaryFamily == nil { primaryFamily = family }
            }
        }

        // If only one family was found, use it for both
        if primaryFamily == nil, let m = monoFamily { primaryFamily = m }
        if monoFamily == nil, let p = primaryFamily { monoFamily = p }

        if let p = primaryFamily, let m = monoFamily {
            Log.info(.system, "AppFonts: primary='\(p)'  mono='\(m)'")
        } else {
            Log.info(.system, "AppFonts: no custom fonts found — using system defaults")
        }
    }
}
