import SwiftUI
import AppKit

// MARK: - CallStreamWidgetView
//
// Brutalist design language — no circles, no soft rounding, sharp geometric.
// The feed is a story, not a log. Sections:
//
//   ┌─ HEADER: CALL STREAM + timer + close ─────────────────┐
//   │  MISSION: user's goal (first spoken message)           │
//   ├─ PARTICIPANTS: rectangular tiles, thick top accent ────┤
//   │  TASKS: pending todo queue (top 3)                     │
//   ├─ STREAM ──────────────────────────────────────────────┤
//   │  Group chat — NAME ─── time / message / image          │
//   ├─ SPOTLIGHT: current file or image (auto-shown) ────────┤
//   │  END CALL bar                                          │
//   └────────────────────────────────────────────────────────┘

struct CallStreamWidgetView: View {
    @ObservedObject var appState: AppState
    let onClose: () -> Void

    @State private var sessionSeconds: Int = 0
    @State private var spotlightImage: NSImage? = nil
    @State private var spotlightFile:  String?  = nil

    private let sessionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Palette
    private let bg     = Color(red: 0.067, green: 0.067, blue: 0.067)
    private let surf   = Color(red: 0.102, green: 0.102, blue: 0.102)
    private let border = Color.white.opacity(0.07)

    var body: some View {
        VStack(spacing: 0) {
            header
            rowDivider

            if let goal = missionGoal {
                missionBar(goal)
                rowDivider
            }

            participantStrip
            rowDivider

            let tasks = pendingTasks
            if !tasks.isEmpty {
                taskSection(tasks)
                rowDivider
            }

            streamHeader
            streamFeed

            if spotlightImage != nil || spotlightFile != nil {
                rowDivider
                spotlightPanel
            }

            rowDivider
            bottomBar
        }
        .frame(width: 420)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.65), radius: 36, y: 16)
        .shadow(color: .black.opacity(0.20), radius: 6,  y: 2)
        .onReceive(sessionTimer) { _ in sessionSeconds += 1 }
        .onChange(of: appState.callModeSession.messages.count) { _ in
            updateSpotlight()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            // REC dot
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .shadow(color: .red.opacity(0.9), radius: 5)

            Text("CALL STREAM")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
                .tracking(2)

            Spacer()

            Text(formatDuration(sessionSeconds))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.28))
                .monospacedDigit()

            closeButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(surf)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
                .frame(width: 18, height: 18)
                .background(Rectangle().fill(.white.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mission

    private var missionGoal: String? {
        appState.callModeSession.messages.first(where: { $0.role == .user })?.text
    }

    private func missionBar(_ goal: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(Color.orange)
                .frame(width: 2)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 3) {
                sectionLabel("MISSION")
                Text(goal)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(3)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Participant strip (brutalist — no circles)

    private var participantStrip: some View {
        HStack(spacing: 1) {
            userTile
            ForEach(appState.callRoom.participants) { p in
                ParticipantBrutalistTile(
                    participant: p,
                    isActive:    p.id == appState.callRoom.activeParticipantID,
                    onTap:       { appState.callRoom.activeParticipantID = p.id }
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .background(surf)
    }

    private var userTile: some View {
        VStack(spacing: 5) {
            ZStack {
                Rectangle()
                    .fill(.white.opacity(0.05))
                    .frame(width: 32, height: 32)
                if appState.cameraEnabled && appState.cameraService.isRunning {
                    CameraPreviewView(session: appState.cameraService.captureSession)
                        .frame(width: 32, height: 32)
                        .clipped()
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            Text("YOU")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.28))
                .tracking(1)

            // Mic bars
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(appState.isListening ? 0.5 : 0.1))
                        .frame(width: 2, height: 5)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.2)).frame(height: 2)
        }
    }

    // MARK: - Tasks

    private var pendingTasks: [StructuredTodo] {
        Array(appState.structuredTodos.filter { !$0.isExecuted }.prefix(3))
    }

    private func taskSection(_ tasks: [StructuredTodo]) -> some View {
        VStack(spacing: 0) {
            HStack {
                sectionLabel("TASKS")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                Spacer()
                Text("\(tasks.count) pending")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.white.opacity(0.18))
                    .padding(.trailing, 14)
            }
            .background(surf)

            rowDivider

            VStack(spacing: 0) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { i, todo in
                    HStack(spacing: 10) {
                        Rectangle()
                            .fill(i == 0 ? Color.orange : .white.opacity(0.12))
                            .frame(width: 2, height: 14)
                        Image(systemName: i == 0 ? "arrow.right" : "circle")
                            .font(.system(size: 8))
                            .foregroundColor(i == 0 ? .orange : .white.opacity(0.2))
                        Text(todo.content)
                            .font(.system(size: 10))
                            .foregroundColor(i == 0 ? .white.opacity(0.82) : .white.opacity(0.35))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(i == 0 ? Color.orange.opacity(0.04) : Color.clear)

                    if i < tasks.count - 1 {
                        Rectangle()
                            .fill(border)
                            .frame(maxWidth: .infinity, maxHeight: 0.5)
                            .padding(.leading, 14)
                    }
                }
            }
        }
    }

    // MARK: - Stream

    private var streamHeader: some View {
        HStack {
            sectionLabel("STREAM")
            Spacer()
            if appState.callModeSession.isProcessing {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini).tint(.teal)
                    Text("thinking...")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.teal.opacity(0.65))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(surf)
    }

    private var streamFeed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(appState.callModeSession.messages) { msg in
                        BrutalistChatMessage(
                            msg:   msg,
                            color: participantColor(for: msg),
                            name:  participantName(for: msg)
                        )
                        .id(msg.id)
                    }

                    // Live user speech
                    if !appState.liveTranscriptText.isEmpty {
                        BrutalistChatMessage(
                            msg: CallMessage(
                                role:            .user,
                                text:            appState.liveTranscriptText,
                                participantName: "you"
                            ),
                            color: .white,
                            name:  "YOU"
                        )
                        .id("live")
                    }

                    // Empty state
                    if appState.callModeSession.messages.isEmpty && appState.liveTranscriptText.isEmpty {
                        VStack(spacing: 8) {
                            Rectangle()
                                .fill(.white.opacity(0.04))
                                .frame(width: 1, height: 32)
                                .padding(.top, 24)
                            Text("speak or start a claude code session")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.14))
                            Rectangle()
                                .fill(.white.opacity(0.04))
                                .frame(width: 1, height: 24)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 24)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .onChange(of: appState.callModeSession.messages.count) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    if let last = appState.callModeSession.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: appState.liveTranscriptText) { _ in
                withAnimation { proxy.scrollTo("live", anchor: .bottom) }
            }
        }
    }

    // MARK: - Spotlight

    @ViewBuilder
    private var spotlightPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Rectangle()
                    .fill(Color.yellow.opacity(0.6))
                    .frame(width: 2, height: 10)
                sectionLabel("SPOTLIGHT")
                Spacer()
                Button(action: { withAnimation { spotlightImage = nil; spotlightFile = nil } }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7))
                        .foregroundColor(.white.opacity(0.2))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 14)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(surf)

            rowDivider

            if let img = spotlightImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 190)
                    .background(Color.black)
            } else if let file = spotlightFile {
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(Color.yellow.opacity(0.08))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: fileIcon(file))
                                .font(.system(size: 14))
                                .foregroundColor(.yellow.opacity(0.55))
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(fileName(file))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.75))
                        Text(fileCategory(file))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.28))
                    }

                    Spacer()

                    Text("reading")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Rectangle().fill(Color.orange.opacity(0.10)))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal:   .opacity
        ))
        .animation(.easeOut(duration: 0.2), value: spotlightFile)
        .animation(.easeOut(duration: 0.2), value: spotlightImage != nil)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 14) {
            // Waveform
            HStack(spacing: 2) {
                ForEach(0..<10, id: \.self) { i in
                    Rectangle()
                        .fill(Color.green.opacity(appState.isListening ? 0.7 : 0.18))
                        .frame(width: 2, height: waveH(i))
                        .animation(.easeInOut(duration: 0.1), value: appState.audioLevel)
                }
            }
            .frame(width: 30)

            Spacer()

            if !appState.callModeSession.messages.isEmpty {
                Text("\(appState.callModeSession.messages.count) events")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.18))
            }

            // End call — brutalist: red square
            Button {
                appState.stopListening()
                appState.pillMode = .ambientIntelligence
            } label: {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(.white)
                        .frame(width: 7, height: 7)
                    Text("END CALL")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Rectangle().fill(Color.red.opacity(0.85)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(surf)
    }

    // MARK: - Shared helpers

    private var rowDivider: some View {
        Rectangle()
            .fill(border)
            .frame(maxWidth: .infinity, maxHeight: 1)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundColor(.white.opacity(0.25))
            .tracking(2)
    }

    private func participantColor(for msg: CallMessage) -> Color {
        if let pid = msg.participantID,
           let p = appState.callRoom.participants.first(where: { $0.id == pid }) {
            return p.tileColor
        }
        switch msg.role {
        case .user:        return .white
        case .assistant:   return .teal
        case .external:    return .orange
        case .tool:        return .yellow
        case .error:       return .red
        case .participant: return .purple
        }
    }

    private func participantName(for msg: CallMessage) -> String {
        if let name = msg.participantName { return name.uppercased() }
        switch msg.role {
        case .user:        return "YOU"
        case .assistant:   return "AUTOCLAWD"
        case .external:    return "CLAWD"
        case .tool:        return "TOOL"
        case .error:       return "ERROR"
        case .participant: return "AGENT"
        }
    }

    // MARK: - Spotlight helpers

    private func updateSpotlight() {
        let msgs = appState.callModeSession.messages
        for msg in msgs.suffix(6).reversed() {
            if let data = msg.imageData, let img = NSImage(data: data) {
                withAnimation { spotlightImage = img; spotlightFile = nil }
                return
            }
        }
        for msg in msgs.suffix(6).reversed() {
            if let file = extractFilename(from: msg.text) {
                withAnimation { spotlightFile = file; spotlightImage = nil }
                return
            }
        }
    }

    private func extractFilename(from text: String) -> String? {
        // Matches things like "Sources/Foo.swift" or "foo.ts" etc.
        let pat = #"[\w\-./]+\.(swift|ts|tsx|py|js|json|md|yaml|yml|sh|go|rs|kt|css|html)"#
        guard let range = text.range(of: pat, options: .regularExpression),
              text[range].count > 5 else { return nil }
        return String(text[range])
    }

    private func fileIcon(_ path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "swift":     return "swift"
        case "ts", "tsx": return "t.square"
        case "py":        return "terminal"
        case "js":        return "j.square"
        case "json":      return "curlybraces"
        case "md":        return "text.alignleft"
        case "sh":        return "terminal.fill"
        default:          return "doc.text"
        }
    }

    private func fileName(_ path: String) -> String { URL(fileURLWithPath: path).lastPathComponent }

    private func fileCategory(_ path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "swift":     return "swift source"
        case "ts", "tsx": return "typescript"
        case "py":        return "python"
        case "js":        return "javascript"
        case "json":      return "configuration"
        case "md":        return "documentation"
        default:          return "source file"
        }
    }

    private func waveH(_ i: Int) -> CGFloat {
        guard appState.isListening else { return 3 }
        let ph = Double(i) * 0.8
        return 3 + (sin(ph + Double(appState.audioLevel) * 6) * 0.5 + 0.5)
                   * CGFloat(appState.audioLevel) * 12
    }

    private func formatDuration(_ sec: Int) -> String {
        String(format: "%d:%02d", sec / 60, sec % 60)
    }
}

