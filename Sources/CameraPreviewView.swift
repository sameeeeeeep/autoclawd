import AVFoundation
import SwiftUI

// MARK: - PixelAvatarView

/// Renders a PixelAvatar's 5×7 grid as a tiny SwiftUI pixel art image.
struct PixelAvatarView: View {
    let seed: UInt64
    let pixelSize: CGFloat

    init(seed: UInt64, pixelSize: CGFloat = 3) {
        self.seed = seed
        self.pixelSize = pixelSize
    }

    var body: some View {
        let grid = PixelAvatar.generate(seed: seed)
        VStack(spacing: 0) {
            ForEach(0..<grid.count, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<grid[row].count, id: \.self) { col in
                        Rectangle()
                            .fill(Color(cgColor: grid[row][col]))
                            .frame(width: pixelSize, height: pixelSize)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: pixelSize * 0.5))
    }
}

// MARK: - CameraPreviewView

/// Live camera preview using AVCaptureVideoPreviewLayer.
/// Shows the front-facing camera feed inside the pill widget.
/// No video is recorded — this is purely a live viewfinder.
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession?

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.session = session
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.session = session
    }
}

/// Backing NSView that hosts the AVCaptureVideoPreviewLayer.
final class CameraPreviewNSView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    var session: AVCaptureSession? {
        didSet {
            guard session !== oldValue else { return }
            setupPreviewLayer()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    private func setupPreviewLayer() {
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil

        guard let session else { return }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = bounds
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        // Mirror the front camera so it feels natural (like FaceTime)
        if let connection = preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }

        layer?.addSublayer(preview)
        previewLayer = preview
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }
}

// MARK: - CameraFeedWidget

/// Dual-purpose feed tile for the pill widget — shows camera feed or screen share preview.
/// When both camera and screen share are active, a chevron on the center-right switches between them.
/// Gesture detection can be toggled with a button on the top-left.
/// A capture button on the bottom takes a snapshot.
struct CameraFeedWidget: View {
    @ObservedObject var appState: AppState
    let appearance: WidgetAppearance
    var onCapture: (() -> Void)? = nil

    private var cameraActive: Bool {
        appState.cameraEnabled && appState.cameraService.isRunning
    }

    private var screenActive: Bool {
        appState.systemAudioEnabled
    }

    /// Both sources active — show cycle button
    private var hasBothSources: Bool {
        cameraActive && screenActive
    }

