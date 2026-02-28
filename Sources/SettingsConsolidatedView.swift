import AVFoundation
import SwiftUI

// MARK: - Settings Section Enum

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case models
    case projects
    case people
    case skills
    case connections
    case appearance
    case widget

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general:     return "\u{2699}"
        case .models:      return "\u{1F9E0}"
        case .projects:    return "\u{1F4C1}"
        case .people:      return "\u{1F465}"
        case .skills:      return "\u{1F527}"
        case .connections: return "\u{1F517}"
        case .appearance:  return "\u{1F3A8}"
        case .widget:      return "\u{1F4F1}"
        }
    }

    var label: String {
        switch self {
        case .general:     return "General"
        case .models:      return "Models"
        case .projects:    return "Projects"
        case .people:      return "People"
        case .skills:      return "Skills"
        case .connections: return "Connections"
        case .appearance:  return "Appearance"
        case .widget:      return "Widget"
        }
    }
}

// MARK: - SettingsConsolidatedView

struct SettingsConsolidatedView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var themeManager = ThemeManager.shared

    @State private var selectedSection: SettingsSection = .general

    // General mock state (items not yet backed by real persistence)
    @State private var autoStart = true
    // notificationsEnabled is now backed by appState.showToasts

    // Hot words local state (synced to SettingsManager)
    @State private var localHotWordConfigs: [HotWordConfig] = SettingsManager.shared.hotWordConfigs
    @State private var showAddHotWord = false

    // API key local state (synced to Keychain via SettingsManager)
    @State private var groqKey: String = ""
    @State private var anthropicKey: String = SettingsManager.shared.anthropicAPIKey
    @State private var isValidatingGroq = false
    @State private var groqValidationResult: Bool? = nil

    // Connections state — TODO: wire to real connection system when built
    @State private var connections: [ConnectionItem] = [
        ConnectionItem(icon: "\u{1F916}", name: "Claude Code CLI", connected: false),
        ConnectionItem(icon: "\u{1F4C5}", name: "Google Calendar", connected: false),
        ConnectionItem(icon: "\u{1F4E7}", name: "Gmail", connected: false),
        ConnectionItem(icon: "\u{1F4AC}", name: "Slack", connected: false),
        ConnectionItem(icon: "\u{1F4DD}", name: "Notion", connected: false),
        ConnectionItem(icon: "\u{1F419}", name: "GitHub", connected: false),
    ]

    // Widget mock state
    @State private var showWaveform = true
    @State private var showRecentTranscripts = true

    // Projects sheet
    @State private var showAddProject = false

    // People
    @State private var newPersonName = ""

    // Audio devices
    @State private var audioDevices: [AVCaptureDevice] = []
    @State private var selectedAudioDeviceID: String = ""

    var body: some View {
        let theme = themeManager.current
        let isDark = theme.isDark

        GeometryReader { geo in
            let showSidebarInline = geo.size.width >= 450

            VStack(spacing: 0) {
                // Compact mode: horizontal scrollable picker at top
                if !showSidebarInline {
                    compactSettingsNav
                }

                HStack(spacing: 0) {
                    // MARK: Left Nav (shown inline when wide enough)
                    if showSidebarInline {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(SettingsSection.allCases) { section in
                                let isActive = selectedSection == section
                                Button {
                                    selectedSection = section
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(section.icon)
                                            .font(.system(size: 11))
                                        Text(section.label)
                                            .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                                            .foregroundColor(isActive ? theme.textPrimary : theme.textSecondary)
                                    }
                                    .padding(.vertical, 7)
                                    .padding(.horizontal, 9)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(isActive ? theme.accent.opacity(0.08) : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                        }
                        .frame(minWidth: 110, idealWidth: 150, maxWidth: 190)
                        .padding(.top, 12)
                        .padding(.horizontal, 8)

                        // Divider
                        Rectangle()
                            .fill(theme.glassBorder)
                            .frame(width: 0.5)
                    }

            // MARK: Content Area
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch selectedSection {
                    case .general:     generalSection(theme: theme, isDark: isDark)
                    case .models:      modelsSection(theme: theme, isDark: isDark)
                    case .projects:    projectsSection(theme: theme, isDark: isDark)
                    case .people:      peopleSection(theme: theme, isDark: isDark)
                    case .skills:      skillsSection(theme: theme, isDark: isDark)
                    case .connections: connectionsSection(theme: theme, isDark: isDark)
                    case .appearance:  appearanceSection(theme: theme, isDark: isDark)
                    case .widget:      widgetSection(theme: theme, isDark: isDark)
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
                } // end HStack
            } // end VStack
        } // end GeometryReader
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showAddProject) {
            AddProjectSheet(isPresented: $showAddProject) { name, path in
                appState.addProject(name: name, path: path)
            }
        }
        .sheet(isPresented: $showAddHotWord) {
            AddHotWordSheet(configs: Binding(
                get: { localHotWordConfigs },
                set: {
                    localHotWordConfigs = $0
                    SettingsManager.shared.hotWordConfigs = $0
                }
            ))
        }
        .onAppear {
            groqKey = appState.groqAPIKey
            anthropicKey = SettingsManager.shared.anthropicAPIKey
            localHotWordConfigs = SettingsManager.shared.hotWordConfigs
            refreshAudioDevices()
            checkClaudeCodeCLI()
        }
    }

    // MARK: - Compact Settings Nav (horizontal scrollable picker)

    private var compactSettingsNav: some View {
        let theme = themeManager.current
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(SettingsSection.allCases) { section in
                    let isActive = selectedSection == section
                    Button {
                        selectedSection = section
                    } label: {
                        HStack(spacing: 4) {
                            Text(section.icon)
                                .font(.system(size: 10))
                            Text(section.label)
                                .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                                .foregroundColor(isActive ? theme.accent : theme.textSecondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isActive ? theme.accent.opacity(0.12) : Color.clear)
                        )
                        .overlay(
                            Capsule()
                                .stroke(isActive ? theme.accent.opacity(0.3) : theme.glassBorder, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .overlay(
            Rectangle()
                .fill(theme.glassBorder)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - General Section

    @ViewBuilder
    private func generalSection(theme: ThemePalette, isDark: Bool) -> some View {
        settingsRow(theme: theme, isDark: isDark, label: "Auto-start", description: "Launch on login") {
            settingsToggle(isOn: $autoStart, theme: theme)
        }
        settingsRow(theme: theme, isDark: isDark, label: "Always-on listening") {
            settingsToggle(isOn: $appState.micEnabled, theme: theme)
        }
        settingsRow(theme: theme, isDark: isDark, label: "Transcription engine") {
            settingsDropdown(
                selectedValue: appState.transcriptionMode.displayName,
                theme: theme,
                isDark: isDark
            ) {
                ForEach(TranscriptionMode.allCases, id: \.self) { mode in
                    Button(mode.displayName) {
                        appState.transcriptionMode = mode
                    }
                }
            }
        }

        // Audio input device picker
        settingsRow(theme: theme, isDark: isDark, label: "Audio input", description: "Microphone device") {
            settingsDropdown(
                selectedValue: audioDevices.first(where: { $0.uniqueID == selectedAudioDeviceID })?.localizedName
                    ?? (AVCaptureDevice.default(for: .audio)?.localizedName ?? "Default"),
                theme: theme,
                isDark: isDark
            ) {
                Button("System Default") { selectedAudioDeviceID = "" }
                Divider()
                ForEach(audioDevices, id: \.uniqueID) { device in
                    Button(device.localizedName) {
                        selectedAudioDeviceID = device.uniqueID
                    }
                }
            }
        }

        // Audio retention
        settingsRow(theme: theme, isDark: isDark, label: "Delete audio after", description: "Retention period for raw audio") {
            settingsDropdown(
                selectedValue: "\(appState.audioRetentionDays) days",
                theme: theme,
                isDark: isDark
            ) {
                ForEach(AudioRetention.allCases, id: \.rawValue) { r in
                    Button(r.displayName) {
                        appState.audioRetentionDays = r.rawValue
                    }
                }
            }
        }

        // Hot Words — real binding to SettingsManager.shared.hotWordConfigs
        sectionLabel("HOT WORDS", theme: theme)
            .padding(.top, 8)

        VStack(spacing: 6) {
            ForEach(localHotWordConfigs) { config in
                HStack(spacing: 8) {
                    Text("hot \(config.keyword)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(theme.accent)

                    Text("\u{2192} \(config.action.displayName)")
                        .font(.system(size: 9))
                        .foregroundColor(theme.textTertiary)

                    if config.action == .executeImmediately && config.skipPermissions {
                        Text("\u{26A1}")
                            .font(.system(size: 9))
                    }

                    Spacer()

                    Button {
                        localHotWordConfigs.removeAll { $0.id == config.id }
                        SettingsManager.shared.hotWordConfigs = localHotWordConfigs
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundColor(theme.error)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.glass)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.glassBorder, lineWidth: 0.5)
                )
            }

            Button { showAddHotWord = true } label: {
                HStack {
                    Spacer()
                    Text("+ Add Hot Word")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.textTertiary)
                    Spacer()
                }
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .foregroundColor(theme.textTertiary.opacity(0.4))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 4)

        settingsRow(theme: theme, isDark: isDark, label: "Language") {
            settingsDropdown(selectedValue: "English + Hindi", theme: theme, isDark: isDark) {
                Text("English + Hindi").tag("en_hi")
            }
        }
        settingsRow(theme: theme, isDark: isDark, label: "Notifications", showBorder: false) {
            settingsToggle(isOn: $appState.showToasts, theme: theme)
        }

        // Data management
        sectionLabel("DATA", theme: theme)
            .padding(.top, 8)

        HStack(spacing: 8) {
            Button("Re-run Setup") { appState.showSetup() }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.glass)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(theme.glassBorder, lineWidth: 0.5)
                )
                .buttonStyle(.plain)

            Button("Export All") { appState.exportData() }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.glass)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(theme.glassBorder, lineWidth: 0.5)
                )
                .buttonStyle(.plain)

            Button("Delete All") { appState.confirmDeleteAll() }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(theme.error)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.glass)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(theme.error.opacity(0.3), lineWidth: 0.5)
                )
                .buttonStyle(.plain)
        }
    }

    // MARK: - Models Section

    @ViewBuilder
    private func modelsSection(theme: ThemePalette, isDark: Bool) -> some View {

        // API Keys subsection
        sectionLabel("API KEYS", theme: theme)

        VStack(alignment: .leading, spacing: 10) {
            // Anthropic API Key
            VStack(alignment: .leading, spacing: 4) {
                Text("Anthropic API Key")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(theme.textSecondary)
                SecureField("sk-ant-...", text: $anthropicKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))
                    .onChange(of: anthropicKey) { _ in
                        SettingsManager.shared.anthropicAPIKey = anthropicKey
                    }
            }

            // Groq API Key (shown when groq transcription mode selected)
            VStack(alignment: .leading, spacing: 4) {
                Text("Groq API Key")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(theme.textSecondary)
                HStack(spacing: 6) {
                    SecureField("gsk_...", text: $groqKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10))
                        .onChange(of: groqKey) { _ in
                            appState.groqAPIKey = groqKey
                            groqValidationResult = nil
                        }

                    Button(isValidatingGroq ? "..." : "Validate") {
                        validateGroqKey()
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(theme.glass)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(theme.glassBorder, lineWidth: 0.5)
                    )
                    .buttonStyle(.plain)
                    .disabled(isValidatingGroq || groqKey.isEmpty)

                    if let result = groqValidationResult {
                        Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(result ? theme.accent : theme.error)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(theme.glass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(theme.glassBorder, lineWidth: 0.5)
        )
        .padding(.bottom, 8)

        // Model assignments subsection
        sectionLabel("MODEL ASSIGNMENTS", theme: theme)
            .padding(.top, 4)

        settingsRow(theme: theme, isDark: isDark, label: "Transcription") {
            settingsDropdown(selectedValue: "Groq Whisper V3", theme: theme, isDark: isDark) {
                Button("Groq Whisper V3") {}
                Button("Local Whisper") {}
            }
        }
        settingsRow(theme: theme, isDark: isDark, label: "Cleaning", description: "Coming soon") {
            Text("Claude Haiku 4.5")
                .font(.system(size: 10))
                .foregroundColor(theme.textTertiary)
        }
        settingsRow(theme: theme, isDark: isDark, label: "Analysis", description: "Coming soon") {
            Text("Claude Sonnet 4.5")
                .font(.system(size: 10))
                .foregroundColor(theme.textTertiary)
        }
        settingsRow(theme: theme, isDark: isDark, label: "Execution", description: "Coming soon") {
            Text("Claude Code CLI")
                .font(.system(size: 10))
                .foregroundColor(theme.textTertiary)
        }
        settingsRow(theme: theme, isDark: isDark, label: "Auto-approve", description: "Auto-synthesize after N pending items", showBorder: false) {
            settingsDropdown(
                selectedValue: appState.synthesizeThreshold > 0
                    ? "Auto: \(appState.synthesizeThreshold)"
                    : "Manual",
                theme: theme,
                isDark: isDark
            ) {
                Button("Auto: 5") { appState.synthesizeThreshold = 5 }
                Button("Auto: 10") { appState.synthesizeThreshold = 10 }
                Button("Auto: 20") { appState.synthesizeThreshold = 20 }
                Button("Manual") { appState.synthesizeThreshold = 0 }
            }
        }
    }

    // MARK: - Projects Section

    @ViewBuilder
    private func projectsSection(theme: ThemePalette, isDark: Bool) -> some View {
        let dotColors = [theme.accent, theme.tertiary, theme.secondary]
        VStack(spacing: 8) {
            ForEach(Array(appState.projects.enumerated()), id: \.element.id) { index, project in
                projectCard(
                    project: project,
                    dotColor: dotColors[index % dotColors.count],
                    theme: theme,
                    isDark: isDark
                )
            }

            // Add Project button
            Button { showAddProject = true } label: {
                HStack {
                    Spacer()
                    Text("+ Add Project")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.textTertiary)
                    Spacer()
                }
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .foregroundColor(theme.textTertiary.opacity(0.4))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func projectCard(project: Project, dotColor: Color, theme: ThemePalette, isDark: Bool) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                Text(project.localPath)
                    .font(.system(size: 9))
                    .foregroundColor(theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()

            Button {
                appState.deleteProject(id: project.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 9))
                    .foregroundColor(theme.error)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(theme.glass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(theme.glassBorder, lineWidth: 0.5)
        )
    }

    // MARK: - People Section

    @ViewBuilder
    private func peopleSection(theme: ThemePalette, isDark: Bool) -> some View {
        VStack(spacing: 8) {
            ForEach(appState.people) { person in
                HStack(spacing: 10) {
                    Circle()
                        .fill(person.color)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(person.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(theme.textPrimary)
                            if person.isMe {
                                Text("(you)")
                                    .font(.system(size: 9))
                                    .foregroundColor(theme.accent)
                            }
                            if person.isMusic {
                                Text("(music)")
                                    .font(.system(size: 9))
                                    .foregroundColor(theme.secondary)
                            }
                        }
                        Text("Color: \(person.personColor)")
                            .font(.system(size: 9))
                            .foregroundColor(theme.textTertiary)
                    }

                    Spacer()

                    // Don't allow deleting "Me" or "Music" special persons
                    if !person.isMe && !person.isMusic {
                        Button {
                            appState.people.removeAll { $0.id == person.id }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 9))
                                .foregroundColor(theme.error)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(theme.glass)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(theme.glassBorder, lineWidth: 0.5)
                )
            }

            // Add Person
            HStack(spacing: 6) {
                TextField("New person name", text: $newPersonName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))

                Button {
                    let name = newPersonName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    appState.addPerson(name: name)
                    newPersonName = ""
                } label: {
                    Text("+ Add")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(theme.accent.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(theme.accent.opacity(0.3), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .disabled(newPersonName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 4)

            // Note about world view
            HStack(spacing: 6) {
                Text("\u{1F4CD}")
                    .font(.system(size: 10))
                Text("Drag people on the World map to set their spatial position")
                    .font(.system(size: 9))
                    .foregroundColor(theme.textTertiary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.glass)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.glassBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Skills Section

    @ViewBuilder
    private func skillsSection(theme: ThemePalette, isDark: Bool) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text("\u{1F527}")
                .font(.system(size: 28))
            Text("Skills — Coming Soon")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.textPrimary)
            Text("MCP-based skills like web browsing, file management, and calendar integration will be available in a future update.")
                .font(.system(size: 10))
                .foregroundColor(theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Connections Section

    @ViewBuilder
    private func connectionsSection(theme: ThemePalette, isDark: Bool) -> some View {
        VStack(spacing: 12) {
            // ── WhatsApp Connection ──────────────────────────────────
            WhatsAppConnectionCard(appState: appState, theme: theme, isDark: isDark)

            // ── Other Connections ────────────────────────────────────
            ForEach($connections) { $conn in
                let isCC = conn.name == "Claude Code CLI"
                HStack(spacing: 10) {
                    Text(conn.icon)
                        .font(.system(size: 14))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(conn.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(theme.textPrimary)
                        if isCC {
                            Text(conn.connected ? "Connected" : "Not connected")
                                .font(.system(size: 9))
                                .foregroundColor(conn.connected ? theme.accent : theme.textTertiary)
                        } else {
                            Text("Coming Soon")
                                .font(.system(size: 9))
                                .foregroundColor(theme.textTertiary)
                        }
                    }

                    Spacer()

                    if isCC {
                        Button(conn.connected ? "Manage" : "Connect") {
                            // Claude Code CLI connection action
                        }
                        .font(.system(size: 9))
                        .foregroundColor(theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(theme.glass)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(theme.glassBorder, lineWidth: 0.5)
                        )
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(theme.glass)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(theme.glassBorder, lineWidth: 0.5)
                )
                .opacity(isCC ? 1.0 : 0.45)
            }
        }
    }

    // MARK: - Appearance Section

    @ViewBuilder
    private func appearanceSection(theme: ThemePalette, isDark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {

            // 1. Mode Toggle (Light / Dark)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mode")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                    Text("Switch between light and dark interface")
                        .font(.system(size: 9))
                        .foregroundColor(theme.textTertiary)
                }
                Spacer()
                HStack(spacing: 0) {
                    let isLight = themeManager.key == .light
                    Button {
                        themeManager.key = .light
                    } label: {
                        HStack(spacing: 4) {
                            Text("\u{2600}\u{FE0F}")
                                .font(.system(size: 10))
                            Text("Light")
                                .font(.system(size: 10, weight: isLight ? .semibold : .regular))
                        }
                        .foregroundColor(isLight ? theme.textPrimary : theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isLight ? theme.accent.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        if themeManager.key == .light {
                            themeManager.key = .neon
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\u{1F319}")
                                .font(.system(size: 10))
                            Text("Dark")
                                .font(.system(size: 10, weight: !isLight ? .semibold : .regular))
                        }
                        .foregroundColor(!isLight ? theme.textPrimary : theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(!isLight ? theme.accent.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(theme.glassBorder, lineWidth: 0.5)
                )
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.glass)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.glassBorder, lineWidth: 0.5)
            )

            // Pill appearance mode (frosted / transparent / dynamic)
            sectionLabel("PILL APPEARANCE", theme: theme)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pill style")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                    Text("Visual style of the floating pill")
                        .font(.system(size: 9))
                        .foregroundColor(theme.textTertiary)
                }
                Spacer()
                settingsDropdown(
                    selectedValue: appState.appearanceMode.displayName,
                    theme: theme,
                    isDark: isDark
                ) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Button(mode.displayName) {
                            appState.appearanceMode = mode
                        }
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.glass)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.glassBorder, lineWidth: 0.5)
            )

            // 2. Color Palette section (only visible when dark)
            if isDark {
                sectionLabel("COLOR PALETTE", theme: theme)

                VStack(spacing: 8) {
                    paletteCard(key: .neon, palette: .neon, theme: theme, isDark: isDark)
                    paletteCard(key: .pastel, palette: .pastel, theme: theme, isDark: isDark)
                    paletteCard(key: .cyber, palette: .cyber, theme: theme, isDark: isDark)
                }
            }

            // 3. Custom Theme section
            sectionLabel("CUSTOM", theme: theme)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("\u{1F3A8}")
                        .font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Create Custom Theme")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(theme.textPrimary)
                        Text("Design your own color palette")
                            .font(.system(size: 9))
                            .foregroundColor(theme.textTertiary)
                    }
                }

                // Voice command suggestion box
                VStack(alignment: .leading, spacing: 6) {
                    Text("TRY SAYING:")
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(theme.textTertiary)

                    HStack(spacing: 6) {
                        Text("\u{1F399}")
                            .font(.system(size: 10))
                        Text("\"DOT p0 for autoclawd add appearance theme monotone\"")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(theme.accent)
                    }

                    Text("Use voice commands to create themes hands-free")
                        .font(.system(size: 9))
                        .foregroundColor(theme.textTertiary)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.glass)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.glassBorder, lineWidth: 0.5)
                )

                // Create Manually button
                Button {} label: {
                    HStack {
                        Spacer()
                        Text("+ Create Manually")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(theme.accent)
                        Spacer()
                    }
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(theme.accent.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(theme.accent.opacity(0.3), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundColor(theme.textTertiary.opacity(0.3))
            )
        }
    }

    private func paletteCard(key: ThemeKey, palette: ThemePalette, theme: ThemePalette, isDark: Bool) -> some View {
        let isActive = themeManager.key == key

        return Button {
            themeManager.key = key
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(key.displayName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(theme.textPrimary)
                    Spacer()
                    if isActive {
                        Text("Active")
                            .font(.system(size: 8, weight: .semibold))
                            .tracking(0.3)
                            .foregroundColor(theme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(theme.accent.opacity(0.12))
                            )
                    }
                }

                // Color swatches
                HStack(spacing: 6) {
                    colorSwatch(palette.accent)
                    colorSwatch(palette.secondary)
                    colorSwatch(palette.tertiary)
                    colorSwatch(palette.warning)
                    colorSwatch(palette.error)
                }

                // Tag previews
                HStack(spacing: 6) {
                    TagView(type: .project, label: "Project", small: true)
                    TagView(type: .person, label: "Person", small: true)
                    TagView(type: .action, label: "Action", small: true)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(palette.glass.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isActive ? theme.accent : theme.glassBorder,
                        lineWidth: isActive ? 1.5 : 0.5
                    )
            )
            .shadow(
                color: isActive ? theme.accent.opacity(0.15) : .clear,
                radius: 8,
                x: 0,
                y: 2
            )
        }
        .buttonStyle(.plain)
    }

    private func colorSwatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(width: 18, height: 18)
    }

    // MARK: - Widget Section

    @ViewBuilder
    private func widgetSection(theme: ThemePalette, isDark: Bool) -> some View {
        settingsRow(theme: theme, isDark: isDark, label: "Show in menu bar") {
            settingsToggle(isOn: $appState.showAmbientWidget, theme: theme)
        }
        settingsRow(theme: theme, isDark: isDark, label: "Show waveform") {
            settingsToggle(isOn: $showWaveform, theme: theme)
        }
        settingsRow(theme: theme, isDark: isDark, label: "Recent transcripts") {
            settingsToggle(isOn: $showRecentTranscripts, theme: theme)
        }
        settingsRow(theme: theme, isDark: isDark, label: "Widget theme", showBorder: false) {
            settingsDropdown(selectedValue: "Glassmorphic", theme: theme, isDark: isDark) {
                Button("Glassmorphic") {}
                Button("Minimal") {}
                Button("Solid") {}
            }
        }
    }

    // MARK: - Reusable Components

    /// Standard settings row with label, optional description, and trailing control.
    private func settingsRow<Control: View>(
        theme: ThemePalette,
        isDark: Bool,
        label: String,
        description: String? = nil,
        showBorder: Bool = true,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                    if let description {
                        Text(description)
                            .font(.system(size: 9))
                            .foregroundColor(theme.textTertiary)
                    }
                }
                Spacer()
                control()
            }
            .padding(.vertical, 11)

            if showBorder {
                Rectangle()
                    .fill(isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.04))
                    .frame(height: 0.5)
            }
        }
    }

    /// Glassmorphic dropdown menu.
    private func settingsDropdown<MenuContent: View>(
        selectedValue: String,
        theme: ThemePalette,
        isDark: Bool,
        @ViewBuilder content: () -> MenuContent
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Text(selectedValue)
                    .font(.system(size: 10))
                    .foregroundColor(theme.textSecondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7))
                    .foregroundColor(theme.textTertiary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(theme.glassBorder, lineWidth: 0.5)
            )
        }
    }

    /// Custom toggle matching v2.0 wireframe: 36x20pt rounded rect.
    private func settingsToggle(isOn: Binding<Bool>, theme: ThemePalette) -> some View {
        SettingsCustomToggle(isOn: isOn, theme: theme)
    }

    /// Section label (uppercase, 10pt, semibold, letter-spaced).
    private func sectionLabel(_ title: String, theme: ThemePalette) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundColor(theme.textSecondary)
            .padding(.top, 4)
    }

    // MARK: - Private Helpers

    private func validateGroqKey() {
        isValidatingGroq = true
        Task {
            let result = await TranscriptionService.validateAPIKey(groqKey)
            await MainActor.run {
                groqValidationResult = result
                isValidatingGroq = false
            }
        }
    }

    private func refreshAudioDevices() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        audioDevices = discoverySession.devices
    }

    private func checkClaudeCodeCLI() {
        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = ["claude"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let found = process.terminationStatus == 0
                await MainActor.run {
                    if let idx = connections.firstIndex(where: { $0.name == "Claude Code CLI" }) {
                        connections[idx].connected = found
                    }
                }
            } catch {
                // which not available or failed — leave as disconnected
            }
        }
    }
}

