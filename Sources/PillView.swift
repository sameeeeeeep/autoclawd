import SwiftUI

// MARK: - Pill State

enum PillState: Equatable {
    case listening
    case processing
    case paused
    case minimal
    case silence
}

// MARK: - PillView

struct PillView: View {
    let state: PillState
    let audioLevel: Float
    let onOpenPanel: () -> Void
    let onTogglePause: () -> Void
    let onOpenLogs: () -> Void
    let onToggleMinimal: () -> Void
    let pillMode: PillMode
    let onCycleMode: () -> Void
    let appearanceMode: AppearanceMode

    @State private var scanOffset: CGFloat = -120
    @State private var scanTimer: Timer? = nil
    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        ZStack {
            switch state {
            case .minimal:
                minimalView
            default:
                fullPillView
            }
        }
        .contextMenu { contextMenu }
        .onTapGesture(count: 2) { onToggleMinimal() }
        .onTapGesture { onOpenPanel() }
    }

    // MARK: - Pulse

    private var pillOpacity: Double {
        switch state {
        case .processing: return pulseOpacity
        case .listening:  return pulseOpacity
        default:          return 1.0
        }
    }

    private func startPulse() {
        switch state {
        case .processing:
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseOpacity = 0.4
            }
        case .listening:
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseOpacity = 0.6
            }
        default:
            withAnimation(.easeInOut(duration: 0.2)) { pulseOpacity = 1.0 }
        }
    }

    // MARK: - Full Pill

    private var fullPillView: some View {
        HStack(spacing: 8) {
            modeButton

            ZStack {
                waveformBars
                if state == .processing { scanLine }
            }
            .frame(width: 100, height: 24)
            .clipShape(Rectangle())

            stateLabel

            pausePlayButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(pillBackground)
        .overlay(pillBorder)
        .frame(height: 40)
        .opacity(pillOpacity)
        .onAppear { startPulse() }
        .onChange(of: state) { _ in startPulse() }
    }

    // MARK: - Mode Button

    private var modeButton: some View {
        Button(action: onCycleMode) {
            Text(pillMode.shortLabel)
                .font(.custom("JetBrains Mono", size: 10).weight(.bold))
                .foregroundColor(state == .paused
                    ? .white.opacity(0.4)
                    : BrutalistTheme.neonGreen)
                .frame(width: 36, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pause/Play Button

    private var pausePlayButton: some View {
        Button(action: onTogglePause) {
            Text(state == .paused ? "[▶]" : "[⏸]")
                .font(.custom("JetBrains Mono", size: 10).weight(.bold))
                .foregroundColor(.white.opacity(state == .paused ? 0.9 : 0.5))
                .frame(width: 28, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Minimal Dot

    private var minimalView: some View {
        Circle()
            .fill(Color.black)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
    }

    // MARK: - Waveform Bars

    private var waveformBars: some View {
        HStack(spacing: 3) {
            ForEach(0..<16, id: \.self) { i in
                Rectangle()
                    .fill(barColor(index: i))
                    .frame(width: 3, height: barHeight(index: i))
                    .animation(.easeOut(duration: 0.08), value: audioLevel)
            }
        }
    }

    private func barHeight(index: Int) -> CGFloat {
        guard state == .listening else { return 4 }
        let base: CGFloat = 4
        let phase = Double(index) * 0.6
        let wave = sin(phase + Double(audioLevel) * 10) * 0.5 + 0.5
        let level = CGFloat(audioLevel)
        return base + wave * level * 18
    }

    private func barColor(index: Int) -> Color {
        state == .listening ? BrutalistTheme.neonGreen : Color.white.opacity(0.20)
    }

    // MARK: - Scan Line (processing)

    private var scanLine: some View {
        Rectangle()
            .fill(Color.white.opacity(0.6))
            .frame(width: 2, height: 24)
            .offset(x: scanOffset)
            .onAppear { startScan() }
            .onDisappear { stopScan() }
    }

    private func startScan() {
        scanOffset = -120
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            withAnimation(.linear(duration: 0.016)) {
                scanOffset += 3
                if scanOffset > 120 { scanOffset = -120 }
            }
        }
    }

    private func stopScan() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    // MARK: - Label

    private var stateLabel: some View {
        Text(labelText)
            .font(.custom("JetBrains Mono", size: 10).weight(.medium))
            .foregroundColor(.white.opacity(0.7))
            .monospacedDigit()
    }

    private var labelText: String {
        switch state {
        case .listening:  return "LIVE"
        case .processing: return "PROC"
        case .paused:     return "PAUSE"
        case .silence:    return "SIL"
        case .minimal:    return ""
        }
    }

    // MARK: - Background & Border

    private var pillBackground: some View {
        ZStack {
            switch appearanceMode {
            case .frosted:
                Rectangle().fill(.ultraThinMaterial)
            case .transparent:
                Rectangle().fill(Color.black.opacity(0.35))
            }
            // Specular sheen (both modes)
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
        }
    }

    private var pillBorder: some View {
        Rectangle().stroke(Color.white.opacity(0.25), lineWidth: 1)
    }

    // MARK: - Context Menu

    private var contextMenu: some View {
        Group {
            Button("Open Panel") { onOpenPanel() }
            Button(state == .paused ? "Resume Listening" : "Pause Listening") { onTogglePause() }
            Divider()
            Button("Mode: \(pillMode.displayName) → \(pillMode.next().displayName)") { onCycleMode() }
            Divider()
            Button("View Logs") { onOpenLogs() }
        }
    }
}
