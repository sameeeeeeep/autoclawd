import Foundation
import SwiftUI

enum TranscriptionMode: String, CaseIterable {
    case groq  = "groq"
    case local = "local"

    var displayName: String {
        switch self {
        case .groq:  return "Groq (Fast, requires internet)"
        case .local: return "Local Whisper (Private, offline)"
        }
    }
}

enum AudioRetention: Int, CaseIterable {
    case threeDays   = 3
    case sevenDays   = 7
    case thirtyDays  = 30

    var displayName: String { "\(rawValue) days" }
}
enum AppearanceMode: String, CaseIterable {
    case frosted = "frosted"
    case solid   = "solid"

    var displayName: String {
        switch self {
        case .frosted: return "Frosted"
        case .solid:   return "Solid"
        }
    }
}

enum FontSizePreference: String, CaseIterable {
    case small  = "small"
    case medium = "medium"
    case large  = "large"

    var displayName: String {
        switch self {
        case .small:  return "Small"
        case .medium: return "Medium"
        case .large:  return "Large"
        }
    }

    /// Base size multiplier applied to system font sizes throughout the app.
    var scale: CGFloat {
        switch self {
        case .small:  return 0.85
        case .medium: return 1.0
        case .large:  return 1.2
        }
    }
}

// MARK: - Widget Appearance

/// Base colour tone for the floating widget shell and all tiles within it.
enum WidgetBase: String, CaseIterable {
    case dark  = "dark"
    case light = "light"
    var label: String { rawValue == "dark" ? "Dark" : "Light" }
}

/// How much the desktop bleeds through the widget glass.
enum WidgetStyle: String, CaseIterable {
    case solid       = "solid"
    case frosted     = "frosted"
    case transparent = "transparent"
    var label: String {
        switch self {
        case .solid:       return "Solid"
        case .frosted:     return "Frosted"
        case .transparent: return "Transparent"
        }
    }
}

enum ColorSchemeSetting: String, CaseIterable {
    case system = "system"
    case light  = "light"
    case dark   = "dark"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}


final class SettingsManager: @unchecked Sendable {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private let kTranscriptionMode = "transcription_mode"
    private let kAudioRetention    = "audio_retention_days"
    private let kMicEnabled        = "mic_enabled"
    private let kLogLevel          = "log_level"
    private let kGroqAPIKey        = "groq_api_key_storage"
    private let kShowAmbientWidget = "show_ambient_widget"
    private let kAppearanceMode  = "appearance_mode"
    private let kWidgetBase      = "widget_base"
    private let kWidgetStyle     = "widget_style"
    private let kHotWordConfigs = "hotWordConfigs"
    private let kColorScheme    = "color_scheme_setting"
    private let kShowToasts     = "show_toasts"
    private let kWhatsAppEnabled = "whatsapp_enabled"
    private let kWhatsAppNotifyTasks = "whatsapp_notify_tasks"
    private let kWhatsAppNotifySummaries = "whatsapp_notify_summaries"
    private let kWhatsAppMyJID = "whatsapp_my_jid"
    private let kFontSizePreference  = "font_size_preference"
    private let kAutonomousTaskRules = "autonomous_task_rules"
    private let kIsOllamaEnabled      = "is_ollama_enabled"
    private let kIsCodeExecEnabled    = "is_code_exec_enabled"
    private let kSpeakerMode          = "speaker_mode"
    private let kMusicModeEnabled     = "music_mode_enabled"

    // MARK: - Properties

    var transcriptionMode: TranscriptionMode {
        get {
            let raw = defaults.string(forKey: kTranscriptionMode) ?? TranscriptionMode.groq.rawValue
            return TranscriptionMode(rawValue: raw) ?? .groq
        }
        set { defaults.set(newValue.rawValue, forKey: kTranscriptionMode) }
    }

    var audioRetentionDays: Int {
        get {
            let v = defaults.integer(forKey: kAudioRetention)
            return v > 0 ? v : 7
        }
        set { defaults.set(newValue, forKey: kAudioRetention) }
    }

    /// Auto-synthesize after this many pending accepted items. 0 = off (manual only).
    var synthesizeThreshold: Int {
        get { UserDefaults.standard.integer(forKey: "synthesizeThreshold") == 0
              ? 10
              : UserDefaults.standard.integer(forKey: "synthesizeThreshold") }
        set { UserDefaults.standard.set(newValue, forKey: "synthesizeThreshold") }
    }

    var colorSchemeSetting: ColorSchemeSetting {
        get {
            let raw = defaults.string(forKey: kColorScheme) ?? ColorSchemeSetting.system.rawValue
            return ColorSchemeSetting(rawValue: raw) ?? .system
        }
        set { defaults.set(newValue.rawValue, forKey: kColorScheme) }
    }

    var micEnabled: Bool {
        get { defaults.object(forKey: kMicEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: kMicEnabled) }
    }

    var logLevel: LogLevel {
        get {
            let raw = defaults.string(forKey: kLogLevel) ?? LogLevel.info.rawValue
            return LogLevel(rawValue: raw) ?? .info
        }
        set { defaults.set(newValue.rawValue, forKey: kLogLevel) }
    }

