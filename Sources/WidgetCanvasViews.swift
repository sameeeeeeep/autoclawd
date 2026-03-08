import SwiftUI

// MARK: - Canvas Text Input Bar

/// Compact typed-text input shown at the bottom of the AI canvas.
/// Lets users type or paste context alongside their spoken transcript.
/// Clipboard auto-paste (via ClipboardMonitor) appends text here automatically.
struct CanvasTextInputBar: View {
    @Binding var text: String
    var placeholder: String = "Type to add context…"

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "keyboard")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white.opacity(0.25))
                .padding(.top, 2)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.18))
                        .padding(.top, 1)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.72))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 28, maxHeight: 52)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.6))
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }
}

// MARK: - Unified Canvas Text Box
// Used by all transcript-accumulating canvas views.
// One editable TextEditor for STT+typing, with a faint ghost line for the live streaming partial.

struct UnifiedCanvasTextBox: View {
    /// Combined STT + typed text — editable.
    @Binding var text: String
    /// Live streaming partial from SFSpeech — faint ghost, not editable.
    var streamingPartial: String = ""
    var placeholder: String = "Speak or type…"

    private var hasContent: Bool { !text.isEmpty || !streamingPartial.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                // Placeholder when completely empty
                if !hasContent {
                    Text(placeholder)
                        .font(.system(size: 10, design: .default))
                        .foregroundColor(.white.opacity(0.18))
                        .padding(.horizontal, 14)
                        .padding(.top, 11)
                        .allowsHitTesting(false)
                }

                // Editable body — cleaned STT appended here by AppState + user typing
                TextEditor(text: $text)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.white.opacity(0.82))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .lineSpacing(3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }

