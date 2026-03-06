import SwiftUI

// MARK: - Session Config View

/// Slide-out panel for configuring a recording session before it starts.
/// Lets the user select a project, tag people, and add context bullets.
struct SessionConfigView: View {
    @ObservedObject var appState: AppState
    let appearance: WidgetAppearance

    @State private var selectedProjectID: String?
    @State private var selectedPeopleIDs: Set<UUID> = []
    @State private var contextBullets: [String] = [""]
    @State private var isVoiceInputActive = false

    private var projects: [Project] { appState.projectStore.all() }
    private var people: [Person] { appState.people.filter { !$0.isMe } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "rectangle.and.pencil.and.ellipsis")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(appearance.textSecondary)
                Text("New Session")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(appearance.textPrimary)
                Spacer()
                Button { appState.dismissSessionConfig() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(appearance.textOff)
                }
                .buttonStyle(.plain)
            }

            Divider().opacity(0.2)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    projectSection
                    peopleSection
                    contextSection
                    voiceInputButton
                }
            }

            Spacer(minLength: 0)

            // Start button
            Button {
                let config = buildConfig()
                appState.startUserSession(config: config)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                    Text("Start Session")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.green.opacity(0.65))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Project Section

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PROJECT")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(appearance.textOff)

            if projects.isEmpty {
                Text("No projects — add one in Settings")
                    .font(.system(size: 9))
                    .foregroundColor(appearance.textOff)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 70, maximum: 120), spacing: 5)],
                    spacing: 5
                ) {
                    ForEach(projects) { project in
                        Button { selectedProjectID = project.id } label: {
                            let isSelected = selectedProjectID == project.id
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(isSelected ? Color.purple : Color.purple.opacity(0.4))
                                    .frame(width: 5, height: 5)
                                Text(project.name)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(isSelected ? appearance.textPrimary : appearance.textSecondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isSelected ? Color.purple.opacity(0.18) : Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(isSelected ? Color.purple.opacity(0.35) : appearance.textOff.opacity(0.15), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - People Section

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PEOPLE")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(appearance.textOff)

            if people.isEmpty {
                Text("No people added yet")
                    .font(.system(size: 9))
                    .foregroundColor(appearance.textOff)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 60, maximum: 100), spacing: 5)],
                    spacing: 5
                ) {
                    ForEach(people) { person in
                        Button { togglePerson(person.id) } label: {
                            let isSelected = selectedPeopleIDs.contains(person.id)
                            HStack(spacing: 4) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(isSelected ? PersonColor(rawValue: person.colorIndex)?.color ?? .blue : appearance.textOff)
                                Text(person.name)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(isSelected ? appearance.textPrimary : appearance.textSecondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isSelected ? Color.blue.opacity(0.12) : Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(isSelected ? Color.blue.opacity(0.30) : appearance.textOff.opacity(0.15), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Context Section

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CONTEXT")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(appearance.textOff)

            ForEach(contextBullets.indices, id: \.self) { idx in
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 3))
                        .foregroundColor(appearance.textOff)
                    TextField("Add context...", text: $contextBullets[idx])
                        .font(.system(size: 10))
                        .foregroundColor(appearance.textPrimary)
                        .textFieldStyle(.plain)
                    if contextBullets.count > 1 {
                        Button { contextBullets.remove(at: idx) } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 9))
                                .foregroundColor(appearance.textOff)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(appearance.canvasBg.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(appearance.textOff.opacity(0.12), lineWidth: 1)
                        )
                )
            }

            Button { contextBullets.append("") } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 9))
                    Text("Add bullet")
                        .font(.system(size: 9))
                }
                .foregroundColor(appearance.textOff)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Voice Input

    private var voiceInputButton: some View {
        Button {
            isVoiceInputActive.toggle()
            // TODO: Wire voice input — record briefly, transcribe, send to Ollama to infer context
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isVoiceInputActive ? "mic.fill" : "mic")
                    .font(.system(size: 10))
                    .foregroundColor(isVoiceInputActive ? .green : appearance.textSecondary)
                Text(isVoiceInputActive ? "Listening..." : "Speak to set context")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(appearance.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isVoiceInputActive ? Color.green.opacity(0.4) : appearance.textOff.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func togglePerson(_ id: UUID) {
        if selectedPeopleIDs.contains(id) {
            selectedPeopleIDs.remove(id)
        } else {
            selectedPeopleIDs.insert(id)
        }
    }

    private func buildConfig() -> SessionConfig {
        let project = projects.first { $0.id == selectedProjectID }
        let selectedPeople = people.filter { selectedPeopleIDs.contains($0.id) }
        let bullets = contextBullets.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        return SessionConfig(
            projectID: project?.id,
            projectName: project?.name,
            peopleIDs: selectedPeople.map(\.id.uuidString),
            peopleNames: selectedPeople.map(\.name),
            contextBullets: bullets
        )
    }
}
