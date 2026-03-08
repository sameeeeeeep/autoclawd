import SwiftUI
import Combine

// MARK: - CallModeRoomView

/// Full-panel Call Mode UI — participant tiles, shared feed, session controls.
/// Replaces PixelWorldView in the World tab when pillMode == .callMode.
struct CallModeRoomView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            participantsRow
            Divider().background(Color.white.opacity(0.07))
            callFeed
            Divider().background(Color.white.opacity(0.07))
            bottomBar
        }
        .background(Color.black)
        // Route left-hand finger count → participant selection
        .onReceive(appState.$lastConfirmedGesture.compactMap { $0 }) { gesture in
            if case .leftFingerCount(let count) = gesture {
                appState.callRoom.selectByGesture(fingerCount: count)
            }
        }
    }

    // MARK: - Participants Row

    private var participantsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(appState.callRoom.participants) { participant in
                    ParticipantTileView(
                        participant: participant,
                        isActive: participant.id == appState.callRoom.activeParticipantID,
                        onTap:   { appState.callRoom.activeParticipantID = participant.id },
                        onPause: { appState.callRoom.togglePause(id: participant.id) },
                        onRemove: participant.kind == .llama ? nil
                                  : { appState.callRoom.remove(id: participant.id) }
                    )
                }
                inviteButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(height: 148)
    }

    private var inviteButton: some View {
        VStack(spacing: 6) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 52, height: 52)
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.8))
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
            }
            Text("Invite")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.2))
            Spacer()
        }
        .frame(width: 80, height: 124)
    }

    // MARK: - Call Feed

    private var callFeed: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        // Transcript from user's voice — live session text
                        if !appState.liveTranscriptText.isEmpty {
                            CallFeedMessageRow(
                                participantName: "You",
                                color: .white,
                                icon: "mic.fill",
                                text: appState.liveTranscriptText
                            )
                            .id("transcript")
                        }
                        // Messages from participants (Claude Code / external)
                        ForEach(appState.callModeSession.messages) { msg in
                            CallFeedMessageRow(
                                participantName: feedLabel(for: msg.role),
                                color: feedColor(for: msg.role),
                                icon: feedIcon(for: msg.role),
                                text: msg.text
                            )
                            .id(msg.id)
                        }
                    }
                    .padding(14)
                }
                .onChange(of: appState.callModeSession.messages.count) { _ in
                    if let last = appState.callModeSession.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: appState.liveTranscriptText) { _ in
                    withAnimation { proxy.scrollTo("transcript", anchor: .bottom) }
                }
            }

            // Processing indicator
            if appState.callModeSession.isProcessing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini).tint(.cyan)
                    Text("Thinking…")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.8)))
                .padding(.bottom, 8)
            }

            // Empty state
            if appState.callModeSession.messages.isEmpty && appState.liveTranscriptText.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.1))
                    Text("CALL ACTIVE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.15))
                    Text("Speak to start — use left fingers to address participants")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.1))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            // Camera preview (small)
            cameraThumb
            // Screen preview (small)
            screenThumb
            Spacer()
            // Session controls
            sessionControls
            Spacer()
            // Addressing indicator
            addressingIndicator
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.025))
    }

    private var cameraThumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black)
                .frame(width: 64, height: 44)
            if appState.cameraEnabled && appState.cameraService.isRunning {
                CameraPreviewView(session: appState.cameraService.captureSession)
                    .frame(width: 64, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "camera.slash")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
    }

    private var screenThumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black)
                .frame(width: 64, height: 44)
            if let img = appState.screenPreviewImage {
                Image(decorative: img, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
    }

    private var sessionControls: some View {
        HStack(spacing: 14) {
            // Play / Pause toggle
            Button {
                if appState.isListening { appState.stopListening() }
                else { appState.startListening() }
            } label: {
                Image(systemName: appState.isListening ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(appState.isListening ? .white : .green)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)

            // Stop — end call
            Button {
                appState.stopListening()
                appState.pillMode = .ambientIntelligence
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.red.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
    }

    private var addressingIndicator: some View {
        HStack(spacing: 5) {
            if let active = appState.callRoom.activeParticipant {
                Text("①".replacing("①", with: "⑤".isEmpty ? "" : slotEmoji(active.gestureSlot)))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                Image(systemName: active.mascotSystemImage)
                    .font(.system(size: 10))
                    .foregroundColor(participantColor(active.kind))
                Text(active.displayName)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Helpers

    private func slotEmoji(_ slot: Int) -> String {
        let circled = ["①","②","③","④","⑤"]
        guard slot >= 1, slot <= circled.count else { return "\(slot)" }
        return circled[slot - 1]
    }

    private func feedLabel(for role: CallMessage.Role) -> String {
        switch role {
        case .user:      return "You"
        case .assistant: return "AutoClawd"
        case .tool:      return "Tool"
        case .error:     return "Error"
        case .external:  return "Claw'd"
        }
    }

    private func feedColor(for role: CallMessage.Role) -> Color {
        switch role {
        case .user:      return .white
        case .assistant: return .teal
        case .tool:      return .yellow
        case .error:     return .red
        case .external:  return .orange
        }
    }

    private func feedIcon(for role: CallMessage.Role) -> String {
        switch role {
        case .user:      return "mic.fill"
        case .assistant: return "brain"
        case .tool:      return "wrench.adjustable"
        case .error:     return "exclamationmark.triangle"
        case .external:  return "terminal"
        }
    }

    private func participantColor(_ kind: ParticipantKind) -> Color {
        switch kind {
        case .llama:      return .teal
        case .claudeCode: return .orange
        case .connection: return .purple
        }
    }
}

// MARK: - ParticipantTileView

struct ParticipantTileView: View {
    let participant: CallParticipant
    let isActive: Bool
    let onTap:    () -> Void
    let onPause:  () -> Void
    let onRemove: (() -> Void)?

    private var tileColor: Color {
        switch participant.kind {
        case .llama:      return .teal
        case .claudeCode: return .orange
        case .connection: return .purple
        }
    }

    var body: some View {
        VStack(spacing: 5) {
            // Top row: gesture slot + controls
            HStack(spacing: 4) {
                slotBadge
                Spacer()
                pauseButton
                if let rm = onRemove { removeButton(action: rm) }
            }

            // Mascot
            ParticipantMascotView(
                kind:     participant.kind,
                state:    participant.state,
                isPaused: participant.isPaused
            )
            .frame(width: 54, height: 54)

            // Name
            Text(participant.displayName)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(isActive ? .white : .white.opacity(0.4))
                .lineLimit(1)

            // State label
            stateLabel
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(width: 104)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isActive ? 0.07 : 0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isActive ? tileColor.opacity(0.55) : Color.white.opacity(0.08),
                            lineWidth: isActive ? 1.5 : 0.5
                        )
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .animation(.easeInOut(duration: 0.15), value: isActive)
        .animation(.easeInOut(duration: 0.15), value: participant.state)
    }

    private var slotBadge: some View {
        Text(circledDigit(participant.gestureSlot))
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(isActive ? tileColor : .white.opacity(0.25))
    }

    private var pauseButton: some View {
        Button(action: onPause) {
            Image(systemName: participant.isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.white.opacity(0.45))
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var stateLabel: some View {
        if participant.isPaused {
            Text("paused")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white.opacity(0.2))
        } else {
            switch participant.state {
            case .idle:
                Text("idle")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
            case .thinking:
                ThinkingDotsView()
            case .streaming:
                Text("streaming")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(tileColor.opacity(0.7))
            case .paused:
                Text("paused")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
    }

    private func circledDigit(_ n: Int) -> String {
        let circled = ["①","②","③","④","⑤"]
        guard n >= 1, n <= circled.count else { return "\(n)" }
        return circled[n - 1]
    }
}

// MARK: - ParticipantMascotView

struct ParticipantMascotView: View {
    let kind:     ParticipantKind
    let state:    ParticipantState
    let isPaused: Bool

    @State private var breathe = false
    @State private var shimmer = false

    private var mascotIcon: String {
        switch kind {
        case .llama:      return "brain"
        case .claudeCode: return "hammer.fill"
        case .connection(_, _): return "cable.connector"
        }
    }

    private var mascotColor: Color {
        switch kind {
        case .llama:      return .teal
        case .claudeCode: return .orange
        case .connection: return .purple
        }
    }

    var body: some View {
        ZStack {
            // Outer glow ring — pulses when streaming
            Circle()
                .stroke(
                    mascotColor.opacity(isPaused ? 0 : (state == .streaming ? 0.4 : 0.12)),
                    lineWidth: state == .streaming ? 2 : 1
                )
                .scaleEffect(shimmer ? 1.15 : 1.0)
                .opacity(shimmer ? 0 : 1)

            // Background fill
            Circle()
                .fill(mascotColor.opacity(isPaused ? 0.04 : 0.12))

            // Icon
            Image(systemName: mascotIcon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(isPaused ? .gray.opacity(0.3) : mascotColor)
                .scaleEffect(breathe ? 1.06 : 1.0)

            // Thinking spinner overlay
            if state == .thinking && !isPaused {
                Circle()
                    .trim(from: 0, to: 0.65)
                    .stroke(mascotColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(breathe ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: breathe)
            }

            // Paused badge
            if isPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
                    .offset(x: 14, y: 14)
            }
        }
        .onAppear { animate() }
        .onChange(of: state) { _ in animate() }
        .onChange(of: isPaused) { _ in animate() }
    }

    private func animate() {
        switch state {
        case .idle:
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathe = true
            }
            shimmer = false
        case .thinking:
            breathe = true  // spinner uses this
        case .streaming:
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: false)) {
                shimmer = true
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                breathe = true
            }
        case .paused:
            breathe = false
            shimmer = false
        }
    }
}

// MARK: - ThinkingDotsView

private struct ThinkingDotsView: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(phase == i ? 0.7 : 0.2))
                    .frame(width: 4, height: 4)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
                phase = (phase + 1) % 3
            }
        }
    }
}

// MARK: - CallFeedMessageRow

private struct CallFeedMessageRow: View {
    let participantName: String
    let color: Color
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(color.opacity(0.6))
                .frame(width: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(participantName.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(color.opacity(0.5))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