    var groqAPIKey: String {
        get { AppSettingsStorage.load(account: kGroqAPIKey) ?? "" }
        set { AppSettingsStorage.save(newValue, account: kGroqAPIKey) }
    }

    private let kAnthropicAPIKey = "anthropic_api_key_storage"

    var anthropicAPIKey: String {
        get { AppSettingsStorage.load(account: kAnthropicAPIKey) ?? "" }
        set { AppSettingsStorage.save(newValue, account: kAnthropicAPIKey) }
    }

    var showAmbientWidget: Bool {
        get { defaults.object(forKey: kShowAmbientWidget) as? Bool ?? true }
        set { defaults.set(newValue, forKey: kShowAmbientWidget) }
    }

    var showToasts: Bool {
        get { defaults.object(forKey: kShowToasts) as? Bool ?? true }
        set { defaults.set(newValue, forKey: kShowToasts) }
    }

    var appearanceMode: AppearanceMode {
        get {
            let raw = defaults.string(forKey: kAppearanceMode) ?? AppearanceMode.frosted.rawValue
            return AppearanceMode(rawValue: raw) ?? .frosted
        }
        set { defaults.set(newValue.rawValue, forKey: kAppearanceMode) }
    }

    var widgetBase: WidgetBase {
        get {
            let raw = defaults.string(forKey: kWidgetBase) ?? WidgetBase.dark.rawValue
            return WidgetBase(rawValue: raw) ?? .dark
        }
        set { defaults.set(newValue.rawValue, forKey: kWidgetBase) }
    }

    var widgetStyle: WidgetStyle {
        get {
            let raw = defaults.string(forKey: kWidgetStyle) ?? WidgetStyle.frosted.rawValue
            return WidgetStyle(rawValue: raw) ?? .frosted
        }
        set { defaults.set(newValue.rawValue, forKey: kWidgetStyle) }
    }


    var hotWordConfigs: [HotWordConfig] {
        get {
            guard let data = defaults.data(forKey: kHotWordConfigs),
                  let configs = try? JSONDecoder().decode([HotWordConfig].self, from: data) else {
                return HotWordConfig.defaults
            }
            return configs
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else {
                assertionFailure("HotWordConfig encode failed — settings not saved")
                return
            }
            defaults.set(data, forKey: kHotWordConfigs)
        }
    }

    // MARK: - Font Size

    var fontSizePreference: FontSizePreference {
        get {
            let raw = defaults.string(forKey: kFontSizePreference) ?? FontSizePreference.medium.rawValue
            return FontSizePreference(rawValue: raw) ?? .medium
        }
        set { defaults.set(newValue.rawValue, forKey: kFontSizePreference) }
    }

    // MARK: - WhatsApp

    var whatsAppEnabled: Bool {
        get { defaults.object(forKey: kWhatsAppEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: kWhatsAppEnabled) }
    }

    var whatsAppNotifyTasks: Bool {
        get { defaults.object(forKey: kWhatsAppNotifyTasks) as? Bool ?? true }
        set { defaults.set(newValue, forKey: kWhatsAppNotifyTasks) }
    }

    var whatsAppNotifySummaries: Bool {
        get { defaults.object(forKey: kWhatsAppNotifySummaries) as? Bool ?? true }
        set { defaults.set(newValue, forKey: kWhatsAppNotifySummaries) }
    }

    var whatsAppMyJID: String {
        get { defaults.string(forKey: kWhatsAppMyJID) ?? "" }
        set { defaults.set(newValue, forKey: kWhatsAppMyJID) }
    }

    // MARK: - Autonomous Task Rules
    //
    // Plain-English descriptions of task categories that autoclawd can execute
    // autonomously without requiring user approval.  The analysis LLM receives
    // this list when it assigns task.mode — tasks matching a rule get `.auto`,
    // all others get `.ask`.
    //
    // Default: empty → nothing runs autonomously until the user configures rules.

    var autonomousTaskRules: [String] {
        get { defaults.stringArray(forKey: kAutonomousTaskRules) ?? [] }
        set { defaults.set(newValue, forKey: kAutonomousTaskRules) }
    }

    // MARK: - Pipeline Control

    /// Whether the local Ollama model (Llama 3.2B) runs analysis, task creation.
    /// When false, transcripts are still recorded and cleaned but Ollama stages are skipped.
    var isOllamaEnabled: Bool {
        get { defaults.object(forKey: kIsOllamaEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: kIsOllamaEnabled) }
    }

    /// Whether auto tasks are sent to Claude Code for execution.
    /// When false, tasks are created by Ollama but never executed — even .auto ones.
    var isCodeExecutionEnabled: Bool {
        get { defaults.object(forKey: kIsCodeExecEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: kIsCodeExecEnabled) }
    }

    // MARK: - Conversation Context

    /// "single" or "multiple" — how many speakers the pipeline should expect.
    var speakerMode: String {
        get { defaults.string(forKey: kSpeakerMode) ?? "single" }
        set { defaults.set(newValue, forKey: kSpeakerMode) }
    }

    /// Whether music is playing in the background (enables Shazam integration).
    var musicModeEnabled: Bool {
        get { defaults.object(forKey: kMusicModeEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: kMusicModeEnabled) }
    }

    private init() {}
}