// MARK: - ParticipantBrutalistTile

private struct ParticipantBrutalistTile: View {
    let participant: CallParticipant
    let isActive:    Bool
    let onTap:       () -> Void

    private var color: Color { participant.tileColor }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                // Square icon/mascot — NO circles
                ZStack {
                    Rectangle()
                        .fill(color.opacity(isActive ? 0.12 : 0.06))
                        .frame(width: 34, height: 34)

                    if let ns = NSImage(named: "mascot-\(participant.id)") {
                        Image(nsImage: ns)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: participant.mascotSystemImage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(participant.isPaused ? .gray.opacity(0.3) : color)
                    }

                    // Activity border (square pulse instead of circle)
                    if participant.state == .streaming || participant.state == .thinking {
                        Rectangle()
                            .stroke(color.opacity(0.55), lineWidth: 1)
                            .frame(width: 38, height: 38)
                    }
                }

                Text(participant.displayName.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(isActive ? color : .white.opacity(0.28))
                    .tracking(0.5)
                    .lineLimit(1)

                Text(stateText)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(stateColor.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .background(isActive ? color.opacity(0.055) : Color.clear)
            // Thick top accent bar
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(color)
                    .frame(height: isActive ? 3 : 1)
                    .opacity(isActive ? 1.0 : 0.3)
            }
            // Side/bottom border
            .overlay(
                Rectangle()
                    .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var stateText: String {
        if participant.isPaused { return "paused" }
        switch participant.state {
        case .idle:      return "idle"
        case .thinking:  return "thinking"
        case .streaming: return "working"
        case .paused:    return "paused"
        }
    }

    private var stateColor: Color {
        switch participant.state {
        case .streaming: return color
        case .thinking:  return .yellow
        default:         return .white.opacity(0.3)
        }
    }
}

// MARK: - BrutalistChatMessage

private struct BrutalistChatMessage: View {
    let msg:   CallMessage
    let color: Color
    let name:  String

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // NAME ─────────────── time
            HStack(spacing: 8) {
                Text(name)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(color.opacity(msg.isGenerated ? 0.55 : 1.0))

                if msg.isGenerated {
                    Text("~")
                        .font(.system(size: 9, design: .monospaced))
                        .italic()
                        .foregroundColor(color.opacity(0.4))
                }

                Rectangle()
                    .fill(color.opacity(msg.isGenerated ? 0.12 : 0.22))
                    .frame(maxWidth: .infinity, maxHeight: 1)

                Text(Self.timeFmt.string(from: msg.createdAt))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.18))
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            // Message text
            if !msg.text.isEmpty {
                Text(msg.text)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(msg.isGenerated ? 0.50 : 0.82))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.top, 5)
                    .padding(.bottom, msg.imageData != nil ? 6 : 12)
            }

            // Inline image (Pencil screenshot, ScreenGrab, etc.)
            if let data = msg.imageData, let ns = NSImage(data: data) {
                Image(nsImage: ns)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 200)
                    .background(Color.black)
                    .overlay(
                        Rectangle()
                            .stroke(color.opacity(0.22), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }

            // Bottom rule
            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(maxWidth: .infinity, maxHeight: 1)
        }
        .opacity(msg.isGenerated ? 0.70 : 1.0)
    }
}