            // Live streaming partial shown below as a faint ghost
            if !streamingPartial.isEmpty {
                Text(streamingPartial)
                    .font(.system(size: 10, weight: .regular).italic())
                    .foregroundColor(.white.opacity(0.28))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Ambient Intelligence Canvas

/// Single unified text box — STT text is appended here automatically by AppState,
/// and the user can type/edit freely in the same field.
struct AmbientCanvasView: View {
    /// Accumulated cleaned chunks — passed so AppDelegate can snapshot; not shown separately.
    let cleanedText:  String
    let pendingText:  String
    /// Current streaming partial (word-by-word from SFSpeech) — shown as ghost below editor.
    let incomingText: String
    /// Unified editable text (STT + typed). Bound to AppState.canvasTypedText.
    @Binding var typedText: String

    var body: some View {
        UnifiedCanvasTextBox(
            text: $typedText,
            streamingPartial: incomingText,
            placeholder: "Speak or type to add context…"
        )
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

/// Live transcription canvas — single unified text box (STT appended + user can type).
struct TranscriptCanvasView: View {
    let cleanedText: String
    let pendingText: String
    let incomingText: String
    let onApply: () -> Void
    let onClear: () -> Void
    @Binding var typedText: String

    private var wordCount: Int { typedText.split(separator: " ").count }
    private var hasContent: Bool { !typedText.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ───────────────────────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("LIVE TRANSCRIPT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
                if wordCount > 0 {
                    Text("\(wordCount) words")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.28))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider().opacity(0.12)

            // ── Unified text box ──────────────────────────────────────────────
            UnifiedCanvasTextBox(
                text: $typedText,
                streamingPartial: incomingText,
                placeholder: "Speak to transcribe…"
            )

            // ── Action row ────────────────────────────────────────────────────
            if hasContent {
                HStack(spacing: 6) {
                    Button(action: onClear) {
                        Text("Clear")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.45))
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(0.07)))
                    }
                    .buttonStyle(.plain)

                    Button(action: onApply) {
                        HStack(spacing: 4) {
                            Image(systemName: "text.insert").font(.system(size: 9))
                            Text("Paste")
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.accentColor.opacity(0.75)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: hasContent)
    }
}

// MARK: - AI Search Canvas

/// Renders the most recent question/answer pair, or an idle prompt.
struct AISearchCanvasView: View {
    let question: String
    let answer:   String
    /// Typed/clipboard-pasted text input (bound to AppState.canvasTypedText).
    @Binding var typedText: String

    var body: some View {
        VStack(spacing: 0) {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            UnifiedCanvasTextBox(text: $typedText, placeholder: "Speak or type a question…")
                .frame(maxHeight: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Meeting Canvas

/// Live meeting notes canvas — single unified text box.
/// STT text is appended automatically; user can also type/edit inline.
struct MeetingCanvasView: View {
    let cleanedText:  String
    let pendingText:  String
    let incomingText: String
    @Binding var typedText: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.wave.2")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.purple)
                Text("MEETING")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
                Text("analysed at session end")
                    .font(.system(size: 7))
                    .foregroundColor(.white.opacity(0.20))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider().opacity(0.12)

            UnifiedCanvasTextBox(
                text: $typedText,
                streamingPartial: incomingText,
                placeholder: "Speak or type to add notes…"
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Call Mode Canvas

/// Canvas for Call Mode — shows the real-time Claude conversation thread.
/// Voice chunks are sent directly to Claude; Claude calls screen/cursor/selection tools inline.
struct CallModeCanvasView: View {
    @ObservedObject var session: CallModeSession

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "phone.bubble")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.cyan)
                Text("CALL MODE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
                if session.isProcessing {
                    HStack(spacing: 3) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 10, height: 10)
                        Text("thinking")
                            .font(.system(size: 7))
                            .foregroundColor(.cyan.opacity(0.60))
                    }
                } else {
                    Text("direct · claude")
                        .font(.system(size: 7))
                        .foregroundColor(.white.opacity(0.20))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider().opacity(0.12)

            // Message thread
            if session.messages.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 20, weight: .ultraLight))
                        .foregroundColor(.cyan.opacity(0.18))
                    Text("Speak to start the call")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.22))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(session.messages) { msg in
                                CallMessageBubble(message: msg)
                                    .id(msg.id)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: session.messages.count) { _ in
                        if let last = session.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Single message bubble in the call mode thread.
private struct CallMessageBubble: View {
    let message: CallMessage

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            // Role indicator dot
            Circle()
                .fill(roleColor)
                .frame(width: 5, height: 5)
                .padding(.top, 4)

            Text(message.text)
                .font(.system(size: 10, design: message.role == .tool ? .monospaced : .default))
                .foregroundColor(textColor)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var roleColor: Color {
        switch message.role {
        case .user:        return .white.opacity(0.45)
        case .assistant:   return .cyan
        case .tool:        return .yellow.opacity(0.60)
        case .error:       return .red
        case .external:    return .green
        case .participant: return .purple
        }
    }

    private var textColor: Color {
        switch message.role {
        case .user:        return .white.opacity(0.72)
        case .assistant:   return .white.opacity(0.88)
        case .tool:        return .white.opacity(0.38)
        case .error:       return .red.opacity(0.80)
        case .external:    return .green.opacity(0.85)
        case .participant: return .white.opacity(0.85)
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
                            if let seed = person.avatarSeed {
                                PixelAvatarView(seed: seed, pixelSize: 2)
                            } else {
                                Circle()
                                    .fill(person.personColor.color)
                                    .frame(width: 7, height: 7)
                            }
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

// MARK: - Face Linking Canvas

/// Shown on the AI canvas when the user taps the face count badge.
/// Walks through each tracked face and presents numbered people options.
/// User selects with left-hand gestures (1-5) or tap.
struct FaceLinkingCanvasView: View {
    @ObservedObject var appState: AppState

    private var currentFace: FaceTracker.TrackedFace? {
        let queue = appState.faceTracker.trackedFaces
        let index = appState.faceLinkingIndex
        guard index < queue.count else { return nil }
        return queue[index]
    }

    private var peopleOptions: [Person] {
        appState.people.filter { !$0.isMusic }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "face.dashed")
                    .font(.system(size: 10))
                    .foregroundColor(.cyan)
                Text("Link Faces")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                Button {
                    appState.showFaceLinkingOverlay = false
                } label: {
                    Text("Done")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.26))
                }
                .buttonStyle(.plain)
            }

            if let face = currentFace {
                // Current face label
                HStack(spacing: 6) {
                    Text(face.label)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.3))
                    Text("?")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.yellow)
                }

                // People chips
                let options = peopleOptions
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 76, maximum: 120), spacing: 6)],
                    spacing: 6
                ) {
                    ForEach(Array(options.enumerated()), id: \.offset) { idx, person in
                        Button { appState.advanceFaceLinking(selectedOption: idx + 1) } label: {
                            HStack(spacing: 5) {
                                Text("\(idx + 1)")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(.cyan)
                                    .frame(width: 12)
                                if let seed = person.avatarSeed {
                                    PixelAvatarView(seed: seed, pixelSize: 2)
                                } else {
                                    Circle()
                                        .fill(person.personColor.color)
                                        .frame(width: 6, height: 6)
                                }
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
                                    .fill(Color.cyan.opacity(0.08))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.cyan.opacity(0.18), lineWidth: 1))
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("gesture \u{270B} 1-\(options.count) or tap")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.22))
            } else {
                Text("No faces detected")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.22))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Session Project Picker Canvas

