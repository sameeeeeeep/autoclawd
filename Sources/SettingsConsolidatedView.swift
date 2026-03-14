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
        case .general:     return "gearshape"
        case .models:      return "cpu"
        case .projects:    return "folder"
        case .people:      return "person.2"
        case .skills:      return "wrench.and.screwdriver"
        case .connections: return "link"
        case .appearance:  return "paintbrush"
        case .widget:      return "widget.small"
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

    @State private var selectedSection: SettingsSection = .general

    @State private var autoStart = true

    @State private var localHotWordConfigs: [HotWordConfig] = SettingsManager.shared.hotWordConfigs
    @State private var showAddHotWord = false

    @State private var groqKey: String = ""
    @State private var anthropicKey: String = SettingsManager.shared.anthropicAPIKey
    @State private var isValidatingGroq = false
    @State private var groqValidationResult: Bool? = nil

    @State private var connections: [ConnectionItem] = [
        ConnectionItem(icon: "desktopcomputer", name: "Claude Code CLI", connected: false),
        ConnectionItem(icon: "calendar", name: "Google Calendar", connected: false),
        ConnectionItem(icon: "envelope", name: "Gmail", connected: false),
        ConnectionItem(icon: "bubble.left.and.bubble.right", name: "Slack", connected: false),
        ConnectionItem(icon: "doc.text", name: "Notion", connected: false),
        ConnectionItem(icon: "chevron.left.forwardslash.chevron.right", name: "GitHub", connected: false),
    ]

    @State private var showWaveform = true
    @State private var showRecentTranscripts = true

    @State private var showAddProject = false

    @State private var newPersonName = ""

    @State private var audioDevices: [AVCaptureDevice] = []
    @State private var selectedAudioDeviceID: String = ""


    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.label, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 140, ideal: 170, max: 200)
        } detail: {
            ScrollView {
                settingsContent
                    .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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

    @ViewBuilder
    private var settingsContent: some View {
        switch selectedSection {
        case .general:     generalSection()
        case .models:      modelsSection()
        case .projects:    projectsSection()
        case .people:      peopleSection()
        case .skills:      skillsSection()
        case .connections: connectionsSection()
        case .appearance:  appearanceSection()
        case .widget:      widgetSection()
        }
    }

    // MARK: - General Section

    @ViewBuilder
    private func generalSection() -> some View {
        Form {
            Section("Listening") {
                Toggle("Auto-start on login", isOn: $autoStart)
                Toggle("Always-on listening", isOn: $appState.micEnabled)
            }

            Section("Transcription") {
                Picker("Engine", selection: $appState.transcriptionMode) {
                    ForEach(TranscriptionMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker("Audio input", selection: $selectedAudioDeviceID) {
                    Text("System Default").tag("")
                    ForEach(audioDevices, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device.uniqueID)
                    }
                }

                Picker("Delete audio after", selection: $appState.audioRetentionDays) {
                    ForEach(AudioRetention.allCases, id: \.rawValue) { r in
                        Text(r.displayName).tag(r.rawValue)
                    }
                }
            }

            Section("Hot Words") {
                ForEach(localHotWordConfigs) { config in
                    HStack {
                        Label {
                            Text("hot \(config.keyword)")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        } icon: {
                            if config.action == .executeImmediately && config.skipPermissions {
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(.orange)
                            } else {
                                Image(systemName: "waveform")
                            }
                        }

                        Spacer()

                        Text(config.action.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(role: .destructive) {
                            localHotWordConfigs.removeAll { $0.id == config.id }
                            SettingsManager.shared.hotWordConfigs = localHotWordConfigs
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Button("Add Hot Word...") {
                    showAddHotWord = true
                }
            }

            Section("Preferences") {
                Picker("Language", selection: .constant("en_hi")) {
                    Text("English + Hindi").tag("en_hi")
                }

                Toggle("Notifications", isOn: $appState.showToasts)
            }

            Section("Data") {
                HStack(spacing: 12) {
                    Button("Re-run Setup") { appState.showSetup() }
                        .buttonStyle(.bordered)
                    Button("Export All") { appState.exportData() }
                        .buttonStyle(.bordered)
                    Button("Delete All", role: .destructive) { appState.confirmDeleteAll() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Models Section

    @ViewBuilder
    private func modelsSection() -> some View {
        Form {
            Section("API Keys") {
                LabeledContent("Anthropic") {
                    SecureField("sk-ant-...", text: $anthropicKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                        .onChange(of: anthropicKey) { _ in
                            SettingsManager.shared.anthropicAPIKey = anthropicKey
                        }
                }

                LabeledContent("Groq") {
                    HStack(spacing: 8) {
                        SecureField("gsk_...", text: $groqKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 240)
                            .onChange(of: groqKey) { _ in
                                appState.groqAPIKey = groqKey
                                groqValidationResult = nil
                            }

                        Button(isValidatingGroq ? "Validating..." : "Validate") {
                            validateGroqKey()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isValidatingGroq || groqKey.isEmpty)

                        if let result = groqValidationResult {
                            Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result ? .green : .red)
                        }
                    }
                }
            }

            Section("Model Assignments") {
                LabeledContent("Transcription") {
                    Text(appState.transcriptionMode.displayName)
                        .foregroundColor(.secondary)
                }

                LabeledContent("Cleaning") {
                    Text("Claude Haiku 4.5")
                        .foregroundColor(.secondary)
                }

                LabeledContent("Analysis") {
                    Text("Claude Sonnet 4.5")
                        .foregroundColor(.secondary)
                }

                LabeledContent("Execution") {
                    Text("Claude Code CLI")
                        .foregroundColor(.secondary)
                }

                Picker("Auto-approve", selection: $appState.synthesizeThreshold) {
                    Text("Manual").tag(0)
                    Text("Auto: 5").tag(5)
                    Text("Auto: 10").tag(10)
                    Text("Auto: 20").tag(20)
                }
            }

            Section("Autonomous Task Rules") {
                Text("List task categories that autoclawd can execute without asking for approval. One rule per line. Example: \"Create a GitHub issue\", \"Search the web\".")
                    .font(.caption)
                    .foregroundColor(.secondary)

                AutonomousRulesEditor(rules: $appState.autonomousTaskRules)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Projects Section

    @ViewBuilder
    private func projectsSection() -> some View {
        let dotColors: [Color] = [.blue, .cyan, .purple]
        Form {
            Section {
                ForEach(Array(appState.projects.enumerated()), id: \.element.id) { index, project in
                    HStack {
                        Circle()
                            .fill(dotColors[index % dotColors.count])
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name)
                                .font(.body)
                            Text(project.localPath)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Button(role: .destructive) {
                            appState.deleteProject(id: project.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Button("Add Project...") {
                    showAddProject = true
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - People Section

    @ViewBuilder
    private func peopleSection() -> some View {
        Form {
            Section {
                ForEach(appState.people) { person in
                    HStack {
                        Circle()
                            .fill(person.color)
                            .frame(width: 8, height: 8)

                        Text(person.name)

                        if person.isMe {
                            Text("you")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.blue.opacity(0.1), in: Capsule())
                        }
                        if person.isMusic {
                            Text("music")
                                .font(.caption)
                                .foregroundColor(.purple)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.purple.opacity(0.1), in: Capsule())
                        }

                        Spacer()

                        if !person.isMe && !person.isMusic {
                            Button(role: .destructive) {
                                appState.people.removeAll { $0.id == person.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section("Add Person") {
                HStack {
                    TextField("Name", text: $newPersonName)
                        .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        let name = newPersonName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        appState.addPerson(name: name)
                        newPersonName = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newPersonName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section {
                Label("Drag people on the World map to set their spatial position",
                      systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Skills Section

    @ViewBuilder
    private func skillsSection() -> some View {
        Form {
            Section("OpenClaw Skills") {
                Toggle("Enable OpenClaw Skills", isOn: Binding(
                    get: { SettingsManager.shared.isOpenClawEnabled },
                    set: { SettingsManager.shared.isOpenClawEnabled = $0 }
                ))

                HStack {
                    Text("Skills Directory")
                    Spacer()
                    let dir = SkillStore.openClawDirectory().path
                    Text(dir)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                let openClawSkills = appState.skillStore.availableOpenClawSkills()
                let allOpenClaw = appState.skillStore.all().filter { $0.isOpenClaw == true }

                HStack {
                    Text("Loaded Skills")
                    Spacer()
                    Text("\(openClawSkills.count) available / \(allOpenClaw.count) total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button("Refresh Skills") {
                    appState.skillStore.refreshOpenClawSkills()
                    appState.refreshSkills()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Open Skills Folder") {
                    let dir = SkillStore.openClawDirectory()
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(dir)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Section("How to Add Skills") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Place OpenClaw-compatible skill folders in the skills directory. Each folder should contain a SKILL.md file with YAML frontmatter and markdown instructions.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Example SKILL.md:")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("""
                    ---
                    name: Web Search
                    description: Search the web
                    requires:
                      bins:
                        - curl
                    category: search
                    ---
                    # Instructions...
                    """)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(6)
                }
            }

            Section("Built-in Skills") {
                let builtinSkills = appState.skillStore.allBuiltin().filter { $0.category != .pipeline }
                ForEach(builtinSkills, id: \.id) { skill in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(skill.name)
                                .font(.body)
                            Text(skill.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text(skill.category.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Connections Section

    @ViewBuilder
    private func connectionsSection() -> some View {
        Form {
            Section("Integrations") {
                ForEach($connections) { $conn in
                    let isCC = conn.name == "Claude Code CLI"
                    HStack {
                        Image(systemName: conn.icon)
                            .frame(width: 20)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(conn.name)
                            if isCC {
                                Text(conn.connected ? "Connected" : "Not connected")
                                    .font(.caption)
                                    .foregroundColor(conn.connected ? .green : .secondary)
                            } else {
                                Text("Coming Soon")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        if isCC {
                            Button(conn.connected ? "Manage" : "Connect") {}
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .opacity(isCC ? 1.0 : 0.5)
                }
            }
        }
        .formStyle(.grouped)
    }


    // MARK: - Appearance Section

    @ViewBuilder
    private func appearanceSection() -> some View {
        Form {
            Section {
                Text("Appearance follows your macOS system settings.")
                    .foregroundColor(.secondary)
            }

            Section("Pill") {
                Picker("Style", selection: $appState.appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section("Text Size") {
                Picker("Font size", selection: $appState.fontSizePreference) {
                    ForEach(FontSizePreference.allCases, id: \.self) { pref in
                        Text(pref.displayName).tag(pref)
                    }
                }
                .pickerStyle(.segmented)

                Text("Changes take effect after reopening the main panel.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Widget Section

    @ViewBuilder
    private func widgetSection() -> some View {
        Form {
            Section("Visibility") {
                Toggle("Show widget", isOn: $appState.showAmbientWidget)
            }

            Section("Glass Style") {
                Picker("Base colour", selection: $appState.widgetBase) {
                    ForEach(WidgetBase.allCases, id: \.self) { base in
                        Text(base.label).tag(base)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Material", selection: $appState.widgetStyle) {
                    ForEach(WidgetStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Text("Changes apply instantly to the floating widget.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Preview") {
                HStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(appState.widgetBase == .dark
                              ? Color.black.opacity(appState.widgetStyle == .solid ? 0.88 : 0.52)
                              : Color.white.opacity(appState.widgetStyle == .solid ? 0.94 : 0.22))
                        .frame(width: 160, height: 56)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.22), .white.opacity(0.05)],
                                        startPoint: .top, endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .overlay(
                            Text("autoclawd")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(appState.widgetBase == .dark ? .white : Color(red: 0.08, green: 0.08, blue: 0.10))
                        )
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                    Spacer()
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
        }
        .formStyle(.grouped)
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
            } catch {}
        }
    }
}


// MARK: - Connection Item

struct ConnectionItem: Identifiable {
    let id = UUID()
    var icon: String
    var name: String
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Hot Word")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Keyword").font(.caption).foregroundStyle(.secondary)
                TextField("e.g. p0, info", text: $keyword)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Action").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $action) {
                    ForEach(HotWordAction.allCases, id: \.self) { a in
                        Text(a.displayName).tag(a)
                    }
                }
                .labelsHidden()
            }

            if action == .executeImmediately {
                Toggle("Skip permissions (--dangerously-skip-permissions)", isOn: $skipPermissions)
                    .font(.caption)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Label (display name)").font(.caption).foregroundStyle(.secondary)
                TextField("e.g. Critical Execute", text: $label)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
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
                .buttonStyle(.borderedProminent)
                .disabled(keyword.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

// MARK: - Autonomous Rules Editor

/// Inline list editor for the autonomous task rules setting.
/// Each rule is a plain-English description of a task category.
private struct AutonomousRulesEditor: View {
    @Binding var rules: [String]
    @State private var newRule: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if rules.isEmpty {
                Text("No rules yet — all tasks will require approval.")
                    .font(.caption)
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.accentColor)

                        Text(rule)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            rules.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)

                    if index < rules.count - 1 {
                        Divider()
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("Add a rule, e.g. \"Create a GitHub issue\"", text: $newRule)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit { addRule() }

                Button(action: addRule) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(newRule.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addRule() {
        let trimmed = newRule.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        rules.append(trimmed)
        newRule = ""
    }
}