    var body: some View {
        ZStack {
            if appState.feedViewMode == .camera && cameraActive {
                cameraContent
            } else if appState.feedViewMode == .screen && screenActive {
                screenContent
            } else if cameraActive {
                cameraContent
            } else if screenActive {
                screenContent
            } else {
                feedOffPlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.7))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            (cameraActive || screenActive)
                                ? Color.cyan.opacity(0.3) : appearance.borderOff,
                            (cameraActive || screenActive)
                                ? Color.cyan.opacity(0.08) : appearance.borderLow,
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        )
    }

    // MARK: - Camera Content

    private var cameraContent: some View {
        ZStack {
            CameraPreviewView(session: appState.cameraService.captureSession)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if appState.faceTrackingEnabled {
                GeometryReader { geo in
                    ForEach(appState.faceTracker.trackedFaces) { face in
                        faceBoundingBox(face: face, in: geo.size)
                    }
                }
            }

            feedHUD(isScreen: false)
        }
    }

    // MARK: - Screen Content

    private var screenContent: some View {
        ZStack {
            if let image = appState.screenPreviewImage {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 18))
                        .foregroundColor(appearance.textDim)
                    Text("Waiting for screen…")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(appearance.textDim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            feedHUD(isScreen: true)
        }
    }

    // MARK: - Feed HUD

    private func feedHUD(isScreen: Bool) -> some View {
        ZStack {
            VStack {
                // Top row: gesture toggle (left), face badge + gesture indicator (right)
                HStack {
                    if !isScreen {
                        gestureToggleButton
                    }
                    Spacer()
                    if !isScreen && appState.faceTrackingEnabled && appState.detectedFaceCount > 0 {
                        faceCountBadge
                            .onTapGesture { appState.presentFaceLinkingOptions() }
                    }
                    if !isScreen, let gesture = appState.lastConfirmedGesture {
                        gestureIndicatorBadge(gesture)
                    }
                }
                Spacer()
                // Bottom row: live/screen badge (left), capture button (right)
                HStack {
                    if isScreen { screenBadge } else { liveBadge }
                    Spacer()
                    if !isScreen {
                        captureButton
                    }
                }
            }
            .padding(8)

            // Center-right chevron (only when both sources are active)
            if hasBothSources {
                HStack {
                    Spacer()
                    chevronCycleButton
                }
            }
        }
    }

    // MARK: - Gesture Toggle Button

    private var gestureToggleButton: some View {
        Button {
            appState.gestureControlEnabled.toggle()
        } label: {
            Image(systemName: appState.gestureControlEnabled ? "hand.raised.fill" : "hand.raised.slash.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(appState.gestureControlEnabled ? .green : .white.opacity(0.5))
                .padding(5)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .overlay(Circle().stroke(
                            appState.gestureControlEnabled ? Color.green.opacity(0.4) : Color.white.opacity(0.2),
                            lineWidth: 0.5
                        ))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Capture Button

    private var captureButton: some View {
        Button { onCapture?() } label: {
            Image(systemName: "camera.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.85))
                .shadow(color: .black.opacity(0.4), radius: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Center-right Chevron Cycle Button

    private var chevronCycleButton: some View {
        Button {
            appState.feedViewMode = appState.feedViewMode == .camera ? .screen : .camera
        } label: {
            Image(systemName: appState.feedViewMode == .camera ? "chevron.right" : "chevron.left")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.85))
                .padding(.vertical, 10)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.50))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Face Bounding Box

    private func faceBoundingBox(face: FaceTracker.TrackedFace, in size: CGSize) -> some View {
        let bbox = face.boundingBox
        let x = (1 - bbox.origin.x - bbox.width) * size.width
        let y = (1 - bbox.origin.y - bbox.height) * size.height
        let w = bbox.width * size.width
        let h = bbox.height * size.height
        let borderColor: Color = face.isSpeaking ? .green : .cyan

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(borderColor.opacity(0.7), lineWidth: 1.5)
                .frame(width: w, height: h)

            Text(face.label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(borderColor)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.5))
                .cornerRadius(2)
                .offset(y: -12)
        }
        .position(x: x + w / 2, y: y + h / 2)
    }

    // MARK: - Sub-views

    private var faceCountBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.fill")
                .font(.system(size: 8, weight: .semibold))
            Text("\(appState.detectedFaceCount)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.55))
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
        )
    }

    private func gestureIndicatorBadge(_ gesture: HandGestureRecognizer.Gesture) -> some View {
        let color: Color = {
            switch gesture {
            case .rightSpreadOpen:     return .green
            case .rightThumbIndexOpen: return .yellow
            case .rightPinchClosed:    return .orange
            case .rightThumbsUp:       return .white.opacity(0.4)
            case .leftFingerCount:     return .cyan
            }
        }()
        let icon: String = {
            switch gesture {
            case .rightSpreadOpen:     return "hand.raised.fill"
            case .rightThumbIndexOpen: return "hand.point.up.fill"
            case .rightPinchClosed:    return "hand.point.up.braille.fill"
            case .rightThumbsUp:       return "hand.thumbsup.fill"
            case .leftFingerCount:     return "hand.point.up.left.fill"
            }
        }()

        return Image(systemName: icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(5)
            .background(
                Circle()
                    .fill(Color.black.opacity(0.55))
                    .overlay(Circle().stroke(color.opacity(0.4), lineWidth: 0.5))
            )
    }

    private var liveBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.red)
                .frame(width: 5, height: 5)
            Text("LIVE")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.55))
        )
    }

    private var screenBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.cyan)
                .frame(width: 5, height: 5)
            Text("SCREEN")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.55))
        )
    }

    private var feedOffPlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "camera.fill")
                .font(.system(size: 18))
                .foregroundColor(appearance.textDim)
            Text("Camera Off")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(appearance.textDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

