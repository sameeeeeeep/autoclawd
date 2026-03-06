import SwiftUI

// MARK: - SkillsView

struct SkillsView: View {
    @ObservedObject var appState: AppState

    @State private var selectedSkillID: String? = nil
    @State private var editedPrompt: String = ""
    @State private var hasUnsavedChanges = false

    private var selectedSkill: Skill? {
        appState.skills.first(where: { $0.id == selectedSkillID })
    }

    var body: some View {
        NavigationSplitView {
            skillList
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            skillEditor
        }
        .onAppear { appState.refreshSkills() }
    }

    // MARK: - Skill List

    private var skillList: some View {
        let allSkills = appState.skills
        let builtinSkills = allSkills.filter { $0.isOpenClaw != true }
        let openClawSkills = allSkills.filter { $0.isOpenClaw == true }

        let builtinGrouped = Dictionary(grouping: builtinSkills, by: \.category)
        let builtinCategories = builtinGrouped.keys.sorted { $0.rawValue < $1.rawValue }

        let openClawGrouped = Dictionary(grouping: openClawSkills, by: \.category)
        let openClawCategories = openClawGrouped.keys.sorted { $0.rawValue < $1.rawValue }

        return List(selection: $selectedSkillID) {
            // Built-in skills
            ForEach(builtinCategories, id: \.self) { category in
                Section(category.rawValue.capitalized) {
                    ForEach(builtinGrouped[category] ?? [], id: \.id) { skill in
                        skillRow(skill)
                            .tag(skill.id)
                    }
                }
            }

            // OpenClaw skills (separated)
            if !openClawSkills.isEmpty {
                Section {
                    ForEach(openClawCategories, id: \.self) { category in
                        Section(category.rawValue.capitalized) {
                            ForEach(openClawGrouped[category] ?? [], id: \.id) { skill in
                                skillRow(skill)
                                    .tag(skill.id)
                            }
                        }
                    }
                } header: {
                    Label("OpenClaw Skills", systemImage: "puzzlepiece.extension")
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selectedSkillID) { newValue in
            if let id = newValue, let skill = appState.skills.first(where: { $0.id == id }) {
                selectSkill(skill)
            }
        }
    }

    private func skillRow(_ skill: Skill) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(skill.name)
                        .font(.body)
                    if !skill.isAvailable {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                if skill.isBuiltin {
                    Text("Built-in")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if skill.isOpenClaw == true {
                    Text("OpenClaw")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            Spacer()
            if let wf = skill.workflowID {
                Text(wf.replacingOccurrences(of: "autoclawd-", with: ""))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Skill Editor

    private var skillEditor: some View {
        VStack(spacing: 0) {
            if let skill = selectedSkill {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Header
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.name)
                                    .font(.title3.bold())
                                Text(skill.id)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fontDesign(.monospaced)
                            }
                            Spacer()
                            if hasUnsavedChanges && skill.isOpenClaw != true {
                                Button("Save") {
                                    savePrompt(skill: skill)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }

                        Text(skill.description)
                            .font(.callout)
                            .foregroundColor(.secondary)

                        // Tags
                        HStack(spacing: 8) {
                            TagView(type: .action, label: skill.category.rawValue, small: true)
                            if let wf = skill.workflowID {
                                TagView(type: .status, label: wf, small: true)
                            }
                            if skill.isBuiltin {
                                TagView(type: .status, label: "built-in", small: true)
                            }
                            if skill.isOpenClaw == true {
                                TagView(type: .action, label: "openclaw", small: true)
                            }
                            if !skill.isAvailable {
                                TagView(type: .action, label: "unavailable", small: true)
                            }
                        }

                        // Requirements (for OpenClaw skills)
                        if skill.isOpenClaw == true {
                            openClawDetails(skill)
                        }

                        // Instructions (for OpenClaw skills with SKILL.md body)
                        if let instructions = skill.instructions, !instructions.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Skill Instructions")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                ScrollView {
                                    Text(instructions)
                                        .font(.system(size: 11, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                }
                                .frame(minHeight: 150, maxHeight: 300)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                                .textSelection(.enabled)

                                if let path = skill.skillMDPath {
                                    Button("Open in Editor") {
                                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }

                        // Prompt Template (editable for non-OpenClaw skills)
                        if skill.isOpenClaw != true {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Prompt Template")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                TextEditor(text: $editedPrompt)
                                    .font(.system(size: 11, design: .monospaced))
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 200)
                                    .padding(8)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                                    .onChange(of: editedPrompt) { newValue in
                                        hasUnsavedChanges = newValue != skill.promptTemplate
                                    }

                                Text("Placeholders: {{transcript}}, {{project_list}}, {{skill_list}}, {{workflow_list}}, etc.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // File location
                        if skill.isOpenClaw == true, let path = skill.skillMDPath {
                            Label(path, systemImage: "doc.text")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fontDesign(.monospaced)
                                .textSelection(.enabled)
                        } else {
                            Label("~/.autoclawd/skills/\(skill.id).json", systemImage: "doc.text")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fontDesign(.monospaced)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(16)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("Select a Skill")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Built-in skills stored in ~/.autoclawd/skills/\nOpenClaw skills loaded from ~/.autoclawd/openclaw-skills/")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - OpenClaw Skill Details

    private func openClawDetails(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let bins = skill.requiredBins, !bins.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Required Binaries")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(bins, id: \.self) { bin in
                        HStack(spacing: 6) {
                            Image(systemName: Skill.commandExists(bin) ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(Skill.commandExists(bin) ? .green : .red)
                                .font(.caption)
                            Text(bin)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }

            if let envVars = skill.envVars, !envVars.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Environment Variables")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(Array(envVars.keys.sorted()), id: \.self) { key in
                        HStack(spacing: 6) {
                            Image(systemName: "key")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text(key)
                                .font(.system(.caption, design: .monospaced))
                            if let val = envVars[key], !val.isEmpty {
                                Text("= \(val.prefix(20))...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func selectSkill(_ skill: Skill) {
        if hasUnsavedChanges, let current = selectedSkill, current.isOpenClaw != true {
            savePrompt(skill: current)
        }
        selectedSkillID = skill.id
        editedPrompt = skill.promptTemplate
        hasUnsavedChanges = false
    }

    private func savePrompt(skill: Skill) {
        guard skill.isOpenClaw != true else { return } // OpenClaw skills are read-only
        var updated = skill
        updated.promptTemplate = editedPrompt
        appState.skillStore.save(updated)
        appState.refreshSkills()
        hasUnsavedChanges = false
    }
}
