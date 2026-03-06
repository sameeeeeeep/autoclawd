import SwiftUI
import AppKit

// MARK: - Collapse Level

enum WidgetCollapseLevel: Int, CaseIterable {
    case expanded   // everything + extra canvas height
    case full       // header + status rows + mode bar + canvas + logs + dock
    case compact    // header + mode bar + canvas (taller) + logs
    case headerOnly // header + audio row only
    case icon       // app icon in small rounded square

    var height: CGFloat {
        switch self {
        case .expanded:   return 740
        case .full:       return 640
        case .compact:    return 460
        case .headerOnly: return 150
        case .icon:       return 52
        }
    }

    var width: CGFloat { self == .icon ? 52 : 240 }

    func next() -> WidgetCollapseLevel {
        WidgetCollapseLevel(rawValue: min(rawValue + 1, 4)) ?? .icon
    }
    func prev() -> WidgetCollapseLevel {
        WidgetCollapseLevel(rawValue: max(rawValue - 1, 0)) ?? .expanded
    }
}

// MARK: - Pipeline Stage

enum WidgetStageKind { case analysis, execution }

struct WidgetStageRow: Identifiable {
    let id    = UUID()
    var kind:  WidgetStageKind
    var icon:  String
    var color: Color
    var title: String
    var sub1:  String
    var sub2:  String
}

// MARK: - Glow State (for the three status rows)

/// Three visual states for the per-row intelligence glow effect.
enum GlowState: Equatable {
    case off                 // row disabled — no glow
    case enabled             // row ON but idle — gentle breathing pulse
    case thinking            // actively processing — Apple Intelligence shimmer
}

// MARK: - Canvas Snapshot (for history)

struct CanvasSnapshot: Identifiable {
    let id        = UUID()
    let mode:     PillMode
    let label:    String        // e.g. "Transcription · 14:32"
    let content:  AnyView
}

// MARK: - Widget Appearance Token System

/// Derives every colour token used inside the widget from a `WidgetBase` + `WidgetStyle` pair.
/// Pass one of these into WidgetView and it propagates to every sub-view automatically.
struct WidgetAppearance {
    static let `default` = WidgetAppearance(base: .dark, style: .frosted)

    let base:  WidgetBase
    let style: WidgetStyle

    private var isDark: Bool { base == .dark }

    // MARK: Shell
    /// Only frosted mode uses NSVisualEffectView/ultraThinMaterial.
    /// Transparent = clear window with thin tint only; Solid = opaque fill.
    var shellUseMaterial: Bool  { style == .frosted }
    var shellTintColor:   Color { isDark ? .black : .white }
    var shellTintOpacity: Double {
        switch style {
        case .solid:       return 0.0
        case .frosted:     return isDark ? 0.52 : 0.22
        case .transparent: return isDark ? 0.10 : 0.08   // thin tint, no blur
        }
    }
    var shellSolidFill: Color {
        isDark ? Color(red: 0.10, green: 0.10, blue: 0.12)
               : Color(red: 0.97, green: 0.97, blue: 0.99)
    }

    // MARK: Text
    var textPrimary:   Color { isDark ? .white                    : Color(red: 0.08, green: 0.08, blue: 0.10) }
    var textSecondary: Color { isDark ? .white.opacity(0.55)      : .black.opacity(0.60) }
    var textTertiary:  Color { isDark ? .white.opacity(0.35)      : .black.opacity(0.42) }
    var textDim:       Color { isDark ? .white.opacity(0.18)      : .black.opacity(0.28) }
    var textOff:       Color { isDark ? .white.opacity(0.12)      : .black.opacity(0.18) }

    // MARK: Row tiles  (white on dark → lighter; black on light → darker)
    var rowTile:           Color  { isDark ? .white : .black }
    var rowOffOpacity:     Double { isDark ? 0.03 : 0.05 }
    var rowEnabledOpacity: Double { isDark ? 0.06 : 0.07 }
    var rowActiveOpacity:  Double { isDark ? 0.09 : 0.11 }

    // MARK: Borders
    var borderHigh: Color { isDark ? .white.opacity(0.20) : .white.opacity(0.45) }
    var borderLow:  Color { isDark ? .white.opacity(0.05) : .black.opacity(0.06) }
    var borderOff:  Color { isDark ? .white.opacity(0.13) : .black.opacity(0.12) }
    var separator:  Color { isDark ? .white.opacity(0.07) : .black.opacity(0.08) }