// MARK: - Custom Toggle

struct SettingsCustomToggle: View {
    @Binding var isOn: Bool
    let theme: ThemePalette

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isOn ? theme.accent : (theme.isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)))
                    .frame(width: 36, height: 20)

                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .padding(2)
                    .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - WhatsApp Connection Card

struct WhatsAppConnectionCard: View {
    @ObservedObject var appState: AppState
    let theme: ThemePalette
    let isDark: Bool

    @State private var qrImage: String? = nil // base64 data URL
    @State private var isConnecting = false
    @State private var pollTimer: Timer? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Text("\u{1F4F2}")
                    .font(.system(size: 14))

                VStack(alignment: .leading, spacing: 2) {
                    Text("WhatsApp")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                    Text(statusText)
                        .font(.system(size: 9))
                        .foregroundColor(statusColor)
                }

                Spacer()

                if case .connected = appState.whatsAppStatus {
                    Button("Disconnect") {
                        Task { await disconnect() }
                    }
                    .font(.system(size: 9))
                    .foregroundColor(.red.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.glass)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(theme.glassBorder, lineWidth: 0.5)
                    )
                    .buttonStyle(.plain)
                } else if case .waitingForQR = appState.whatsAppStatus {
                    // QR is showing, no button needed
                } else {
                    Button(isConnecting ? "Connecting..." : "Connect") {
                        Task { await startConnection() }
                    }
                    .font(.system(size: 9))
                    .foregroundColor(theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.glass)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(theme.glassBorder, lineWidth: 0.5)
                    )
                    .buttonStyle(.plain)
                    .disabled(isConnecting)
                }
            }

            // QR Code display
            if case .waitingForQR = appState.whatsAppStatus, let qr = qrImage {
                VStack(spacing: 8) {
                    // Parse the data URL and display image
                    if let imageData = dataFromBase64URL(qr),
                       let nsImage = NSImage(data: imageData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 180, height: 180)
                            .background(Color.white)
                            .cornerRadius(8)
                    }

                    Text("Scan with WhatsApp")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(theme.textSecondary)
                    Text("Open WhatsApp \u{2192} Settings \u{2192} Linked Devices \u{2192} Link a Device")
                        .font(.system(size: 8))
                        .foregroundColor(theme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // Connected state — notification settings
            if case .connected = appState.whatsAppStatus {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                        .background(theme.glassBorder)

                    Toggle(isOn: Binding(
                        get: { SettingsManager.shared.whatsAppNotifyTasks },
                        set: { SettingsManager.shared.whatsAppNotifyTasks = $0 }
                    )) {
                        Text("Task update notifications")
                            .font(.system(size: 10))
                            .foregroundColor(theme.textSecondary)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                    Toggle(isOn: Binding(
                        get: { SettingsManager.shared.whatsAppNotifySummaries },
                        set: { SettingsManager.shared.whatsAppNotifySummaries = $0 }
                    )) {
                        Text("Daily summary notifications")
                            .font(.system(size: 10))
                            .foregroundColor(theme.textSecondary)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(theme.glass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    appState.whatsAppStatus == .connected
                        ? theme.accent.opacity(0.3)
                        : theme.glassBorder,
                    lineWidth: appState.whatsAppStatus == .connected ? 1 : 0.5
                )
        )
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    // MARK: - Helpers

    private var statusText: String {
        switch appState.whatsAppStatus {
        case .disconnected: return "Not connected"
        case .connecting:   return "Connecting..."
        case .waitingForQR: return "Scan QR code to link"
        case .connected:    return "Connected"
        }
    }

    private var statusColor: Color {
        switch appState.whatsAppStatus {
        case .connected:    return theme.accent
        case .waitingForQR: return .orange
        case .connecting:   return .yellow
        case .disconnected: return theme.textTertiary
        }
    }

    private func startConnection() async {
        isConnecting = true

        // Start sidecar if not running
        if !WhatsAppSidecar.shared.running {
            WhatsAppSidecar.shared.start()
            // Wait a moment for sidecar to start
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        // Tell sidecar to connect
        do {
            try await WhatsAppService.shared.connect()
        } catch {
            Log.warn(.system, "[WhatsApp] Connection failed: \(error)")
        }

        isConnecting = false

        // Start polling for QR code and status updates
        startStatusPolling()
    }

    private func disconnect() async {
        pollTimer?.invalidate()
        pollTimer = nil
        do {
            try await WhatsAppService.shared.disconnect(clearAuth: true)
            appState.whatsAppStatus = .disconnected
            SettingsManager.shared.whatsAppEnabled = false
            SettingsManager.shared.whatsAppMyJID = ""
            qrImage = nil
            appState.stopWhatsApp()
        } catch {
            Log.warn(.system, "[WhatsApp] Disconnect failed: \(error)")
        }
    }

    private func startStatusPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                await pollStatus()
            }
        }
    }

    private func pollStatus() async {
        let status = await WhatsAppService.shared.checkHealth()
        appState.whatsAppStatus = status

        switch status {
        case .waitingForQR:
            // Fetch QR code
            if let qr = await WhatsAppService.shared.getQRCode() {
                qrImage = qr
            }

        case .connected:
            // Stop polling, we're connected
            pollTimer?.invalidate()
            pollTimer = nil
            qrImage = nil
            SettingsManager.shared.whatsAppEnabled = true
            appState.startWhatsApp()

        case .disconnected:
            qrImage = nil

        case .connecting:
            break
        }
    }

    /// Parse a data URL (data:image/png;base64,...) into raw Data.
    private func dataFromBase64URL(_ dataURL: String) -> Data? {
        guard let commaIndex = dataURL.firstIndex(of: ",") else { return nil }
        let base64 = String(dataURL[dataURL.index(after: commaIndex)...])
        return Data(base64Encoded: base64)
    }
}

// MARK: - Data Models for Skills and Connections

struct SkillItem: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    var enabled: Bool
}

