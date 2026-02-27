import SwiftUI

// MARK: - SettingsConsolidatedView

struct SettingsConsolidatedView: View {
    @ObservedObject var appState: AppState

    // API key local state
    @State private var anthropicKey: String = SettingsManager.shared.anthropicAPIKey
    @State private var groqKey: String = ""
    @State private var isValidating = false
    @State private var validationResult: Bool? = nil

    // Hot words local state
    @State private var localHotWordConfigs: [HotWordConfig] = SettingsManager.shared.hotWordConfigs
    @State private var showAddHotWord = false

    // Projects sheet
    @State private var showAddProject = false

    // Appearance
    @AppStorage("color_scheme_setting") private var colorSchemeSetting: String = "system"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.xl) {

                // MARK: PROJECTS
                sectionHeader("PROJECTS")
                VStack(spacing: AppTheme.xs) {
                    ForEach(appState.projects) { project in
                        HStack(spacing: AppTheme.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                    .font(AppTheme.label)
                                    .foregroundColor(AppTheme.textPrimary)
                                Text(project.localPath)
                                    .font(AppTheme.caption)
                                    .foregroundColor(AppTheme.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if !project.tags.isEmpty {
                                    HStack(spacing: 4) {
                                        ForEach(project.tags, id: \.self) { tag in
                                            Text(tag)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, AppTheme.xs)
                                                .padding(.vertical, 2)
                                                .background(AppTheme.green)
                                                .cornerRadius(AppTheme.cornerRadius)
                                        }
                                    }
                                }
                            }
                            Spacer()
                            Button {
                                appState.deleteProject(id: project.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.destructive)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(AppTheme.md)
                        .background(AppTheme.surface)
                        .cornerRadius(AppTheme.cornerRadius)
                    }

                    Button("+ Add Project") { showAddProject = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .sheet(isPresented: $showAddProject) {
                    AddProjectSheet(isPresented: $showAddProject) { name, path in
                        appState.addProject(name: name, path: path)
                    }
                }

                // MARK: HOT WORDS
                sectionHeader("HOT WORDS")
                VStack(spacing: AppTheme.xs) {
                    ForEach(localHotWordConfigs) { config in
                        HStack(spacing: AppTheme.sm) {
                            Text("hot \(config.keyword)")
                                .font(AppTheme.mono)
                                .foregroundColor(AppTheme.green)
                            Text("→ \(config.action.displayName)")
                                .font(AppTheme.caption)
                                .foregroundColor(AppTheme.textSecondary)
                            if config.action == .executeImmediately && config.skipPermissions {
                                Text("⚡")
                                    .font(AppTheme.caption)
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            Spacer()
                            Button {
                                localHotWordConfigs.removeAll { $0.id == config.id }
                                SettingsManager.shared.hotWordConfigs = localHotWordConfigs
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.destructive)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(AppTheme.md)
                        .background(AppTheme.surface)
                        .cornerRadius(AppTheme.cornerRadius)
                    }

                    Button("+ Add Hot Word") { showAddHotWord = true }
                        .buttonStyle(SecondaryButtonStyle())
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

                // MARK: TRANSCRIPTION
                sectionHeader("TRANSCRIPTION")
                VStack(alignment: .leading, spacing: AppTheme.sm) {
                    Picker("", selection: $appState.transcriptionMode) {
                        ForEach(TranscriptionMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
                .padding(AppTheme.md)
                .background(AppTheme.surface)
                .cornerRadius(AppTheme.cornerRadius)

                // MARK: API KEYS
                sectionHeader("API KEYS")
                VStack(alignment: .leading, spacing: AppTheme.sm) {
                    Text("Anthropic API Key")
                        .font(AppTheme.caption)
                        .foregroundColor(AppTheme.textSecondary)
                    SecureField("sk-ant-...", text: $anthropicKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: anthropicKey) { SettingsManager.shared.anthropicAPIKey = $0 }

                    if appState.transcriptionMode == .groq {
                        Divider().padding(.vertical, AppTheme.xs)
                        Text("Groq API Key")
                            .font(AppTheme.caption)
                            .foregroundColor(AppTheme.textSecondary)
                        HStack(spacing: AppTheme.sm) {
                            SecureField("gsk_...", text: $groqKey)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: groqKey) {
                                    appState.groqAPIKey = $0
                                    validationResult = nil
                                }
                            Button(isValidating ? "..." : "Validate") {
                                validateGroqKey()
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(isValidating || groqKey.isEmpty)

                            if let result = validationResult {
                                Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(result ? AppTheme.green : AppTheme.destructive)
                            }
                        }
                    }
                }
                .padding(AppTheme.md)
                .background(AppTheme.surface)
                .cornerRadius(AppTheme.cornerRadius)

                // MARK: DISPLAY
                sectionHeader("DISPLAY")
                VStack(alignment: .leading, spacing: AppTheme.sm) {
                    HStack {
                        Text("Appearance")
                            .font(AppTheme.label)
                            .foregroundColor(AppTheme.textPrimary)
                        Spacer()
                        Picker("", selection: $colorSchemeSetting) {
                            ForEach(ColorSchemeSetting.allCases, id: \.rawValue) { setting in
                                Text(setting.displayName).tag(setting.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                    Divider().padding(.vertical, AppTheme.xs)
                    Toggle(isOn: $appState.showAmbientWidget) {
                        Text("Show Ambient Widget")
                            .font(AppTheme.label)
                            .foregroundColor(AppTheme.textPrimary)
                    }
                    Divider().padding(.vertical, AppTheme.xs)
                    Text("Pill Appearance")
                        .font(AppTheme.caption)
                        .foregroundColor(AppTheme.textSecondary)
                    Picker("", selection: $appState.appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(AppTheme.md)
                .background(AppTheme.surface)
                .cornerRadius(AppTheme.cornerRadius)

                // MARK: MICROPHONE & AUDIO
                sectionHeader("MICROPHONE & AUDIO")
                VStack(alignment: .leading, spacing: AppTheme.sm) {
                    Toggle(isOn: $appState.micEnabled) {
                        Text("Always-on Listening")
                            .font(AppTheme.label)
                            .foregroundColor(AppTheme.textPrimary)
                    }
                    Divider().padding(.vertical, AppTheme.xs)
                    Text("Delete audio after")
                        .font(AppTheme.caption)
                        .foregroundColor(AppTheme.textSecondary)
                    Picker("", selection: $appState.audioRetentionDays) {
                        ForEach(AudioRetention.allCases, id: \.rawValue) { r in
                            Text(r.displayName).tag(r.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }
                .padding(AppTheme.md)
                .background(AppTheme.surface)
                .cornerRadius(AppTheme.cornerRadius)

                // MARK: DATA
                sectionHeader("DATA")
                HStack(spacing: AppTheme.sm) {
                    Button("Re-run Setup") { appState.showSetup() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Export All") { appState.exportData() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Delete All") { appState.confirmDeleteAll() }
                        .buttonStyle(DestructiveButtonStyle())
                }
                .padding(AppTheme.md)
                .background(AppTheme.surface)
                .cornerRadius(AppTheme.cornerRadius)

                Spacer(minLength: AppTheme.xl)
            }
            .padding(AppTheme.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
        .onAppear {
            groqKey = appState.groqAPIKey
            anthropicKey = SettingsManager.shared.anthropicAPIKey
            localHotWordConfigs = SettingsManager.shared.hotWordConfigs
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AppTheme.textSecondary)
            .kerning(0.3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, AppTheme.sm)
    }

    // MARK: - Validate Groq

    private func validateGroqKey() {
        isValidating = true
        Task {
            let result = await TranscriptionService.validateAPIKey(groqKey)
            await MainActor.run {
                validationResult = result
                isValidating = false
            }
        }
    }
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