    // MARK: Specular highlight — always white (glass refraction catch)
    /// Reduced for light mode — white on white is less visible; contrast comes from the border.
    var specularColor:   Color  { .white }
    var specularOpacity: Double { isDark ? 0.13 : 0.22 }

    // MARK: Icons & controls
    var iconCircleBg:  Color { isDark ? .white.opacity(0.08) : .black.opacity(0.06) }
    var iconOff:       Color { isDark ? .white.opacity(0.15) : .black.opacity(0.18) }
    var iconFaint:     Color { isDark ? .white.opacity(0.06) : .black.opacity(0.05) }
    var dotOff:        Color { isDark ? .white.opacity(0.10) : .black.opacity(0.10) }

    // MARK: Mode bar
    var modeIconActive:   Color { textPrimary }
    var modeIconInactive: Color { isDark ? .white.opacity(0.28) : .black.opacity(0.28) }
    var modeBgActive:     Color { isDark ? .white.opacity(0.13) : .black.opacity(0.09) }
    var modeBorderActive: Color { isDark ? .white.opacity(0.18) : .black.opacity(0.13) }

    // MARK: Canvas, logs, dock
    var canvasBg: Color {
        switch (base, style) {
        case (.dark,  _):      return .black.opacity(0.58)
        case (.light, .solid): return Color(red: 0.90, green: 0.90, blue: 0.93)
        case (.light, _):      return .black.opacity(0.06)
        }
    }
    var logBg:         Color { isDark ? .black.opacity(0.45) : .black.opacity(0.05) }
    var historyPill:   Color { isDark ? .black.opacity(0.45) : .black.opacity(0.10) }
    var dockSeparator: Color { isDark ? .white.opacity(0.14) : .black.opacity(0.12) }
    var dockCircleBg:  Color { isDark ? .black.opacity(0.45) : .black.opacity(0.08) }
}

// MARK: - Widget View

struct WidgetView: View {
    let state:       PillState
    let audioLevel:  Float
    let pillMode:    PillMode
    @Binding var collapseLevel: WidgetCollapseLevel
    let onOpenPanel:          () -> Void
    let onTogglePause:        () -> Void
    let onCycleMode:          () -> Void
    let onSetMode:            (PillMode) -> Void
    let onToggleLocalModel:   () -> Void
    let onToggleCode:         () -> Void
    let onToggleSpeakerMode:  () -> Void
    let onToggleMusicMode:    () -> Void
    let onToggleWhatsApp:     () -> Void
    let onSessionConfigure:   () -> Void
    let onSessionPlay:        () -> Void
    let onSessionPause:       () -> Void
    let onSessionStop:        () -> Void

    /// Live pipeline stage rows — matched by .kind
    var pipelineStages:      [WidgetStageRow] = []
    var isLocalModelEnabled: Bool = true
    var isCodeEnabled:       Bool = false
    var isMultiSpeaker:      Bool = false
    var isMusicMode:         Bool = false
    var isWhatsAppEnabled:   Bool = false
    var sessionLifecycle: SessionLifecycleState = .undefined
    /// Live log lines (max 2) from AutoClawdLogger
    var logLines: [(dot: Color, text: String, time: String)] = []
    /// Current AI canvas content
    var aiCanvasContent: AnyView? = nil
    /// Subtitle shown on Analysis row when enabled but idle (e.g. "14 tasks found")
    var analysisIdleSubtitle: String = "Ready"
    /// Subtitle shown on Execution row when enabled but idle (e.g. "3 tasks queued")
    var executionIdleSubtitle: String = "Ready"
    /// Canvas history passed from parent — index 0 = oldest, last = most recent past
    var canvasSnapshots: [CanvasSnapshot] = []
    /// Colour / material appearance tokens — drives dark/light/solid/frosted/transparent
    var appearance: WidgetAppearance = .default
    @State private var historyIndex: Int = 0

