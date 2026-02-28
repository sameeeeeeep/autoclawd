import AppKit
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

    private var isActiveState: Bool {
        state == .listening || state == .processing
    }

    // MARK: - Full Pill

    private var fullPillView: some View {
        HStack(spacing: 8) {
            modeButton

            ZStack {
                waveformBars
                if state == .processing { scanLine }
            }
            .frame(width: 80, height: 24)
            .clipShape(Rectangle())

            stateDot

            pausePlayButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(pillBackground)
        .overlay(pillBorder)
        .frame(height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .opacity(pillOpacity)
        .onAppear { startPulse() }
        .onChange(of: state) { _ in startPulse() }
    }

    // MARK: - Mode Button

    private var modeButton: some View {
        Button(action: onCycleMode) {
            Image(systemName: pillMode.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(state == .paused ? .secondary : .accentColor)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pause/Play Button

    private var pausePlayButton: some View {
        Button(action: onTogglePause) {
            Image(systemName: state == .paused ? "play.fill" : "pause.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.primary.opacity(state == .paused ? 0.85 : 0.55))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(state == .paused ? 0.12 : 0.06)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Minimal Dot

    private var minimalView: some View {
        Circle()
            .fill(Color(NSColor.controlBackgroundColor))
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
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
        state == .listening ? .accentColor : .secondary.opacity(0.3)
    }

    // MARK: - Scan Line (processing)

    private var scanLine: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.5))
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

    // MARK: - State Dot

    private var stateDot: some View {
        Circle()
            .fill(stateDotColor)
            .frame(width: 6, height: 6)
    }

    private var stateDotColor: Color {
        switch state {
        case .listening:  return .green
        case .processing: return .orange
        case .paused:     return .secondary.opacity(0.4)
        case .silence:    return .secondary.opacity(0.2)
        case .minimal:    return .clear
        }
    }

    // MARK: - Background & Border (Clean macOS style)

    private var pillBackground: some View {
        ZStack {
            switch appearanceMode {
            case .frosted:
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            case .solid:
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(NSColor.windowBackgroundColor))
            }
        }
    }

    private var pillBorder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
    }

    // MARK: - Context Menu

    private var contextMenu: some View {
        Group {
            Button("Open Panel") { onOpenPanel() }
            Button(state == .paused ? "Resume Listening  \u{2303}Z" : "Pause Listening  \u{2303}Z") { onTogglePause() }
            Divider()
            Button("Ambient Mode  \u{2303}A") { onCycleMode() }
            Button("AI Search Mode  \u{2303}S") { onCycleMode() }
            Button("Transcribe Mode  \u{2303}X") { onCycleMode() }
            Divider()
            Button("View Logs") { onOpenLogs() }
            Divider()
            Button("Quit AutoClawd") { NSApp.terminate(nil) }
        }
    }
}
