import SwiftUI

// MARK: - Mock Speaker Dot

private struct SpeakerDot: Identifiable {
    let id = UUID()
    let name: String
    let xPercent: CGFloat
    let yPercent: CGFloat
    let isActive: Bool
}

// MARK: - WorldTimeView

struct WorldTimeView: View {
    @ObservedObject var appState: AppState

    @State private var selectedEpisodeIndex: Int = 0
    @State private var seekTime: TimeInterval = 52200 // ~2:30 PM
    @State private var isPlaying: Bool = false
    @State private var micOn: Bool = true
    @State private var viewMode: String = "now" // "now" or "replay"

    // Waveform animation
    @State private var waveformHeights: [CGFloat] = (0..<50).map { _ in CGFloat.random(in: 0.15...1.0) }
    @State private var waveformTimer: Timer?

    private let episodes = Episode.mockEpisodes(count: 14)
    private let transcriptGroups = PipelineGroup.mockData()

    private let speakerDots: [SpeakerDot] = [
        SpeakerDot(name: "You", xPercent: 0.35, yPercent: 0.45, isActive: true),
        SpeakerDot(name: "Mukul", xPercent: 0.65, yPercent: 0.30, isActive: false),
        SpeakerDot(name: "Priya", xPercent: 0.50, yPercent: 0.70, isActive: false),
    ]

    private var selectedEpisode: Episode {
        episodes[selectedEpisodeIndex]
    }

    private var isLive: Bool {
        viewMode == "now"
    }

    private var seasonCode: String {
        let iso = Calendar(identifier: .iso8601)
        let year = iso.component(.yearForWeekOfYear, from: Date()) % 100
        let week = iso.component(.weekOfYear, from: Date())
        return String(format: "Y%02dS%02d", year, week)
    }

    var body: some View {
        HStack(spacing: 0) {
            episodeListPanel
            centerPlayerPanel
            transcriptPanel
        }
        .onAppear {
            updateViewMode()
        }
        .onChange(of: selectedEpisodeIndex) { _ in
            updateViewMode()
        }
    }

    // MARK: - View Mode

    private func updateViewMode() {
        let ep = episodes[selectedEpisodeIndex]
        if ep.isToday {
            viewMode = "now"
            startWaveformAnimation()
        } else {
            viewMode = "replay"
            stopWaveformAnimation()
        }
    }

    // MARK: - Waveform Animation