    var body: some View {
        Group {
            switch collapseLevel {
            case .icon:       iconWidget
            case .headerOnly: headerOnlyWidget
            default:          fullWidget
            }
        }
        .frame(width: collapseLevel.width, height: collapseLevel.height)
        .background(Color.clear)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: collapseLevel)
    }

    // MARK: - Icon

    @ViewBuilder
    private var iconWidget: some View {
#if NATIVE_GLASS_AVAILABLE
        if #available(macOS 26, *) {
            logoMark(size: 34, radius: 14)
                .frame(width: 52, height: 52)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 6)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { collapseLevel = collapseLevel.prev() } }
        } else {
            iconWidgetLegacy
        }
#else
        iconWidgetLegacy
#endif
    }

    private var iconWidgetLegacy: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.13).opacity(0.88))
            logoMark(size: 34, radius: 14)
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 6)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { collapseLevel = collapseLevel.prev() } }
    }

    // MARK: - Header Only

    private var headerOnlyWidget: some View {
        VStack(spacing: 0) {
            header
            audioRow
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .liquidGlass(cornerRadius: 22, appearance: appearance)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { collapseLevel = collapseLevel.prev() } }
    }

    // MARK: - Full / Compact / Expanded

    private var fullWidget: some View {
        VStack(spacing: 0) {
            header

            if collapseLevel != .compact {
                statusSection
            }

            Rectangle().fill(appearance.separator).frame(height: 1).padding(.horizontal, 12)

            modeBar

            aiCanvasWithHistory
                .frame(height: canvasHeight)

            logSection

            if collapseLevel != .compact {
                dock
            }
        }
        .liquidGlass(cornerRadius: 26, appearance: appearance)
    }

    private var canvasHeight: CGFloat {
        switch collapseLevel {
        case .expanded: return 220
        case .compact:  return 240
        default:        return 160
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onOpenPanel) {
                HStack(spacing: 8) {
                    logoMark(size: 28, radius: 9)
                    Text("autoclawd")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(appearance.textPrimary)
                        .kerning(-0.4)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            // Expand button (only if not already at expanded)
            if collapseLevel != .expanded {
                Button {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                        collapseLevel = collapseLevel.prev()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(appearance.textTertiary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(appearance.iconCircleBg))
                }
                .buttonStyle(.plain)
            }
            // Collapse / minimize button
            Button {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                    collapseLevel = collapseLevel.next()
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(appearance.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(appearance.iconCircleBg))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
    }

    // MARK: - Status Section (mic + analysis + execution rows)

    private var statusSection: some View {
        VStack(spacing: 6) {
            audioRow
            stageRow(kind: .analysis,
                     icon: "brain",
                     activeColor: Color(red: 0.25, green: 0.55, blue: 1.0),
                     title: "Analysis",
                     idleSubtitle: analysisIdleSubtitle,
                     enabled: isLocalModelEnabled,
                     onToggle: onToggleLocalModel)
            stageRow(kind: .execution,
                     icon: "chevron.left.forwardslash.chevron.right",
                     activeColor: Color(red: 0.58, green: 0.2, blue: 0.92),
                     title: "Execution",
                     idleSubtitle: executionIdleSubtitle,
                     enabled: isCodeEnabled,
                     onToggle: onToggleCode)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    // Mic / audio row — tap to toggle listening
    private var audioRow: some View {
        let isOn = (state == .listening)
        return HStack(spacing: 10) {
            iconCircle(systemName: "mic.fill",
                       iconColor: isOn ? .green : appearance.iconOff)
            VStack(alignment: .leading, spacing: 3) {
                waveformBars
                Text(state == .paused ? "Paused · tap to resume" : "Apple SF · LOCAL")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(appearance.textSecondary)
            }
            Spacer()
            Circle()
                .fill(isOn ? Color.green : appearance.dotOff)
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background {
            ZStack {
                // Glass tile base — slightly lighter than widget background
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(appearance.rowTile.opacity(isOn ? appearance.rowActiveOpacity : appearance.rowOffOpacity))
                // Green tint when listening
                if isOn {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.green.opacity(0.16), Color.green.opacity(0.07)],
                            startPoint: .top, endPoint: .bottom))
                }
                // Top specular highlight — mimics glass refraction
                LinearGradient(
                    colors: [appearance.specularColor.opacity(appearance.specularOpacity), .clear],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.55)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                // Gradient border: bright catch at top, subtle at bottom
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                isOn ? Color.green.opacity(0.38) : appearance.borderOff,
                                isOn ? Color.green.opacity(0.08) : appearance.borderLow,
                            ],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            }
        }
        .intelligenceGlow(color: .green, cornerRadius: 20, state: isOn ? .thinking : .off)
        .contentShape(Rectangle())
        .onTapGesture { onTogglePause() }
    }

    /// Tappable stage row — 3 states: active (pipeline running) / idle-enabled (ON but idle) / off.
    /// When enabled, mirrors the mic row's visual language: colored gradient background +
    /// colored border + colored icon + colored dot — all derived from `activeColor`.
    private func stageRow(
        kind: WidgetStageKind,
        icon: String,
        activeColor: Color,
        title: String,
        idleSubtitle: String = "Ready",
        enabled: Bool,
        onToggle: @escaping () -> Void
    ) -> some View {
        let active = pipelineStages.first(where: { $0.kind == kind })
        let isActive = active != nil

        return HStack(spacing: 10) {
            iconCircle(
                systemName: icon,
                iconColor: isActive ? activeColor
                         : (enabled ? activeColor.opacity(0.82) : appearance.iconFaint)
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(active?.title ?? title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isActive ? appearance.textPrimary
                                   : (enabled ? appearance.textSecondary : appearance.textOff))
                Text(active?.sub1 ?? (enabled ? idleSubtitle : "Off"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isActive ? appearance.textSecondary
                                   : (enabled ? appearance.textTertiary : appearance.textOff.opacity(0.6)))
                if let sub2 = active?.sub2, !sub2.isEmpty {
                    Text(sub2)
                        .font(.system(size: 8))
                        .foregroundColor(appearance.textTertiary)
                }
            }
            Spacer()
            Circle()
                .fill(isActive ? activeColor.opacity(0.90)
                    : (enabled ? activeColor.opacity(0.65) : appearance.dotOff))
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background {
            ZStack {
                // Glass tile base — slightly lighter than widget shell
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(appearance.rowTile.opacity(isActive ? appearance.rowActiveOpacity : (enabled ? appearance.rowEnabledOpacity : appearance.rowOffOpacity)))
                // Colour tint when enabled or active
                if isActive || enabled {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(
                            colors: [
                                activeColor.opacity(isActive ? 0.20 : 0.10),
                                activeColor.opacity(isActive ? 0.08 : 0.04),
                            ],
                            startPoint: .top, endPoint: .bottom))
                }
                // Top specular highlight — glass refraction edge
                LinearGradient(
                    colors: [appearance.specularColor.opacity(appearance.specularOpacity), .clear],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.55)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                // Gradient border: bright top catch, subtle bottom
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                isActive ? activeColor.opacity(0.42) : (enabled ? activeColor.opacity(0.24) : appearance.borderOff),
                                isActive ? activeColor.opacity(0.08) : (enabled ? activeColor.opacity(0.06) : appearance.borderLow),
                            ],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            }
        }
        .intelligenceGlow(
            color: activeColor,
            cornerRadius: 20,
            state: isActive ? .thinking : (enabled ? .enabled : .off)
        )
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }

    // MARK: - Mode Bar

    private var modeBar: some View {
        HStack(spacing: 0) {
            ForEach(PillMode.allCases, id: \.self) { mode in
                Button { onSetMode(mode) } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(pillMode == mode ? appearance.modeIconActive : appearance.modeIconInactive)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(pillMode == mode ? appearance.modeBgActive : .clear)
                                .overlay(pillMode == mode
                                    ? RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(appearance.modeBorderActive, lineWidth: 1)
                                    : nil)
                        )
                        .contentShape(Rectangle())   // full frame is tappable, not just the icon
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .frame(height: 46)
    }

    // MARK: - AI Canvas with History Navigation

    private var aiCanvasWithHistory: some View {
        // Index 0 = "Now" (live), 1..n = history newest→oldest
        let showingLive = (historyIndex == 0)
        let shownContent: AnyView? = showingLive
            ? aiCanvasContent
            : (historyIndex - 1 < canvasSnapshots.count
                ? canvasSnapshots[historyIndex - 1].content
                : nil)

        return ZStack(alignment: .topTrailing) {
            // Canvas content
            ZStack {
                if let content = shownContent {
                    content
                } else {
                    idlePlaceholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // History navigation pill — shown whenever there's at least one past snapshot
            if !canvasSnapshots.isEmpty {
                HStack(spacing: 4) {
                    // ← go further back
                    if historyIndex < canvasSnapshots.count {
                        navButton(icon: "chevron.left") {
                            withAnimation { historyIndex += 1 }
                        }
                    }
                    Text(showingLive ? "Now" : canvasSnapshots[historyIndex - 1].label)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(appearance.textSecondary.opacity(showingLive ? 1.0 : 0.70))
                    // → come forward
                    if historyIndex > 0 {
                        navButton(icon: "chevron.right") {
                            withAnimation { historyIndex -= 1 }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(appearance.logBg))
                .padding(6)
            }
        }
        // Reset to live whenever new content arrives
        .onChange(of: canvasSnapshots.count) { _ in
            historyIndex = 0
        }
        .background {
            ZStack {
                // Slightly translucent dark glass for the canvas area
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(appearance.canvasBg)
                // Top specular hint
                LinearGradient(
                    colors: [.white.opacity(0.05), .clear],
                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                // Subtle inner border
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(appearance.borderOff.opacity(0.5), lineWidth: 0.8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func navButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(appearance.textSecondary)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
    }

    private var idlePlaceholder: some View {
        VStack(spacing: 6) {
            Circle().fill(appearance.dotOff.opacity(0.7)).frame(width: 8, height: 8)
            Text("Listening…")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(appearance.textDim)
        }
    }

    // MARK: - Log Section

    private var logSection: some View {
        let lines: [(dot: Color, text: String, time: String)] = logLines.isEmpty
            ? [(dot: Color.green,          text: "Ready",         time: ""),
               (dot: Color(hex: "818CF8"), text: "Pipeline idle", time: "")]
            : Array(logLines.prefix(2))

        return VStack(spacing: 5) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                logBar(dot: line.dot, text: line.text, time: line.time)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private func logBar(dot: Color, text: String, time: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(dot).frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 9))
                .foregroundColor(appearance.textSecondary)
                .lineLimit(1)
            Spacer()
            if !time.isEmpty {
                Text(time)
                    .font(.system(size: 8))
                    .foregroundColor(appearance.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(appearance.logBg)
        )
    }

    // MARK: - Dock (speaker mode + music toggle)

    private var dock: some View {
        HStack(spacing: 0) {
            // Session lifecycle controls (left side)
            sessionDockControls

            Rectangle().fill(appearance.dockSeparator).frame(width: 1, height: 20)

            // Music mode toggle
            dockToggle(
                icon:    "music.note",
                active:  isMusicMode,
                color:   Color(red: 1.0, green: 0.5, blue: 0.1),
                action:  onToggleMusicMode
            )

            Rectangle().fill(appearance.dockSeparator).frame(width: 1, height: 20)

            // WhatsApp toggle
            dockToggle(
                icon:   "message.fill",
                active: isWhatsAppEnabled,
                color:  Color(red: 0.07, green: 0.73, blue: 0.40),
                action: onToggleWhatsApp
            )
        }
        .frame(height: 50)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var sessionDockControls: some View {
        let green = Color(red: 0.2, green: 0.78, blue: 0.44)
        let yellow = Color(red: 0.95, green: 0.75, blue: 0.1)
        let red = Color(red: 0.92, green: 0.26, blue: 0.24)

        switch sessionLifecycle {
        case .undefined:
            // Plus button to open config panel
            dockToggle(
                icon:   "plus.circle",
                active: false,
                color:  green,
                action: onSessionConfigure
            )
        case .configuring:
            // Highlighted plus (config panel is open)
            dockToggle(
                icon:   "plus.circle.fill",
                active: true,
                color:  green,
                action: onSessionConfigure
            )
        case .ready:
            // Play button (green) to start session
            dockToggle(
                icon:   "play.fill",
                active: true,
                color:  green,
                action: onSessionPlay
            )
        case .active:
            // Pause (yellow) + Stop (red)
            dockToggle(
                icon:   "pause.fill",
                active: true,
                color:  yellow,
                action: onSessionPause
            )
            dockToggle(
                icon:   "stop.fill",
                active: true,
                color:  red,
                action: onSessionStop
            )
        case .paused:
            // Play (green, resume) + Stop (red)
            dockToggle(
                icon:   "play.fill",
                active: true,
                color:  green,
                action: onSessionPlay
            )
            dockToggle(
                icon:   "stop.fill",
                active: true,
                color:  red,
                action: onSessionStop
            )
        }
    }

    private func dockToggle(icon: String, active: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(active ? color : appearance.textOff)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(active ? color.opacity(0.14) : Color.clear)
                        .overlay(active
                            ? RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(color.opacity(0.28), lineWidth: 1)
                            : nil)
                )
        }
        .buttonStyle(.plain)
    }

    private func dockCircle(color: Color, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color).frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(appearance.textPrimary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared Helpers

    private func iconCircle(systemName: String, iconColor: Color) -> some View {
        ZStack {
            Circle().fill(appearance.iconCircleBg)
                .frame(width: 40, height: 40)
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(iconColor)
        }
    }

    private func logoMark(size: CGFloat, radius: CGFloat) -> some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private var waveformBars: some View {
        HStack(spacing: 2) {
            ForEach(0..<14, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(state == .listening ? Color.green : appearance.iconOff)
                    .frame(width: 3, height: barH(i))
                    .animation(.easeOut(duration: 0.08), value: audioLevel)
            }
        }
        .frame(height: 28)
    }

    private func barH(_ i: Int) -> CGFloat {
        guard state == .listening else { return 4 }
        let wave = sin(Double(i) * 0.6 + Double(audioLevel) * 10) * 0.5 + 0.5
        return 4 + wave * Double(audioLevel) * 22
    }
}

// MARK: - Liquid Glass

struct LiquidGlass: ViewModifier {
    let cornerRadius: CGFloat
    var appearance: WidgetAppearance = .default

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // System-level blur — only rendered when not in solid mode
                    if appearance.shellUseMaterial {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                    // Solid mode base fill
                    if !appearance.shellUseMaterial {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(appearance.shellSolidFill)
                    }
                    // Colour tint (black for dark-frosted, white for light-frosted, nil for solid)
                    if appearance.shellTintOpacity > 0 {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(appearance.shellTintColor.opacity(appearance.shellTintOpacity))
                    }
                    // Top-edge specular highlight
                    LinearGradient(
                        colors: [appearance.specularColor.opacity(appearance.specularOpacity * 0.80), .clear],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.22)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [appearance.borderHigh, appearance.borderLow],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // Lighter shadow for light/transparent modes — heavy shadow on pale glass looks wrong
            .shadow(color: .black.opacity(appearance.base == .dark ? 0.50 : 0.20), radius: appearance.base == .dark ? 36 : 22, y: appearance.base == .dark ? 18 : 10)
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }
}

extension View {
    @ViewBuilder
    func liquidGlass(cornerRadius: CGFloat, appearance: WidgetAppearance = .default) -> some View {
#if NATIVE_GLASS_AVAILABLE
        if #available(macOS 26, *) {
            self.nativeGlass(cornerRadius: cornerRadius, appearance: appearance)
        } else {
            self.modifier(LiquidGlass(cornerRadius: cornerRadius, appearance: appearance))
        }
#else
        self.modifier(LiquidGlass(cornerRadius: cornerRadius, appearance: appearance))
#endif
    }
}

#if NATIVE_GLASS_AVAILABLE
// Native Liquid Glass — macOS 26+ only. Replaces the custom LiquidGlass modifier with
// the system .glassEffect() API which correctly samples the compositor, handles
// accessibility (reduced transparency, high contrast) and adapts to the OS appearance.
@available(macOS 26, *)
private extension View {
    @ViewBuilder
    func nativeGlass(cornerRadius: CGFloat, appearance: WidgetAppearance) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let shadowRadius: CGFloat = appearance.base == .dark ? 36 : 22
        let shadowY:      CGFloat = appearance.base == .dark ? 18 : 10
        let shadowOpacity: Double = appearance.base == .dark ? 0.50 : 0.20
        if appearance.style == .solid {
            // Solid mode: no blur, just the opaque fill with the same border + shadow.
            self
                .background(shape.fill(appearance.shellSolidFill))
                .overlay {
                    shape.stroke(
                        LinearGradient(colors: [appearance.borderHigh, appearance.borderLow],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                }
                .clipShape(shape)
                .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        } else if appearance.style == .transparent {
            // Transparent: no background at all — content floats, only border + shadow.
            self
                .overlay {
                    shape.stroke(
                        LinearGradient(colors: [appearance.borderHigh, appearance.borderLow],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                }
                .shadow(color: .black.opacity(shadowOpacity * 0.5), radius: shadowRadius * 0.5, y: shadowY * 0.5)
        } else {
            // Frosted: native compositor glass.
            self
                .glassEffect(Glass.regular, in: shape)
                .overlay {
                    shape.stroke(
                        LinearGradient(colors: [appearance.borderHigh, appearance.borderLow],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                }
                .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
    }
}
#endif

// MARK: - Intelligence Glow Effect

/// Gentle breathing glow rendered when a row is enabled but idle.
/// A single soft stroke pulses opacity from low → high → low on repeat.
private struct EnabledGlow: View {
    let color: Color
    let cornerRadius: CGFloat
    @State private var opacity: Double = 0.18
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(color.opacity(opacity), lineWidth: 2)
            .blur(radius: 8)
            .allowsHitTesting(false)
            .onAppear {
                guard !reduceMotion else { opacity = 0.38; return }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                    opacity = 0.48          // narrower range = more subtle breath
                }
            }
    }
}

/// Apple Intelligence–style multi-layer rotating shimmer for actively processing rows.
/// Four strokeBorder layers with increasing line width + blur create depth; the
/// AngularGradient's stops shuffle every 0.45 s to animate the flow.
private struct ThinkingGlow: View {
    let color: Color
    let cornerRadius: CGFloat
    @State private var stops: [Gradient.Stop]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(color: Color, cornerRadius: CGFloat) {
        self.color = color
        self.cornerRadius = cornerRadius
        _stops = State(initialValue: ThinkingGlow.makeStops(color: color))
    }

    var body: some View {
        let gradient = AngularGradient(gradient: Gradient(stops: stops), center: .center)
        let shape    = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            shape.strokeBorder(gradient, lineWidth:  3)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.90), value: stops)
            shape.strokeBorder(gradient, lineWidth:  6).blur(radius:  4)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.15), value: stops)
            shape.strokeBorder(gradient, lineWidth: 10).blur(radius:  9)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.45), value: stops)
            shape.strokeBorder(gradient, lineWidth: 14).blur(radius: 13)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.80), value: stops)
        }
        .allowsHitTesting(false)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.75))   // slower shuffle = smoother flow
                stops = Self.makeStops(color: color)
            }
        }
    }

    /// Randomises the gradient stop positions each call to create organic movement.
    /// Mixes the base colour at varying opacities with white flashes for tonal depth.
    /// All stops stay within the base colour's hue — no white flashes.
    /// Variation comes purely from opacity (bright → dim → bright) giving a subtle
    /// colour-only shimmer rather than a "white strobe" effect.
    static func makeStops(color: Color) -> [Gradient.Stop] {
        [
            color.opacity(0.95),
            color.opacity(0.20),   // near-transparent gap — creates the shimmer without white
            color.opacity(0.60),
            color.opacity(0.88),
            color.opacity(0.16),   // very dim — another gap
            color.opacity(0.72),
        ]
        .map  { Gradient.Stop(color: $0, location: Double.random(in: 0...1)) }
        .sorted { $0.location < $1.location }
    }
}

private struct IntelligenceGlowModifier: ViewModifier {
    let color: Color
    let cornerRadius: CGFloat
    let glowState: GlowState

    func body(content: Content) -> some View {
        content.overlay {
            switch glowState {
            case .off:      EmptyView()
            case .enabled:  EnabledGlow(color: color, cornerRadius: cornerRadius)
            case .thinking: ThinkingGlow(color: color, cornerRadius: cornerRadius)
            }
        }
    }
}

extension View {
    /// Apply a per-row glow that shifts between off / breathing-pulse / thinking-shimmer.
    func intelligenceGlow(color: Color, cornerRadius: CGFloat = 20, state: GlowState) -> some View {
        modifier(IntelligenceGlowModifier(color: color, cornerRadius: cornerRadius, glowState: state))
    }
}

// MARK: - Color(hex:)

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var n: UInt64 = 0
        Scanner(string: h).scanHexInt64(&n)
        self.init(red:   Double((n >> 16) & 0xFF) / 255,
                  green: Double((n >>  8) & 0xFF) / 255,
                  blue:  Double( n        & 0xFF) / 255)
    }
}
