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
        let grouped = Dictionary(grouping: appState.skills, by: \.category)
        let sortedCategories = grouped.keys.sorted { $0.rawValue < $1.rawValue }

        return List(selection: $selectedSkillID) {
            ForEach(sortedCategories, id: \.self) { category in
                Section(category.rawValue.capitalized) {
                    ForEach(grouped[category] ?? [], id: \.id) { skill in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.name)
                                    .font(.body)
                                if skill.isBuiltin {
                                    Text("Built-in")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if let wf = skill.workflowID {
                                Text(wf)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tag(skill.id)
                    }
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

    // MARK: - Skill Editor

    private var skillEditor: some View {
        VStack(spacing: 0) {
            if let skill = selectedSkill {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
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
                            if hasUnsavedChanges {
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

                        HStack(spacing: 8) {
                            TagView(type: .action, label: skill.category.rawValue, small: true)
                            if let wf = skill.workflowID {
                                TagView(type: .status, label: wf, small: true)
                            }
                            if skill.isBuiltin {
                                TagView(type: .status, label: "built-in", small: true)
                            }
                        }

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

                        Label("~/.autoclawd/skills/\(skill.id).json", systemImage: "doc.text")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fontDesign(.monospaced)
                            .textSelection(.enabled)
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
                    Text("Skills are stored as JSON files in ~/.autoclawd/skills/")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Actions

    private func selectSkill(_ skill: Skill) {
        if hasUnsavedChanges, let current = selectedSkill {
            savePrompt(skill: current)
        }
        selectedSkillID = skill.id
        editedPrompt = skill.promptTemplate
        hasUnsavedChanges = false
    }

    private func savePrompt(skill: Skill) {
        var updated = skill
        updated.promptTemplate = editedPrompt
        appState.skillStore.save(updated)
        appState.refreshSkills()
        hasUnsavedChanges = false
    }
}