    private func startWaveformAnimation() {
        stopWaveformAnimation()
        waveformTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.12)) {
                    waveformHeights = (0..<50).map { _ in CGFloat.random(in: 0.15...1.0) }
                }
            }
        }
    }

    private func stopWaveformAnimation() {
        waveformTimer?.invalidate()
        waveformTimer = nil
    }

    // MARK: - Left Panel: Episode List

    private var episodeListPanel: some View {
        let theme = ThemeManager.shared.current

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Episodes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                Text(seasonCode)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(theme.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Episode list
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                        episodeCard(episode: episode, index: index)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 280)
        .overlay(
            Rectangle()
                .fill(theme.glassBorder)
                .frame(width: 0.5),
            alignment: .trailing
        )
    }

    // MARK: - Episode Card

    private func episodeCard(episode: Episode, index: Int) -> some View {
        let theme = ThemeManager.shared.current
        let isSelected = selectedEpisodeIndex == index
        let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "EEE, MMM d"
            return f
        }()

        return Button {
            selectedEpisodeIndex = index
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                // Top row: thumbnail + info
                HStack(spacing: 8) {
                    // Thumbnail
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(theme.glass)
                        if episode.isToday {
                            Circle()
                                .fill(theme.error)
                                .frame(width: 8, height: 8)
                        } else if !episode.segments.isEmpty {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9))
                                .foregroundColor(theme.textTertiary)
                        }
                    }
                    .frame(width: 38, height: 26)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(theme.glassBorder, lineWidth: 0.5)
                    )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(episode.episodeCode)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(theme.textPrimary)
                        Text(dateFormatter.string(from: episode.date))
                            .font(.system(size: 9))
                            .foregroundColor(theme.textTertiary)
                    }

                    if episode.isToday {
                        LiveBadge()
                    }

                    Spacer()

                    InfoButton()
                }

                // AI title
                if let title = episode.title {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isSelected ? theme.textPrimary : theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                // Summary (only when selected)
                if isSelected, let summary = episode.summary {
                    Text(summary)
                        .font(.system(size: 9))
                        .foregroundColor(theme.textTertiary)
                        .lineSpacing(9 * 0.55) // 1.55 line height
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? theme.accent.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected ? theme.accent.opacity(0.18) : Color.clear,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Center Panel: Player Area

    private var centerPlayerPanel: some View {
        VStack(spacing: 10) {
            playerHeaderBar
            squareMap
            tagsRow
            waveformContainer
            seekBar
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Player Header Bar

    private var playerHeaderBar: some View {
        let theme = ThemeManager.shared.current
        let ep = selectedEpisode
        let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "EEEE, MMMM d, yyyy"
            return f
        }()

        return HStack(spacing: 8) {
            // Left: episode code + date + live badge + title
            Text(ep.episodeCode)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(theme.textPrimary)

            Text(dateFormatter.string(from: ep.date))
                .font(.system(size: 10))
                .foregroundColor(theme.textTertiary)

            if ep.isToday {
                LiveBadge()
            }

            if let title = ep.title {
                Text("— \(title)")
                    .font(.system(size: 10))
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            // Right: Now button + Mic toggle
            Button {
                if ep.isToday {
                    viewMode = viewMode == "now" ? "replay" : "now"
                    if viewMode == "now" { startWaveformAnimation() }
                    else { stopWaveformAnimation() }
                }
            } label: {
                Text("Now")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(isLive ? theme.error : theme.glass)
                    )
                    .overlay(
                        Capsule()
                            .stroke(isLive ? theme.error.opacity(0.5) : theme.glassBorder, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)

            Button {
                micOn.toggle()
            } label: {
                Image(systemName: micOn ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 11))
                    .foregroundColor(micOn ? theme.accent : theme.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(micOn ? theme.accent.opacity(0.18) : theme.glass)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(theme.glassBorder, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 16)
        .overlay(
            Rectangle()
                .fill(theme.glassBorder)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Square Map

    private var squareMap: some View {
        let theme = ThemeManager.shared.current

        return GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)

            ZStack(alignment: .topLeading) {
                // Glass background
                RoundedRectangle(cornerRadius: 16)
                    .fill(theme.glass)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(theme.glassBorder, lineWidth: 0.5)
                    )

                // 8x8 grid overlay
                Canvas { context, canvasSize in
                    let cols = 8
                    let rows = 8
                    let cellW = canvasSize.width / CGFloat(cols)
                    let cellH = canvasSize.height / CGFloat(rows)

                    var path = Path()
                    for i in 1..<cols {
                        let x = cellW * CGFloat(i)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    }
                    for j in 1..<rows {
                        let y = cellH * CGFloat(j)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                    }
                    context.stroke(path, with: .color(theme.textPrimary.opacity(0.03)), lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Location label
                Text("MUMBAI")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.textSecondary)
                    .tracking(1)
                    .padding(.top, 12)
                    .padding(.leading, 14)

                // Speaker dots
                ForEach(speakerDots) { dot in
                    VStack(spacing: 3) {
                        Circle()
                            .fill(dot.isActive ? theme.accent : theme.textSecondary)
                            .frame(
                                width: dot.isActive ? 14 : 10,
                                height: dot.isActive ? 14 : 10
                            )
                            .shadow(
                                color: dot.isActive ? theme.accent.opacity(0.5) : .clear,
                                radius: dot.isActive ? 8 : 0
                            )
                        Text(dot.name)
                            .font(.system(size: 9))
                            .foregroundColor(theme.textSecondary)
                    }
                    .position(
                        x: size * dot.xPercent,
                        y: size * dot.yPercent
                    )
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Tags Row

    private var tagsRow: some View {
        HStack(spacing: 6) {
            TagView(type: .place, label: "office", small: true)
            TagView(type: .project, label: "autoclawd", small: true)
            TagView(type: .person, label: "mukul", small: true)
            Spacer()
        }
    }

    // MARK: - Waveform Container

    private var waveformContainer: some View {
        let theme = ThemeManager.shared.current

        return HStack(spacing: 12) {
            // Play/pause button
            Button {
                isPlaying.toggle()
                if isPlaying && isLive {
                    startWaveformAnimation()
                } else {
                    stopWaveformAnimation()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle()
                                .stroke(
                                    isLive ? theme.error : theme.accent,
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(
                            color: (isLive ? theme.error : theme.accent).opacity(0.3),
                            radius: 6
                        )

                    if isPlaying {
                        // Pause icon: two rects
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(isLive ? theme.error : theme.accent)
                                .frame(width: 3.5, height: 14)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(isLive ? theme.error : theme.accent)
                                .frame(width: 3.5, height: 14)
                        }
                    } else {
                        // Play triangle
                        Image(systemName: "play.fill")
                            .font(.system(size: 14))
                            .foregroundColor(isLive ? theme.error : theme.accent)
                            .offset(x: 1)
                    }
                }
            }
            .buttonStyle(.plain)

            // Waveform bars + status
            VStack(spacing: 6) {
                // Bars
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<50, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(isLive ? theme.error.opacity(0.7) : theme.accent.opacity(0.6))
                            .frame(width: 2, height: max(3, waveformHeights[i] * 28))
                    }
                }
                .frame(height: 28)

                // Status text
                HStack(spacing: 0) {
                    if isLive {
                        Text("Listening \u{2022} Mumbai")
                            .font(.system(size: 9))
                            .foregroundColor(theme.textTertiary)
                    } else if isPlaying {
                        Text("Replay \u{2022} \(formatTime(seekTime))")
                            .font(.system(size: 9))
                            .foregroundColor(theme.textTertiary)
                    } else {
                        Text("Paused")
                            .font(.system(size: 9))
                            .foregroundColor(theme.textTertiary)
                    }
                    Spacer()
                }
            }

            Spacer()

            // Live clock
            if isLive {
                Text(currentTimeString())
                    .font(.system(size: 20, weight: .ultraLight, design: .monospaced))
                    .foregroundColor(theme.textPrimary)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Seek Bar

    private var seekBar: some View {
        let theme = ThemeManager.shared.current
        let totalSeconds: TimeInterval = 86400
        let ep = selectedEpisode

        return VStack(spacing: 4) {
            // Bar
            GeometryReader { geo in
                let width = geo.size.width
                let playheadX = CGFloat(seekTime / totalSeconds) * width

                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.glass.opacity(0.05))
                        .frame(height: 5)

                    // Recorded segments
                    ForEach(Array(ep.segments.enumerated()), id: \.offset) { _, segment in
                        let startX = CGFloat(segment.start / totalSeconds) * width
                        let segWidth = CGFloat((segment.end - segment.start) / totalSeconds) * width
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.accent.opacity(0.5))
                            .frame(width: max(1, segWidth), height: 5)
                            .offset(x: startX)
                    }

                    // Playhead
                    Circle()
                        .fill(isLive ? theme.error : theme.accent)
                        .frame(width: 13, height: 13)
                        .shadow(
                            color: (isLive ? theme.error : theme.accent).opacity(0.4),
                            radius: 5
                        )
                        .offset(x: playheadX - 6.5)
                }
                .frame(height: 13)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let fraction = location.x / width
                    seekTime = max(0, min(totalSeconds, TimeInterval(fraction) * totalSeconds))
                    if selectedEpisode.isToday {
                        // If they click before "now", switch to replay
                        let nowSeconds = currentDaySeconds()
                        if seekTime < nowSeconds - 30 {
                            viewMode = "replay"
                            stopWaveformAnimation()
                        }
                    }
                }
            }
            .frame(height: 13)

            // Time labels
            HStack {
                ForEach(["12a", "4a", "8a", "12p", "4p", "8p"], id: \.self) { label in
                    Text(label)
                        .font(.system(size: 8))
                        .foregroundColor(theme.textTertiary)
                    if label != "8p" { Spacer() }
                }
            }

            // Current time / total
            HStack {
                Text(formatTime(seekTime))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(theme.textTertiary)
                Spacer()
                Text(formatTime(totalSeconds))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(theme.textTertiary)
            }
        }
    }

    // MARK: - Right Panel: Transcript List

    private var transcriptPanel: some View {
        let theme = ThemeManager.shared.current

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Transcripts")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                Text("\(transcriptGroups.count)")
                    .font(.system(size: 9))
                    .foregroundColor(theme.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Transcript entries
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(transcriptGroups) { group in
                        transcriptEntry(group: group)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 250)
        .overlay(
            Rectangle()
                .fill(theme.glassBorder)
                .frame(width: 0.5),
            alignment: .leading
        )
    }

    // MARK: - Transcript Entry

    private func transcriptEntry(group: PipelineGroup) -> some View {
        let theme = ThemeManager.shared.current
        let isActive = abs(Double(group.timeSeconds) - seekTime) < 1800 // within 30 min

        let previewText: String = {
            if let cleaned = group.cleanedText {
                return String(cleaned.prefix(80))
            } else if let first = group.rawChunks.first {
                return String(first.text.prefix(80))
            }
            return ""
        }()

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(group.time)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(theme.textTertiary)

                if let person = group.personTag {
                    TagView(type: .person, label: person, small: true)
                }

                if !group.tasks.isEmpty {
                    TagView(type: .action, label: "\(group.tasks.count)", small: true)
                }

                Spacer()

                InfoButton()
            }

            if !previewText.isEmpty {
                Text(previewText)
                    .font(.system(size: 10))
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isActive ? theme.accent.opacity(0.08) : Color.clear)
        )
        .overlay(
            isActive
                ? AnyView(
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(theme.accent)
                            .frame(width: 2)
                        Spacer()
                    }
                )
                : AnyView(EmptyView())
        )
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func currentTimeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    private func currentDaySeconds() -> TimeInterval {
        let cal = Calendar.current
        let now = Date()
        let start = cal.startOfDay(for: now)
        return now.timeIntervalSince(start)
    }
}
