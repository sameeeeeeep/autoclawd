import SwiftUI

// MARK: - Ambient Intelligence Canvas

/// Shows accumulated session transcript text across all modes.
/// Three opacity layers: cleaned (bright) → pending-raw (medium) → live partial (faint).
/// Falls back to a minimal "listening" idle state when nothing has been spoken yet.
struct AmbientCanvasView: View {
    /// Accumulated cleaned chunks for this session — full opacity.
    let cleanedText:  String
    /// Latest committed chunk awaiting Ollama cleaning — medium opacity.
    let pendingText:  String
    /// Current streaming partial (word-by-word from SFSpeech) — faint.
    let incomingText: String

    private var hasContent: Bool {
        !cleanedText.isEmpty || !pendingText.isEmpty || !incomingText.isEmpty
    }

    var body: some View {
        Group {
            if hasContent {
                liveState
            } else {
                idleState
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
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // One continuous inline text run: cleaned → pending → streaming
                    (
                        Text(cleanedText)
                            .foregroundColor(.white.opacity(0.82))
                        +
                        Text(pendingText.isEmpty ? "" : (cleanedText.isEmpty ? "" : " ") + pendingText)
                            .foregroundColor(.white.opacity(0.52))
                            .italic()
                        +
                        Text(incomingText.isEmpty ? "" : (cleanedText.isEmpty && pendingText.isEmpty ? "" : " ") + incomingText)
                            .foregroundColor(.white.opacity(0.28))
                            .italic()
                    )
                    .font(.system(size: 10, weight: .regular))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onChange(of: incomingText) { _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: cleanedText) { _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
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

/// Live transcription canvas — shows accumulated cleaned text with raw incoming preview.
struct TranscriptCanvasView: View {
    /// Accumulated cleaned transcript chunks — full opacity.
    let cleanedText: String
    /// Committed chunk awaiting Ollama cleaning — medium opacity (never disappears between chunks).
    let pendingText: String
    /// Latest streaming partial (word-by-word from SFSpeech) — faint.
    let incomingText: String
    let onApply: () -> Void
    let onClear: () -> Void

    @State private var scrollID = "bottom"

    private var totalWordCount: Int {
        let all = [cleanedText, pendingText, incomingText].joined(separator: " ")
        return all.split(separator: " ").count
    }

    private var hasContent: Bool { !cleanedText.isEmpty || !pendingText.isEmpty || !incomingText.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header row ──────────────────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("LIVE TRANSCRIPT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
                if totalWordCount > 0 {
                    Text("\(totalWordCount) words")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.28))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider().opacity(0.12)

            // ── Scrolling transcript body ────────────────────────────────────
            // All three layers rendered as one continuous flowing text block.
            // cleaned (bright) → pending-raw (medium, italic) → streaming (faint, italic)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if hasContent {
                            // Build one inline run: cleaned + pending + streaming
                            (
                                Text(cleanedText)
                                    .foregroundColor(.white.opacity(0.82))
                                +
                                Text(pendingText.isEmpty ? "" : (cleanedText.isEmpty ? "" : " ") + pendingText)
                                    .foregroundColor(.white.opacity(0.52))
                                    .italic()
                                +
                                Text(incomingText.isEmpty ? "" : (cleanedText.isEmpty && pendingText.isEmpty ? "" : " ") + incomingText)
                                    .foregroundColor(.white.opacity(0.28))
                                    .italic()
                            )
                            .font(.system(size: 10, weight: .regular))
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("Speak to transcribe…")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.18))
                                .italic()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Anchor for auto-scroll
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: .infinity)
                .onChange(of: incomingText) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: pendingText) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: cleanedText) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            // ── Action row ──────────────────────────────────────────────────
            if hasContent {
                HStack(spacing: 6) {
                    Button(action: onClear) {
                        Text("Clear")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.45))
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.white.opacity(0.07))
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onApply) {
                        HStack(spacing: 4) {
                            Image(systemName: "text.insert")
                                .font(.system(size: 9))
                            Text("Paste")
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.accentColor.opacity(0.75))
                        )
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
        appState.people.filter { !$0.isMe && !$0.isMusic }
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
