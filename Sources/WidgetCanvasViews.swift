import SwiftUI

// MARK: - Ambient Intelligence Canvas

/// Shows live transcript text while the pipeline is running;
/// falls back to a minimal "listening" idle state otherwise.
struct AmbientCanvasView: View {
    let transcript: String

    var body: some View {
        Group {
            if transcript.isEmpty {
                idleState
            } else {
                liveState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idleState: some View {
        VStack(spacing: 8) {
            HStack(spacing: 3) {
                // Static decorative waveform bars
                ForEach([8, 13, 6, 16, 10, 7, 12], id: \.self) { h in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 3, height: CGFloat(h))
                }
            }
            Text("Ambient listening…")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.18))
        }
    }

    private var liveState: some View {
        ScrollView(showsIndicators: false) {
            Text(transcript)
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(.white.opacity(0.55))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
    }
}

// MARK: - Ambient Session Tagging Canvas

/// Shown at the start of an ambient session to let the user tag which project
/// they are working on. Dismissed on chip tap or skip.
struct AmbientTaggingCanvasView: View {
    let projects:  [Project]
    let onSelect:  (Project) -> Void
    let onSkip:    () -> Void

    /// Time-of-day greeting line shown above the prompt.
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning ☀️"
        case 12..<17: return "Good afternoon 🌤️"
        case 17..<21: return "Good evening 🌙"
        default:      return "Late night grind 🌙"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                    HStack(spacing: 5) {
                        Image(systemName: "waveform")
                            .font(.system(size: 10))
                            .foregroundColor(.green.opacity(0.55))
                        Text("What are you working on?")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.78))
                    }
                }
                Spacer()
                Button("Skip") { onSkip() }
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.26))
                    .buttonStyle(.plain)
            }

            if projects.isEmpty {
                Text("No projects yet — add one in Settings.")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.28))
            } else {
                // Project chips — adaptive wrap grid
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 76, maximum: 130), spacing: 6)],
                    spacing: 6
                ) {
                    ForEach(projects) { project in
                        Button { onSelect(project) } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color.purple.opacity(0.70))
                                    .frame(width: 6, height: 6)
                                Text(project.name)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.75))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.purple.opacity(0.10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.purple.opacity(0.22), lineWidth: 1)
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Transcription Canvas

/// Streams the latest clean transcript chunk with an inline "Apply" button.
struct TranscriptCanvasView: View {
    let text:    String
    let onApply: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                Text(text.isEmpty ? "Transcription will appear here…" : text)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(text.isEmpty ? .white.opacity(0.18) : .white.opacity(0.65))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, text.isEmpty ? 10 : 4)
            }

            if !text.isEmpty {
                Button(action: onApply) {
                    Text("Apply to cursor")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - AI Search Canvas

/// Renders the most recent question/answer pair, or an idle prompt.
struct AISearchCanvasView: View {
    let question: String
    let answer:   String

    var body: some View {
        Group {
            if question.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .ultraLight))
                        .foregroundColor(.white.opacity(0.1))
                    Text("Ask a question…")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.18))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(question)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.38))
                        .lineLimit(2)
                    Text(answer)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.72))
                        .lineSpacing(2)
                        .lineLimit(6)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

// MARK: - Tasks Canvas

/// Shows the count + latest task title created in Tasks mode.
struct TasksCanvasView: View {
    let latestTaskTitle: String
    let taskCount:       Int
    var projectName:     String?

    var body: some View {
        Group {
            if latestTaskTitle.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 18, weight: .ultraLight))
                        .foregroundColor(.white.opacity(0.10))
                    Text("Listening for tasks…")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.18))
                    if let proj = projectName {
                        Text(proj)
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.12))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color.orange.opacity(0.75))
                        Text("\(taskCount) task\(taskCount == 1 ? "" : "s") captured")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.38))
                    }
                    Text(latestTaskTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(3)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

// MARK: - Project Picker Canvas  (shared by Code + Tasks modes)

/// Reusable tappable project list — used as the first canvas state in Code and Tasks modes.
struct ProjectPickerCanvasView: View {
    let projects:  [Project]
    let title:     String
    let onSelect:  (Project) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.30))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if projects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 22, weight: .ultraLight))
                        .foregroundColor(.white.opacity(0.10))
                    Text("No projects yet")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.22))
                    Text("Add one in the panel →")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.12))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(projects) { project in
                            Button { onSelect(project) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.28))
                                    Text(project.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.80))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9))
                                        .foregroundColor(.white.opacity(0.20))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.white.opacity(0.05))
                                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 1))
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Code Setup Canvas

/// Second canvas state for Code mode: confirm project + choose Auto/Ask + Start.
struct CodeSetupCanvasView: View {
    let project:             Project
    let skipPermissions:     Bool
    let onTogglePermissions: () -> Void
    let onStart:             () -> Void
    let onChangeProject:     () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Selected project chip
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
                Text(project.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.78))
                Spacer()
                Button("change") { onChangeProject() }
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.28))
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1))
            )

            // Execution mode + Start
            HStack(spacing: 8) {
                modeChip(label: "Auto",
                         active: skipPermissions,
                         color: Color(red: 1.0, green: 0.62, blue: 0.1)) {
                    if !skipPermissions { onTogglePermissions() }
                }
                modeChip(label: "Ask",
                         active: !skipPermissions,
                         color: Color(red: 0.25, green: 0.55, blue: 1.0)) {
                    if skipPermissions { onTogglePermissions() }
                }
                Spacer()
                Button(action: onStart) {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill").font(.system(size: 9))
                        Text("Start").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.90)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func modeChip(label: String, active: Bool, color: Color,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(active ? color : .white.opacity(0.28))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(active ? color.opacity(0.15) : Color.white.opacity(0.04))
                        .overlay(Capsule()
                            .stroke(active ? color.opacity(0.28) : Color.white.opacity(0.07), lineWidth: 1))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Multi-Speaker Prompt Canvas

/// Contextual smart prompt — shown when user enables multi-speaker mode.
/// Person chips are quick-tap, "+" opens the panel to add new people.
struct MultiSpeakerPromptCanvasView: View {
    let people:       [Person]
    let onSelect:     (Person) -> Void
    let onAddPerson:  () -> Void
    let onSkip:       () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.30))
                Text("Who are you with?")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                Button("Skip") { onSkip() }
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.26))
                    .buttonStyle(.plain)
            }

            // Person chips — adaptive grid so they wrap neatly
            let visible = people.filter { !$0.isMe && !$0.isMusic }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76, maximum: 120), spacing: 6)],
                      spacing: 6) {
                ForEach(visible) { person in
                    Button { onSelect(person) } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(person.personColor.color)
                                .frame(width: 7, height: 7)
                            Text(person.name)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.72))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(person.personColor.color.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(person.personColor.color.opacity(0.22), lineWidth: 1))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                // + Add person
                Button { onAddPerson() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 9, weight: .semibold))
                        Text("Add").font(.system(size: 10))
                    }
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.09), lineWidth: 1))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Code Canvas

/// Lightweight code copilot status — project name, streaming indicator, current tool.
struct CodeCanvasView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Group {
            if appState.codeIsStreaming {
                streamingState
            } else {
                idleState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idleState: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("$")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.12))
                Text("claude --project \(appState.codeSelectedProject?.name ?? "…")")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.12))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var streamingState: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 5, height: 5)
                Text(appState.codeCurrentToolName ?? "Running…")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.green.opacity(0.85))
                    .lineLimit(1)
            }
            if let project = appState.codeSelectedProject {
                Text(project.name)
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.28))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
