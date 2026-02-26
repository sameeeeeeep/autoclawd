import Foundation

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
    case frosted     = "frosted"
    case transparent = "transparent"
    case dynamic     = "dynamic"

    var displayName: String {
        switch self {
        case .frosted:     return "Frosted"
        case .transparent: return "Transparent"
        case .dynamic:     return "Dynamic"
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

    private init() {}
}