/// Gesture-friendly project picker shown on the AI canvas when a session starts.
/// User raises left hand with 1-5 fingers to select a project, or taps.
struct SessionProjectPickerCanvasView: View {
    let projects: [Project]
    let onSelect: (Project) -> Void
    let onSkip: () -> Void

    var body: some View {
        let displayProjects = Array(projects.prefix(5))
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                Text("Start Session")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                Button { onSkip() } label: {
                    Text("Skip")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.26))
                }
                .buttonStyle(.plain)
            }

            Text("SELECT PROJECT")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white.opacity(0.28))
                .tracking(1)

            // Numbered project list
            ForEach(Array(displayProjects.enumerated()), id: \.offset) { idx, project in
                Button { onSelect(project) } label: {
                    HStack(spacing: 8) {
                        Text("\(idx + 1)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                            .frame(width: 14)
                        Image(systemName: "folder.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.30))
                        Text(project.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.78))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.green.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.green.opacity(0.15), lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("gesture \u{270B} 1-\(displayProjects.count) or tap")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white.opacity(0.22))
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Cleaning Picker Canvas

/// Shown after a transcription session ends. Shows the actual transcript text
/// Shows the cleaned transcript with level tabs. Auto-runs minimal first;
/// user can gesture 1-3 to re-clean at a different level, thumbs up to dismiss.
struct CleaningPickerCanvasView: View {
    let results: [CleaningLevel: String]
    let selected: CleaningLevel
    let isProcessing: Bool
    let onSelect: (CleaningLevel) -> Void
    let onDismiss: () -> Void

    private var currentText: String {
        results[selected] ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Level tabs ────────────────────────────────────────────────
            HStack(spacing: 0) {
                ForEach(CleaningLevel.allCases) { level in
                    let isActive = level == selected
                    let available = results[level] != nil

                    Button { onSelect(level) } label: {
                        VStack(spacing: 3) {
                            HStack(spacing: 3) {
                                Text("\(level.index)")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                                    .foregroundColor(isActive ? .cyan : .white.opacity(0.3))
                                Text(level.displayName)
                                    .font(.system(size: 9, weight: isActive ? .semibold : .regular))
                                    .foregroundColor(isActive ? .white.opacity(0.85) : .white.opacity(available ? 0.40 : 0.18))
                            }
                            // Underline indicator — no conflicting box
                            Rectangle()
                                .fill(isActive ? Color.cyan.opacity(0.75) : Color.clear)
                                .frame(height: 1.5)
                                .cornerRadius(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .padding(.bottom, 2)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button { onDismiss() } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.25))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider().opacity(0.12)

            // ── Transcript text ───────────────────────────────────────────
            ScrollView(showsIndicators: false) {
                if currentText.isEmpty && isProcessing {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                        Text("Cleaning…")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.25))
                            .italic()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                } else {
                    Text(currentText)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.82))
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .id(selected)
                        .transition(.opacity)
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: selected)

            // ── Hint ──────────────────────────────────────────────────────
            Text("\u{270B} 1-3 · \u{1F44D} done")
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.white.opacity(0.18))
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Ambient Session Review Canvas

/// Post-session review overlay shown on the pill canvas after an ambient session ends.
/// Four phases: cleaning → analyzing → tasksReady → done.
/// Gesture-aware: left fingers select project, thumbs up approves all tasks.
struct AmbientSessionReviewView: View {
    let review:          AmbientReviewState
    let tasks:           [PipelineTaskRecord]
    let projects:        [Project]
    let skills:          [Skill]
    let onApproveTask:   (String) -> Void
    let onSkipTask:      (String) -> Void
    let onApproveAll:    () -> Void
    let onSelectProject: (Project?) -> Void
    let onDone:          () -> Void

    var body: some View {
        switch review.phase {
        case .done:
            doneView
        default:
            mainView
        }
    }

    // MARK: - Done State

    private var doneView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26))
                .foregroundColor(.green.opacity(0.8))
            Text("All done")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.82))
            Text("Tasks executed successfully")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.35))
            Spacer()
            Button { onDone() } label: {
                Text("Close")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.cyan.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.cyan.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main Review View (cleaning / analyzing / tasksReady)

    private var mainView: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────────────
            HStack(spacing: 6) {
                phaseIcon
                phaseLabel
                Spacer()
                if review.phase == .tasksReady {
                    Button { onDone() } label: {
                        Text("Skip")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.28))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 5)

            Divider().opacity(0.10)

            // ── Scrollable body ───────────────────────────────────────────────
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {

                    // ── Transcript ─────────────────────────────────────────────
                    if !review.cleanedTranscript.isEmpty {
                        ScrollView(showsIndicators: false) {
                            Text(review.cleanedTranscript)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(.white.opacity(0.78))
                                .lineSpacing(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 70)
                    }

                    // ── Pipeline status spinner ────────────────────────────────
                    if review.phase == .cleaning || review.phase == .analyzing {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.45)
                                .frame(width: 10, height: 10)
                            Text(review.phase == .cleaning ? "Cleaning transcript…" : "Extracting tasks…")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.28))
                                .italic()
                        }
                    }

                    // ── Task list ─────────────────────────────────────────────
                    if review.phase == .tasksReady {
                        if tasks.isEmpty {
                            Text("No tasks extracted.")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.25))
                                .italic()
                        } else {
                            VStack(spacing: 5) {
                                ForEach(tasks) { task in
                                    taskRow(task)
                                }
                            }

                            // Approve-all hint
                            HStack {
                                Spacer()
                                Button { onApproveAll() } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "hand.thumbsup.fill")
                                            .font(.system(size: 9))
                                        Text("Approve all & execute")
                                            .font(.system(size: 9, weight: .semibold))
                                    }
                                    .foregroundColor(.green.opacity(0.8))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(Color.green.opacity(0.10))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                    .stroke(Color.green.opacity(0.25), lineWidth: 1)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                                Spacer()
                            }
                        }
                    }

                    // ── Project chips ─────────────────────────────────────────
                    projectSelector

                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Phase Icon & Label

    @ViewBuilder
    private var phaseIcon: some View {
        switch review.phase {
        case .cleaning:
            Image(systemName: "wand.and.sparkles")
                .font(.system(size: 10))
                .foregroundColor(.cyan.opacity(0.7))
        case .analyzing:
            Image(systemName: "brain")
                .font(.system(size: 10))
                .foregroundColor(.cyan.opacity(0.7))
        case .tasksReady:
            Image(systemName: "checkmark.circle")
                .font(.system(size: 10))
                .foregroundColor(.green.opacity(0.7))
        case .done:
            EmptyView()
        }
    }

    @ViewBuilder
    private var phaseLabel: some View {
        switch review.phase {
        case .cleaning:
            Text("CLEANING")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
                .tracking(1)
        case .analyzing:
            Text("ANALYZING")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
                .tracking(1)
        case .tasksReady:
            Text("SESSION REVIEW")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
                .tracking(1)
        case .done:
            EmptyView()
        }
    }

    // MARK: - Task Row (rich: title + tags + skill chip + attachments)

    @ViewBuilder
    private func taskRow(_ task: PipelineTaskRecord) -> some View {
        let approved = review.approvedTaskIDs.contains(task.id)
        let skipped  = review.skippedTaskIDs.contains(task.id)
        let resolved = approved || skipped

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                // State icon
                Image(systemName: approved ? "checkmark.circle.fill"
                                  : skipped  ? "xmark.circle.fill"
                                             : "circle")
                    .font(.system(size: 10))
                    .foregroundColor(approved ? .green
                                     : skipped  ? .white.opacity(0.18)
                                                : .white.opacity(0.30))
                    .frame(width: 14, alignment: .top)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    // Title
                    Text(task.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(resolved ? 0.28 : 0.80))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Chips row: skill + tags + attachments
                    if !resolved {
                        chipsRow(task)
                    }
                }

                // Action buttons (hidden once resolved)
                if !resolved {
                    VStack(spacing: 3) {
                        Button("✓") { onApproveTask(task.id) }
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green.opacity(0.85))
                            .buttonStyle(.plain)
                        Button("✕") { onSkipTask(task.id) }
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.22))
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(resolved ? 0.02 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(approved ? Color.green.opacity(0.18) : Color.clear, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func chipsRow(_ task: PipelineTaskRecord) -> some View {
        let skillName: String? = task.skillID.flatMap { sid in
            skills.first(where: { $0.id == sid })?.name
        }
        let hasChips = skillName != nil || !task.attachmentPaths.isEmpty
        if hasChips {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    // Skill chip
                    if let sname = skillName {
                        miniChip(label: sname, icon: "bolt.fill", color: .purple)
                    }
                    // Attachment chips
                    ForEach(Array(task.attachmentPaths.prefix(2).enumerated()), id: \.offset) { _, path in
                        let name = URL(fileURLWithPath: path).lastPathComponent
                        miniChip(label: name, icon: "paperclip", color: .cyan)
                    }
                }
            }
            .frame(height: 18)
        }
    }

    @ViewBuilder
    private func miniChip(label: String, icon: String?, color: Color) -> some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 6))
            }
            Text(label)
                .font(.system(size: 7, weight: .medium))
                .lineLimit(1)
        }
        .foregroundColor(color.opacity(0.7))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(color.opacity(0.08))
                .overlay(Capsule().stroke(color.opacity(0.18), lineWidth: 0.5))
        )
    }

    // MARK: - Project Selector (numbered chips for gesture selection)

    private var projectSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("PROJECT")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white.opacity(0.22))
                    .tracking(1)
                if review.phase != .done {
                    Text("· gesture to assign")
                        .font(.system(size: 7))
                        .foregroundColor(.white.opacity(0.14))
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 62, maximum: 110), spacing: 4)],
                spacing: 4
            ) {
                // "0" = None chip
                numberedProjectChip(index: 0, label: "None",
                                    selected: review.selectedProjectID == nil) {
                    onSelectProject(nil)
                }

                ForEach(Array(projects.prefix(5).enumerated()), id: \.element.id) { i, project in
                    numberedProjectChip(
                        index: i + 1,
                        label: project.name,
                        selected: review.selectedProjectID == project.id
                    ) {
                        onSelectProject(project)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func numberedProjectChip(index: Int, label: String, selected: Bool,
                                     action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            HStack(spacing: 3) {
                Text("\(index)")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(selected ? .cyan.opacity(0.6) : .white.opacity(0.20))
                Text(label)
                    .font(.system(size: 9, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? .cyan : .white.opacity(0.45))
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.cyan.opacity(0.12) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(selected ? Color.cyan.opacity(0.5) : Color.clear,
                                    lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Task Execution Canvas

/// Shown on the pill canvas while a pipeline task is streaming via Claude Code.
/// Reuses AppState's codeSessionMessages / codeIsStreaming / CodeMessageRow machinery.
struct TaskExecutionCanvasView: View {
    let task: PipelineTaskRecord
    @ObservedObject var appState: AppState
    let onDone: () -> Void

    var isRunning: Bool { appState.codeSession?.isRunning == true || appState.codeIsStreaming }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────────────
            HStack(spacing: 5) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.accentColor)

                Text(task.title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)

                Spacer()

                // Streaming pulse
                if appState.codeIsStreaming {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                        .modifier(PulsingDot())
                }

                // Stop / Done button
                Button { onDone() } label: {
                    if isRunning {
                        Image(systemName: "stop.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.7))
                    } else {
                        Text("Done")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.cyan.opacity(0.65))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 5)

            Divider().opacity(0.10)

            // ── Message stream ────────────────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(appState.codeSessionMessages) { msg in
                            CodeMessageRow(message: msg)
                                .id(msg.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: appState.codeSessionMessages.count) { _ in
                    if let last = appState.codeSessionMessages.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // ── Tool indicator ────────────────────────────────────────────────
            if let toolName = appState.codeCurrentToolName {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text(toolName)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
