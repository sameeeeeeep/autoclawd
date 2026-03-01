import SwiftUI

// MARK: - WorldTimeView

struct WorldTimeView: View {
    @ObservedObject var appState: AppState

    @State private var selectedEpisodeIndex: Int = 0
    @State private var seekTime: TimeInterval = 0
    @State private var viewMode: String = "now" // "now" or "replay"

    // Real data loaded from stores
    @State private var episodes: [Episode] = []
    @State private var transcriptRecords: [TranscriptRecord] = []

    // Responsive panel state
    @State private var showEpisodes = false
    @State private var showTranscript = false

    // Drag state for map dots
    @State private var dragStarts: [UUID: CGPoint] = [:]

    // Waveform animation
    @State private var waveformHeights: [CGFloat] = (0..<50).map { _ in CGFloat.random(in: 0.15...1.0) }
    @State private var waveformTimer: Timer?

    private var selectedEpisode: Episode {
        guard !episodes.isEmpty, selectedEpisodeIndex < episodes.count else {
            // Fallback: today's episode with no data
            return Episode(id: UUID(), date: Date(), title: nil, summary: nil, segments: [])
        }
        return episodes[selectedEpisodeIndex]
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
        GeometryReader { geo in
            let width = geo.size.width
            // Breakpoints: <500 = compact (no side panels), 500-750 = medium (episodes only), 750+ = full
            let showEpisodeInline = width >= 500
            let showTranscriptInline = width >= 750

            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    if showEpisodeInline {
                        episodeListPanel
                    }
                    centerPlayerPanel(
                        showEpisodeToggle: !showEpisodeInline,
                        showTranscriptToggle: !showTranscriptInline
                    )
                    if showTranscriptInline {
                        transcriptPanel
                    }
                }

                // Overlay panels for compact modes
                if !showEpisodeInline && showEpisodes {
                    overlayPanel(alignment: .leading) {
                        episodeListPanel
                            .frame(width: min(280, width * 0.75))
                    }
                }

                if !showTranscriptInline && showTranscript {
                    overlayPanel(alignment: .trailing) {
                        transcriptPanel
                            .frame(width: min(280, width * 0.75))
                    }
                }
            }
        }
        .onAppear {
            loadEpisodes()
            loadTranscripts()
            seekTime = currentDaySeconds()
            updateViewMode()
        }
        .onChange(of: selectedEpisodeIndex) { _ in
            loadTranscriptsForSelectedEpisode()
            updateViewMode()
        }
    }

    // MARK: - Overlay Panel Wrapper

    private func overlayPanel<Content: View>(alignment: Alignment, @ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: alignment) {
            // Scrim
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showEpisodes = false
                        showTranscript = false
                    }
                }

            content()
                .background(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 12)
                .transition(.move(edge: alignment == .leading ? .leading : .trailing))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    private func loadEpisodes() {
        let sessions = SessionStore.shared.recentSessions(limit: 100)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Group sessions by day
        var dayMap: [Date: [SessionRecord]] = [:]
        for session in sessions {
            let dayStart = cal.startOfDay(for: session.startedAt)
            dayMap[dayStart, default: []].append(session)
        }

        // Always include today even if no sessions
        if dayMap[today] == nil {
            dayMap[today] = []
        }

        // Sort days descending (most recent first)
        let sortedDays = dayMap.keys.sorted(by: >)

        episodes = sortedDays.map { dayStart -> Episode in
            let daySessions = dayMap[dayStart] ?? []

            // Build segments from sessions (start/end times as seconds-of-day)
            let segments: [(start: TimeInterval, end: TimeInterval)] = daySessions.compactMap { session in
                let start = session.startedAt.timeIntervalSince(dayStart)
                let end: TimeInterval
                if let endDate = session.endedAt {
                    end = endDate.timeIntervalSince(dayStart)
                } else if cal.isDateInToday(session.startedAt) {
                    // Ongoing session today: extend to current time
                    end = Date().timeIntervalSince(dayStart)
                } else {
                    // Past session with no end time: estimate 30 min
                    end = start + 1800
                }
                // Clamp to 0..86400
                let clampedStart = max(0, min(86400, start))
                let clampedEnd = max(clampedStart, min(86400, end))
                return (start: clampedStart, end: clampedEnd)
            }.sorted { $0.start < $1.start }

            // Use the first session's snippet as title, combine all for summary
            let title: String? = {
                let snippets = daySessions.compactMap { s -> String? in
                    s.transcriptSnippet.isEmpty ? nil : s.transcriptSnippet
                }
                return snippets.first
            }()

            let summary: String? = {
                let placeName = daySessions.compactMap { $0.placeName }.first
                let sessionCount = daySessions.count
                if sessionCount == 0 { return nil }
                var parts: [String] = []
                parts.append("\(sessionCount) session\(sessionCount == 1 ? "" : "s")")
                if let place = placeName { parts.append("at \(place)") }
                let totalDuration = segments.reduce(0.0) { $0 + ($1.end - $1.start) }
                let minutes = Int(totalDuration / 60)
                if minutes > 0 { parts.append("\(minutes) min recorded") }
                return parts.joined(separator: " \u{00B7} ")
            }()

            return Episode(
                id: UUID(),
                date: dayStart,
                title: title,
                summary: summary,
                segments: segments
            )
        }

        // If today is selected, set seek to current time
        if !episodes.isEmpty, episodes[0].isToday {
            selectedEpisodeIndex = 0
            seekTime = currentDaySeconds()
        }
    }

    private func loadTranscripts() {
        transcriptRecords = appState.recentTranscripts()
        filterTranscriptsForSelectedEpisode()
    }

    private func loadTranscriptsForSelectedEpisode() {
        let allRecent = appState.recentTranscripts()
        let ep = selectedEpisode
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: ep.date)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        transcriptRecords = allRecent.filter { record in
            record.timestamp >= dayStart && record.timestamp < dayEnd
        }.sorted { $0.timestamp < $1.timestamp }
    }

    private func filterTranscriptsForSelectedEpisode() {
        guard !episodes.isEmpty else { return }
        let ep = selectedEpisode
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: ep.date)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        transcriptRecords = transcriptRecords.filter { record in
            record.timestamp >= dayStart && record.timestamp < dayEnd
        }.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - View Mode

    private func updateViewMode() {
        guard !episodes.isEmpty else { return }
        let ep = episodes[selectedEpisodeIndex]
        if ep.isToday {
            viewMode = "now"
            seekTime = currentDaySeconds()
            startWaveformAnimation()
        } else {
            viewMode = "replay"
            // Set seek to start of first segment, or noon
            seekTime = ep.segments.first?.start ?? 43200
            stopWaveformAnimation()
        }
    }

    // MARK: - Waveform Animation

    private func startWaveformAnimation() {
        stopWaveformAnimation()
        waveformTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.12)) {
                    if appState.isListening {
                        // Use real audio level to drive waveform intensity
                        let level = CGFloat(appState.audioLevel)
                        waveformHeights = (0..<50).map { _ in
                            let base = CGFloat.random(in: 0.05...0.3)
                            return min(1.0, base + level * CGFloat.random(in: 0.5...1.0))
                        }
                    } else {
                        // Flat bars when not listening
                        waveformHeights = (0..<50).map { _ in CGFloat(0.08) }
                    }
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
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Episodes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                Text(seasonCode)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if episodes.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Text("No episodes yet")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Episodes appear as you record throughout the day.")
                        .font(.system(size: 9))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
        }
        .frame(minWidth: 160, idealWidth: 220, maxWidth: 280)
        .overlay(
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(width: 0.5),
            alignment: .trailing
        )
    }

    // MARK: - Episode Card

    private func episodeCard(episode: Episode, index: Int) -> some View {
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
                            .fill(Color(NSColor.windowBackgroundColor).opacity(0.8))
                        if episode.isToday {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                        } else if !episode.segments.isEmpty {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9))
                                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        }
                    }
                    .frame(width: 38, height: 26)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(episode.episodeCode)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                        Text(dateFormatter.string(from: episode.date))
                            .font(.system(size: 9))
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
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
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                // Summary (only when selected)
                if isSelected, let summary = episode.summary {
                    Text(summary)
                        .font(.system(size: 9))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        .lineSpacing(9 * 0.55) // 1.55 line height
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Center Panel: Player Area

    private func centerPlayerPanel(showEpisodeToggle: Bool, showTranscriptToggle: Bool) -> some View {
        VStack(spacing: 10) {
            // Compact toggle bar (shown when panels are collapsed)
            if showEpisodeToggle || showTranscriptToggle {
                compactToggleBar(showEpisodeToggle: showEpisodeToggle, showTranscriptToggle: showTranscriptToggle)
            }
            playerHeaderBar
            squareMap
            tagsRow
            waveformContainer
            seekBar
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func compactToggleBar(showEpisodeToggle: Bool, showTranscriptToggle: Bool) -> some View {
        HStack(spacing: 8) {
            if showEpisodeToggle {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showEpisodes.toggle()
                        showTranscript = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 10))
                        Text("Episodes")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(showEpisodes ? .accentColor : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(showEpisodes ? Color.accentColor.opacity(0.12) : Color(NSColor.windowBackgroundColor).opacity(0.8))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }

            // Episode info when collapsed
            if showEpisodeToggle {
                Text(selectedEpisode.episodeCode)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if showTranscriptToggle {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showTranscript.toggle()
                        showEpisodes = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 10))
                        Text("Transcripts")
                            .font(.system(size: 10, weight: .medium))
                        if !transcriptRecords.isEmpty {
                            Text("\(transcriptRecords.count)")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        }
                    }
                    .foregroundColor(showTranscript ? .accentColor : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(showTranscript ? Color.accentColor.opacity(0.12) : Color(NSColor.windowBackgroundColor).opacity(0.8))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Player Header Bar

    private var playerHeaderBar: some View {
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
                .foregroundColor(.primary)

            Text(dateFormatter.string(from: ep.date))
                .font(.system(size: 10))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))

            if ep.isToday {
                LiveBadge()
            }

            if let title = ep.title {
                Text("— \(title)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            // Right: Now button + Mic toggle
            Button {
                if ep.isToday {
                    viewMode = viewMode == "now" ? "replay" : "now"
                    if viewMode == "now" {
                        seekTime = currentDaySeconds()
                        startWaveformAnimation()
                    } else {
                        stopWaveformAnimation()
                    }
                }
            } label: {
                Text("Now")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(isLive ? Color.red : Color(NSColor.windowBackgroundColor).opacity(0.8))
                    )
                    .overlay(
                        Capsule()
                            .stroke(isLive ? Color.red.opacity(0.5) : Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)

            Button {
                appState.micEnabled.toggle()
            } label: {
                Image(systemName: appState.isListening ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 11))
                    .foregroundColor(appState.isListening ? .accentColor : Color(NSColor.tertiaryLabelColor))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(appState.isListening ? Color.accentColor.opacity(0.18) : Color(NSColor.windowBackgroundColor).opacity(0.8))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 16)
        .overlay(
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Square Map

    private var squareMap: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)

            ZStack(alignment: .topLeading) {
                // Glass background
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
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
                    context.stroke(path, with: .color(Color.primary.opacity(0.03)), lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Location label -- real location from AppState
                Text(appState.locationName.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1)
                    .padding(.top, 12)
                    .padding(.leading, 14)

                // Speaker dots -- real people from AppState (draggable)
                ForEach(Array(appState.people.enumerated()), id: \.element.id) { index, person in
                    if !person.isMusic {
                        let isActive = appState.currentSpeakerID == person.id
                        VStack(spacing: 3) {
                            Circle()
                                .fill(isActive ? person.color : Color.secondary)
                                .frame(
                                    width: isActive ? 14 : 10,
                                    height: isActive ? 14 : 10
                                )
                                .shadow(
                                    color: isActive ? person.color.opacity(0.5) : .clear,
                                    radius: isActive ? 8 : 0
                                )
                            Text(person.name)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 6)
                                .onChanged { drag in
                                    if dragStarts[person.id] == nil {
                                        dragStarts[person.id] = person.mapPosition
                                    }
                                    let start = dragStarts[person.id]!
                                    let newX = start.x + drag.translation.width  / size
                                    let newY = start.y + drag.translation.height / size
                                    appState.people[index].mapPosition = CGPoint(
                                        x: max(0.05, min(0.95, newX)),
                                        y: max(0.05, min(0.95, newY))
                                    )
                                }
                                .onEnded { _ in
                                    dragStarts.removeValue(forKey: person.id)
                                }
                        )
                        .onHover { hovering in
                            if hovering {
                                NSCursor.openHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        .position(
                            x: size * person.mapPosition.x,
                            y: size * person.mapPosition.y
                        )
                    }
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
            // Show location as place tag
            if !appState.locationName.isEmpty {
                TagView(type: .place, label: appState.locationName.lowercased(), small: true)
            }

            // Show current speaker as person tag
            if let speakerName = appState.currentSpeakerName {
                TagView(type: .person, label: speakerName.lowercased(), small: true)
            }

            // Show now-playing song if any
            if let song = appState.nowPlayingSongTitle {
                TagView(type: .status, label: song, small: true)
            }

            Spacer()
        }
    }

    // MARK: - Waveform Container

    private var waveformContainer: some View {
        let locationDisplay = appState.locationName

        return HStack(spacing: 12) {
            // Waveform bars + status
            VStack(spacing: 6) {
                // Bars
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<50, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(isLive ? Color.red.opacity(0.7) : Color.accentColor.opacity(0.6))
                            .frame(width: 2, height: max(3, waveformHeights[i] * 28))
                    }
                }
                .frame(height: 28)

                // Status text
                HStack(spacing: 0) {
                    if isLive && appState.isListening {
                        Text("Listening \u{2022} \(locationDisplay)")
                            .font(.system(size: 9))
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    } else if isLive && !appState.isListening {
                        Text("Mic off \u{2022} \(locationDisplay)")
                            .font(.system(size: 9))
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    } else {
                        Text("Paused at \(formatTime(seekTime))")
                            .font(.system(size: 9))
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    }
                    Spacer()
                }
            }

            Spacer()

            // Live clock
            if isLive {
                Text(currentTimeString())
                    .font(.system(size: 20, weight: .ultraLight, design: .monospaced))
                    .foregroundColor(.primary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Seek Bar

    private var seekBar: some View {
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
                        .fill(Color(NSColor.windowBackgroundColor).opacity(0.8).opacity(0.05))
                        .frame(height: 5)

                    // Recorded segments
                    ForEach(Array(ep.segments.enumerated()), id: \.offset) { _, segment in
                        let startX = CGFloat(segment.start / totalSeconds) * width
                        let segWidth = CGFloat((segment.end - segment.start) / totalSeconds) * width
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(0.5))
                            .frame(width: max(1, segWidth), height: 5)
                            .offset(x: startX)
                    }

                    // Playhead
                    Circle()
                        .fill(isLive ? Color.red : Color.accentColor)
                        .frame(width: 13, height: 13)
                        .shadow(
                            color: (isLive ? Color.red : Color.accentColor).opacity(0.4),
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
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    if label != "8p" { Spacer() }
                }
            }

            // Current time / total
            HStack {
                Text(formatTime(seekTime))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                Spacer()
                Text(formatTime(totalSeconds))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
            }
        }
    }

    // MARK: - Right Panel: Transcript List

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Transcripts")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                Text("\(transcriptRecords.count)")
                    .font(.system(size: 9))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if transcriptRecords.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Text("No transcripts")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Transcripts will appear here as audio is recorded and processed.")
                        .font(.system(size: 9))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Transcript entries
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(transcriptRecords) { record in
                            transcriptEntry(record: record)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(minWidth: 160, idealWidth: 220, maxWidth: 260)
        .overlay(
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(width: 0.5),
            alignment: .leading
        )
    }

    // MARK: - Transcript Entry

    private func transcriptEntry(record: TranscriptRecord) -> some View {
        let recordDaySeconds = record.timestamp.timeIntervalSince(
            Calendar.current.startOfDay(for: record.timestamp)
        )
        let isActive = abs(recordDaySeconds - seekTime) < 1800 // within 30 min

        let timeFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            return f
        }()

        let previewText = String(record.text.prefix(80))

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(timeFormatter.string(from: record.timestamp))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))

                if let speaker = record.speakerName {
                    TagView(type: .person, label: speaker, small: true)
                }

                Spacer()

                InfoButton()
            }

            if !previewText.isEmpty {
                Text(previewText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .overlay(
            isActive
                ? AnyView(
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.accentColor)
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
