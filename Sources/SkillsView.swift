import SwiftUI

// MARK: - SkillsView

/// View for managing AutoClawd skills (editable JSON files in ~/.autoclawd/skills/).
struct SkillsView: View {
    @ObservedObject var appState: AppState

    @State private var selectedSkillID: String? = nil
    @State private var editedPrompt: String = ""
    @State private var hasUnsavedChanges = false

    private var selectedSkill: Skill? {
        appState.skills.first(where: { $0.id == selectedSkillID })
    }

    var body: some View {
        let theme = ThemeManager.shared.current
        HSplitView {
            skillList
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
            skillEditor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.isDark ? Color.black.opacity(0.05) : Color.black.opacity(0.01))
        .onAppear { appState.refreshSkills() }
    }

    // MARK: - Skill List

    private var skillList: some View {
        let theme = ThemeManager.shared.current
        let grouped = Dictionary(grouping: appState.skills, by: \.category)
        let sortedCategories = grouped.keys.sorted { $0.rawValue < $1.rawValue }

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("SKILLS")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(theme.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                ForEach(sortedCategories, id: \.self) { category in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.rawValue.uppercased())
                            .font(.system(size: 7, weight: .semibold))
                            .tracking(1)
                            .foregroundColor(theme.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.top, 6)

                        ForEach(grouped[category] ?? [], id: \.id) { skill in
                            skillRow(skill: skill)
                        }
                    }
                }
            }
            .padding(.bottom, 10)
        }
        .background(theme.isDark ? Color.black.opacity(0.08) : Color.black.opacity(0.02))
    }

    private func skillRow(skill: Skill) -> some View {
        let theme = ThemeManager.shared.current
        let isSelected = selectedSkillID == skill.id

        return Button {
            selectSkill(skill)
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(skill.name)
                        .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? theme.accent : theme.textPrimary)
                        .lineLimit(1)
                    if skill.isBuiltin {
                        Text("Built-in")
                            .font(.system(size: 7))
                            .foregroundColor(theme.textTertiary)
                    }
                }
                Spacer()
                if let wf = skill.workflowID {
                    Text(wf)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(theme.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? theme.accent.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Skill Editor

    private var skillEditor: some View {
        let theme = ThemeManager.shared.current

        return VStack(spacing: 0) {
            if let skill = selectedSkill {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Header
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.name)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(theme.textPrimary)
                                Text(skill.id)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(theme.textTertiary)
                            }
                            Spacer()
                            if hasUnsavedChanges {
                                Button("Save") {
                                    savePrompt(skill: skill)
                                }
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(theme.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(theme.accent.opacity(0.18))
                                )
                                .buttonStyle(.plain)
                            }
                        }

                        // Description
                        Text(skill.description)
                            .font(.system(size: 10))
                            .foregroundColor(theme.textSecondary)

                        // Metadata
                        HStack(spacing: 8) {
                            TagView(type: .action, label: skill.category.rawValue, small: true)
                            if let wf = skill.workflowID {
                                TagView(type: .status, label: wf, small: true)
                            }
                            if skill.isBuiltin {
                                TagView(type: .status, label: "built-in", small: true)
                            }
                        }

                        // Prompt template editor
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PROMPT TEMPLATE")
                                .font(.system(size: 8, weight: .semibold))
                                .tracking(1)
                                .foregroundColor(theme.textTertiary)

                            TextEditor(text: $editedPrompt)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(theme.textPrimary)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 200)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(theme.glass.opacity(0.5))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(theme.glassBorder, lineWidth: 0.5)
                                )
                                .onChange(of: editedPrompt) { newValue in
                                    hasUnsavedChanges = newValue != skill.promptTemplate
                                }

                            Text("Placeholders: {{transcript}}, {{project_list}}, {{skill_list}}, {{workflow_list}}, etc.")
                                .font(.system(size: 8))
                                .foregroundColor(theme.textTertiary)
                        }

                        // File location
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 8))
                                .foregroundColor(theme.textTertiary)
                            Text("~/.autoclawd/skills/\(skill.id).json")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(theme.textTertiary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(16)
                }
            } else {
                Spacer()
                VStack(spacing: 6) {
                    Text("Select a skill to view and edit")
                        .font(.system(size: 11))
                        .foregroundColor(theme.textTertiary)
                    Text("Skills are stored as JSON files in ~/.autoclawd/skills/")
                        .font(.system(size: 9))
                        .foregroundColor(theme.textTertiary)
                }
                Spacer()
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
