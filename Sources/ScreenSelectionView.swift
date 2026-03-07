import AppKit
import SwiftUI

// MARK: - ScreenSelectionPanel

/// Fullscreen transparent NSPanel for user-driven screen region selection.
/// Presented above all other windows at .screenSaver level.
/// Dismissed on Escape (cancel) or mouse release after drag (confirm).
///
/// Usage:
///   let rect = await ScreenSelectionPanel.present()  // nil = cancelled
///   // rect is normalised 0-1 relative to screen bounds
final class ScreenSelectionPanel: NSPanel {

    private let resultContinuation: CheckedContinuation<CGRect?, Never>
    private var hostingView: NSHostingView<ScreenSelectionView>?

    // MARK: - Factory

    /// Show the panel and await a normalised CGRect selection (or nil if cancelled).
    static func present() async -> CGRect? {
        guard let screen = NSScreen.main else { return nil }
        return await withCheckedContinuation { continuation in
            let panel = ScreenSelectionPanel(
                screen: screen,
                continuation: continuation
            )
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Init

    private init(screen: NSScreen, continuation: CheckedContinuation<CGRect?, Never>) {
        self.resultContinuation = continuation
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        setupPanel(screen: screen)
    }

    private func setupPanel(screen: NSScreen) {
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver         // above everything
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        hasShadow = false
        isReleasedWhenClosed = false

        let selectionView = ScreenSelectionView(
            screenSize: screen.frame.size,
            onConfirm: { [weak self] normRect in
                self?.finish(result: normRect)
            },
            onCancel: { [weak self] in
                self?.finish(result: nil)
            }
        )
        let hosting = NSHostingView(rootView: selectionView)
        hosting.frame = screen.frame
        contentView = hosting
        hostingView = hosting
    }

    // MARK: - Keyboard

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            finish(result: nil)
        }
    }

    // MARK: - Finish

    private func finish(result: CGRect?) {
        orderOut(nil)
        resultContinuation.resume(returning: result)
    }
}

// MARK: - ScreenSelectionView

/// SwiftUI body of the selection overlay.
/// - Dim overlay with a cutout for the selected region
/// - Drag to select a rectangle; click to auto-select 300×300 centred region
/// - Real-time visual feedback with corner handles + dimension label
struct ScreenSelectionView: View {

    let screenSize: CGSize
    let onConfirm: (CGRect) -> Void
    let onCancel: () -> Void

    // Drag state in screen pixels (origin = bottom-left, SwiftUI flipped)
    @State private var dragStart: CGPoint? = nil
    @State private var dragCurrent: CGPoint? = nil
    @State private var hovering: CGPoint? = nil

    // MARK: - Geometry helpers

    /// Current selection rect in SwiftUI view coordinates (pixels, top-left origin).
    private var selectionRect: CGRect? {
        guard let s = dragStart, let e = dragCurrent else { return nil }
        let x = min(s.x, e.x)
        let y = min(s.y, e.y)
        let w = abs(e.x - s.x)
        let h = abs(e.y - s.y)
        guard w > 4 && h > 4 else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Convert a SwiftUI-coordinate rect → normalised rect (0-1) for ScreenVisionAnalyzer.
    /// SwiftUI origin is top-left; normalised origin is also top-left.
    private func normalise(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX / screenSize.width,
            y: rect.minY / screenSize.height,
            width:  rect.width  / screenSize.width,
            height: rect.height / screenSize.height
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // ── Dim background ──────────────────────────────────────────────
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            // ── Selection cutout ────────────────────────────────────────────
            if let rect = selectionRect {
                SelectionCutoutShape(rect: rect, screenSize: screenSize)
                    .fill(Color.clear)
                    .background(
                        Color.black.opacity(0.45)
                            .mask(
                                SelectionCutoutMask(rect: rect, screenSize: screenSize)
                            )
                    )
                    .ignoresSafeArea()

                // Selection border + handles
                SelectionBorderView(rect: rect)

                // Dimensions label
                DimensionLabel(rect: rect)
            }

            // ── Instructions overlay ────────────────────────────────────────
            if selectionRect == nil {
                instructionOverlay
            }

            // ── Full-area gesture layer ─────────────────────────────────────
            gestureLayer
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .cursor(.crosshair)
    }

    // MARK: - Instruction overlay

    private var instructionOverlay: some View {
        VStack(spacing: 10) {
            Text("Drag to select a region · Click to point · Esc to cancel")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.black.opacity(0.55))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                        )
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 60)
    }

    // MARK: - Gesture layer

    private var gestureLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .local)
                    .onChanged { value in
                        if dragStart == nil { dragStart = value.startLocation }
                        dragCurrent = value.location
                    }
                    .onEnded { value in
                        if let rect = selectionRect {
                            onConfirm(normalise(rect))
                        } else {
                            // Treat as a point click — 300×300 centred on click
                            let cx = value.location.x
                            let cy = value.location.y
                            let side: CGFloat = 300
                            let r = CGRect(
                                x: max(0, cx - side / 2),
                                y: max(0, cy - side / 2),
                                width:  min(side, screenSize.width  - max(0, cx - side / 2)),
                                height: min(side, screenSize.height - max(0, cy - side / 2))
                            )
                            onConfirm(normalise(r))
                        }
                        dragStart   = nil
                        dragCurrent = nil
                    }
            )
    }
}

// MARK: - SelectionCutoutMask

/// SwiftUI Shape that produces an opaque rect "hole" in a black overlay.
/// Used with `.mask` so the selected area shows the dim mask subtracted.
private struct SelectionCutoutMask: View {
    let rect: CGRect
    let screenSize: CGSize

    var body: some View {
        Canvas { ctx, size in
            // Fill entire canvas black (opaque = masked-out = dim)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            // Erase the selection rect (transparent = not masked = pass-through)
            ctx.blendMode = .destinationOut
            ctx.fill(Path(rect), with: .color(.black))
        }
    }
}

// MARK: - SelectionCutoutShape

/// Placeholder — actual dim-with-hole is done via SelectionCutoutMask above.
private struct SelectionCutoutShape: Shape {
    let rect: CGRect
    let screenSize: CGSize
    func path(in bounds: CGRect) -> Path { Path(bounds) }
}

// MARK: - SelectionBorderView

private struct SelectionBorderView: View {
    let rect: CGRect
    private let handleSize: CGFloat = 8
    private let strokeColor = Color.white

    var body: some View {
        ZStack {
            // Dashed border
            Rectangle()
                .strokeBorder(
                    strokeColor.opacity(0.9),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 3])
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            // Corner handles
            ForEach(corners, id: \.x) { pt in
                RoundedRectangle(cornerRadius: 2)
                    .fill(strokeColor)
                    .frame(width: handleSize, height: handleSize)
                    .position(pt)
            }
        }
    }

    private var corners: [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
    }
}

// MARK: - DimensionLabel

private struct DimensionLabel: View {
    let rect: CGRect

    var body: some View {
        Text("\(Int(rect.width)) × \(Int(rect.height))")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(.black.opacity(0.65))
            )
            .position(
                x: rect.midX,
                y: max(rect.minY - 18, 14)   // above rect, clamped to screen
            )
    }
}

// MARK: - Cursor modifier

private struct CursorModifier: ViewModifier {
    let cursor: NSCursor
    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        modifier(CursorModifier(cursor: cursor))
    }
}
