import SwiftUI

// MARK: - CameraGestureOverlayView

/// Overlay shown in the pill widget for gesture feedback and option selection.
struct CameraGestureOverlayView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 4) {
            // Gesture confirmation feedback
            if let gesture = appState.lastConfirmedGesture {
                gestureIndicator(gesture)
                    .transition(.opacity.combined(with: .scale))
            }

            // Option selection overlay
            if appState.showOptionSelector {
                optionSelectorOverlay
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.lastConfirmedGesture != nil)
        .animation(.easeInOut(duration: 0.2), value: appState.showOptionSelector)
    }

    // MARK: - Gesture Indicator

    @ViewBuilder
    private func gestureIndicator(_ gesture: HandGestureRecognizer.Gesture) -> some View {
        HStack(spacing: 6) {
            Image(systemName: gestureIcon(gesture))
                .font(.system(size: 14, weight: .semibold))
            Text(gestureLabel(gesture))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .foregroundColor(gestureColor(gesture))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(gestureColor(gesture).opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(gestureColor(gesture).opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func gestureIcon(_ gesture: HandGestureRecognizer.Gesture) -> String {
        switch gesture {
        case .rightSpreadOpen:     return "hand.raised.fill"
        case .rightPinchClosed:    return "hand.point.up.braille.fill"
        case .leftFingerCount:     return "hand.point.up.left.fill"
        }
    }

    private func gestureLabel(_ gesture: HandGestureRecognizer.Gesture) -> String {
        switch gesture {
        case .rightSpreadOpen:        return "Session Start"
        case .rightPinchClosed:       return "Session Stop"
        case .leftFingerCount(let n): return "Option \(n)"
        }
    }

    private func gestureColor(_ gesture: HandGestureRecognizer.Gesture) -> Color {
        switch gesture {
        case .rightSpreadOpen:     return .green
        case .rightPinchClosed:    return .red
        case .leftFingerCount:     return .cyan
        }
    }

    // MARK: - Option Selector

    @ViewBuilder
    private var optionSelectorOverlay: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Show fingers to choose:")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            ForEach(Array(appState.availableOptions.enumerated()), id: \.offset) { index, option in
                HStack(spacing: 6) {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                        .frame(width: 18, alignment: .center)
                    Text(option)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.cyan.opacity(0.3), lineWidth: 1)
                )
        )
    }
}
