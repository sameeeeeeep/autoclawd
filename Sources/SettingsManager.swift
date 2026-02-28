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
    private let kAppearanceMode = "appearance_mode"
    private let kHotWordConfigs = "hotWordConfigs"
    private let kColorScheme    = "color_scheme_setting"
    private let kShowToasts     = "show_toasts"
    private let kWhatsAppEnabled = "whatsapp_enabled"
    private let kWhatsAppNotifyTasks = "whatsapp_notify_tasks"
    private let kWhatsAppNotifySummaries = "whatsapp_notify_summaries"
    private let kWhatsAppMyJID = "whatsapp_my_jid"

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

    private init() {}
}