struct ConnectionItem: Identifiable {
    let id = UUID()
    let icon: String
    let name: String
    var connected: Bool
}

// MARK: - AddHotWordSheet

struct AddHotWordSheet: View {
    @Binding var configs: [HotWordConfig]
    @Environment(\.dismiss) private var dismiss

    @State private var keyword = ""
    @State private var action: HotWordAction = .addTodo
    @State private var label = ""
    @State private var skipPermissions = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.lg) {
            Text("ADD HOT WORD")
                .font(AppTheme.heading)
                .foregroundColor(AppTheme.textPrimary)

            VStack(alignment: .leading, spacing: AppTheme.xs) {
                Text("Keyword")
                    .font(AppTheme.caption)
                    .foregroundColor(AppTheme.textSecondary)
                TextField("e.g. p0, info", text: $keyword)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: AppTheme.xs) {
                Text("Action")
                    .font(AppTheme.caption)
                    .foregroundColor(AppTheme.textSecondary)
                Picker("", selection: $action) {
                    ForEach(HotWordAction.allCases, id: \.self) { a in
                        Text(a.displayName).tag(a)
                    }
                }
                .labelsHidden()
            }

            if action == .executeImmediately {
                Toggle("Skip permissions (--dangerously-skip-permissions)", isOn: $skipPermissions)
                    .font(AppTheme.caption)
                    .foregroundColor(AppTheme.textSecondary)
            }

            VStack(alignment: .leading, spacing: AppTheme.xs) {
                Text("Label (display name)")
                    .font(AppTheme.caption)
                    .foregroundColor(AppTheme.textSecondary)
                TextField("e.g. Critical Execute", text: $label)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Add") {
                    guard !keyword.isEmpty else { return }
                    configs.append(HotWordConfig(
                        keyword: keyword.lowercased(),
                        action: action,
                        label: label.isEmpty ? keyword : label,
                        skipPermissions: skipPermissions
                    ))
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(keyword.isEmpty)
            }
        }
        .padding(AppTheme.xl)
        .frame(width: 380)
    }
}
