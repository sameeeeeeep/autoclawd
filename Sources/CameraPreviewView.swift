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

/// Camera feed tile for the pill widget — shows live video with face bounding boxes,
/// gesture indicators, and a camera off button. Styled to match the widget row tiles.
struct CameraFeedWidget: View {
    @ObservedObject var appState: AppState
    let appearance: WidgetAppearance

    var body: some View {
        ZStack {
            if appState.cameraEnabled, appState.cameraService.isRunning {
                // Live camera feed
                CameraPreviewView(session: appState.cameraService.captureSession)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Face bounding boxes overlay
                if appState.faceTrackingEnabled {
                    GeometryReader { geo in
                        ForEach(appState.faceTracker.trackedFaces) { face in
                            faceBoundingBox(face: face, in: geo.size)
                        }
                    }
                }

                // HUD overlay (badges + buttons)
                VStack {
                    // Top row: face count + gesture indicator + camera off button
                    HStack {
                        if appState.faceTrackingEnabled && appState.detectedFaceCount > 0 {
                            faceCountBadge
                                .onTapGesture {
                                    appState.presentFaceLinkingOptions()
                                }
                        }
                        Spacer()
                        if let gesture = appState.lastConfirmedGesture {
                            gestureIndicatorBadge(gesture)
                        }
                        cameraOffButton
                    }
                    Spacer()
                    // Bottom row: LIVE badge
                    HStack {
                        liveBadge
                        Spacer()
                    }
                }
                .padding(8)

            } else {
                cameraOffPlaceholder
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
                            appState.cameraEnabled ? Color.cyan.opacity(0.3) : appearance.borderOff,
                            appState.cameraEnabled ? Color.cyan.opacity(0.08) : appearance.borderLow,
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        )
    }

    // MARK: - Face Bounding Box

    /// Draws a bounding box for a tracked face.
    /// Vision normalized coords: origin bottom-left, y-up. Camera is mirrored.
    private func faceBoundingBox(face: FaceTracker.TrackedFace, in size: CGSize) -> some View {
        // Vision bbox: origin is bottom-left, y goes up. Mirror X for front camera.
        let bbox = face.boundingBox
        let x = (1 - bbox.origin.x - bbox.width) * size.width   // mirror X
        let y = (1 - bbox.origin.y - bbox.height) * size.height  // flip Y to top-left origin
        let w = bbox.width * size.width
        let h = bbox.height * size.height
        let borderColor: Color = face.isSpeaking ? .green : .cyan

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(borderColor.opacity(0.7), lineWidth: 1.5)
                .frame(width: w, height: h)

            // Label above box
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

    // MARK: - Camera Off Button

    private var cameraOffButton: some View {
        Button {
            appState.cameraEnabled = false
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .padding(5)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
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
            case .rightSpreadOpen:  return .green
            case .rightPinchClosed: return .orange
            case .rightThumbsUp:    return .yellow
            case .leftFingerCount:  return .cyan
            }
        }()
        let icon: String = {
            switch gesture {
            case .rightSpreadOpen:  return "hand.raised.fill"
            case .rightPinchClosed: return "hand.point.up.braille.fill"
            case .rightThumbsUp:    return "hand.thumbsup.fill"
            case .leftFingerCount:  return "hand.point.up.left.fill"
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

    private var cameraOffPlaceholder: some View {
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

