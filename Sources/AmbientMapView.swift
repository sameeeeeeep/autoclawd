import SwiftUI

// MARK: - VoiceDot Model

struct VoiceDot: Identifiable {
    let id: String
    let name: String
    let color: Color
    let position: CGPoint  // 0..1 normalized within canvas
    var isSpeaking: Bool
    let isMe: Bool

    static let mock: [VoiceDot] = [
        VoiceDot(id: "me",
                 name: "You",
                 color: BrutalistTheme.neonGreen,
                 position: CGPoint(x: 0.50, y: 0.58),
                 isSpeaking: false,
                 isMe: true),
        VoiceDot(id: "alex",
                 name: "Alex",
                 color: Color(red: 0.0, green: 0.85, blue: 1.0),
                 position: CGPoint(x: 0.22, y: 0.27),
                 isSpeaking: false,
                 isMe: false),
        VoiceDot(id: "jordan",
                 name: "Jordan",
                 color: Color(red: 1.0, green: 0.65, blue: 0.0),
                 position: CGPoint(x: 0.76, y: 0.31),
                 isSpeaking: true,
                 isMe: false),
        VoiceDot(id: "sam",
                 name: "Sam",
                 color: Color(red: 0.72, green: 0.38, blue: 1.0),
                 position: CGPoint(x: 0.28, y: 0.76),
                 isSpeaking: false,
                 isMe: false),
    ]
}

// MARK: - AmbientMapView

struct AmbientMapView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var nowPlaying: NowPlayingService
    @State private var showEditor = false

    private let mapSize: CGFloat = 200

    init(appState: AppState) {
        self.appState = appState
        self._nowPlaying = ObservedObject(wrappedValue: appState.nowPlaying)
    }

    private var musicDot: VoiceDot? {
        guard nowPlaying.isPlaying else { return nil }
        return VoiceDot(
            id: "music",
            name: nowPlaying.currentTitle ?? "Music",
            color: Color(red: 1.0, green: 0.40, blue: 0.75),  // pink
            position: CGPoint(x: 0.82, y: 0.80),
            isSpeaking: true,
            isMe: false
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)

            // Subtle grid
            Canvas { ctx, size in
                for i in 1..<5 {
                    let x = size.width / 5.0 * CGFloat(i)
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(p, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
                }
                for i in 1..<5 {
                    let y = size.height / 5.0 * CGFloat(i)
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
                }
            }

            // Room name
            Text(appState.locationName.uppercased())
                .font(BrutalistTheme.monoSM)
                .foregroundColor(.white.opacity(0.35))
                .padding(.top, 8)
                .padding(.leading, 10)

            // Edit button (pencil, top-right)
            Button { showEditor.toggle() } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .popover(isPresented: $showEditor, arrowEdge: .trailing) {
                MapEditorView(appState: appState)
            }

            // People dots + music dot
            GeometryReader { geo in
                ForEach(appState.people) { person in
                    let isSpeaking = appState.currentSpeakerID == person.id
                    VoiceDotView(dot: VoiceDot(
                        id: person.id.uuidString,
                        name: person.name,
                        color: person.color,
                        position: person.mapPosition,
                        isSpeaking: isSpeaking,
                        isMe: person.isMe
                    ))
                    .position(
                        x: person.mapPosition.x * geo.size.width,
                        y: person.mapPosition.y * geo.size.height
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            appState.toggleSpeaker(person.id)
                        }
                    }
                }

                if let mDot = musicDot {
                    MusicDotView(dot: mDot, songTitle: nowPlaying.currentTitle, artist: nowPlaying.currentArtist)
                        .position(
                            x: mDot.position.x * geo.size.width,
                            y: mDot.position.y * geo.size.height
                        )
                }
            }
            .padding(16)

            // Border
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .frame(width: mapSize, height: mapSize)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - VoiceDotView

struct VoiceDotView: View {
    let dot: VoiceDot
    @State private var pulseScale: CGFloat = 1.0

    private var dotSize: CGFloat { dot.isMe ? 13 : 10 }

    var body: some View {
        ZStack {
            // Pulse ring (speaking)
            if dot.isSpeaking {
                Circle()
                    .fill(dot.color.opacity(0.18))
                    .frame(width: dotSize + 14, height: dotSize + 14)
                    .scaleEffect(pulseScale)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                            pulseScale = 1.5
                        }
                    }
            }

            // Dot
            Circle()
                .fill(dot.color)
                .frame(width: dotSize, height: dotSize)
                .overlay(
                    Circle().stroke(Color.white.opacity(dot.isMe ? 0.6 : 0.28), lineWidth: 1)
                )

            // Speech bubble above dot
            if dot.isSpeaking {
                SpeechBubbleView(color: dot.color)
                    .offset(y: -(dotSize / 2 + 20))
                    .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
            }

            // Name label below dot
            Text(dot.name)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .offset(y: dotSize / 2 + 9)
        }
    }
}

// MARK: - SpeechBubbleView

struct SpeechBubbleView: View {
    let color: Color
    @State private var tick: Double = 0

    private let barCount = 5

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.black.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(color.opacity(0.55), lineWidth: 0.75)
                )

            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(color)
                        .frame(width: 2, height: barHeight(index: i))
                }
            }
        }
        .frame(width: 26, height: 18)
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
            tick += 0.12
        }
    }

    private func barHeight(index: Int) -> CGFloat {
        let phase = Double(index) * 0.9
        let raw = sin(tick + phase) * 0.5 + 0.5
        return 3 + raw * 9
    }
}

// MARK: - MusicDotView

struct MusicDotView: View {
    let dot: VoiceDot
    let songTitle: String?
    let artist: String?
    @State private var pulseScale: CGFloat = 1.0

    private let dotSize: CGFloat = 11

    var body: some View {
        ZStack {
            // Pulse ring
            Circle()
                .fill(dot.color.opacity(0.18))
                .frame(width: dotSize + 14, height: dotSize + 14)
                .scaleEffect(pulseScale)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                        pulseScale = 1.5
                    }
                }

            // Dot with music note icon
            ZStack {
                Circle()
                    .fill(dot.color)
                    .frame(width: dotSize, height: dotSize)
                Image(systemName: "music.note")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.black.opacity(0.8))
            }
            .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1))

            // Song info bubble above dot
            if let title = songTitle {
                SongBubbleView(title: title, artist: artist, color: dot.color)
                    .offset(y: -(dotSize / 2 + 24))
            }

            // Label below
            Text("♫")
                .font(.system(size: 7))
                .foregroundColor(.white.opacity(0.5))
                .offset(y: dotSize / 2 + 9)
        }
    }
}

// MARK: - SongBubbleView

struct SongBubbleView: View {
    let title: String
    let artist: String?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
            if let artist {
                Text(artist)
                    .font(.system(size: 6, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.82))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(color.opacity(0.55), lineWidth: 0.75)
        )
        .cornerRadius(5)
        .fixedSize()
    }
}
