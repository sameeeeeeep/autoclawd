import CoreMedia
import Foundation
import Vision

// MARK: - HandGestureRecognizer

/// Processes camera frames to detect hand gestures using Apple Vision.
///
/// **Right hand:**
/// - Spread open (all fingers extended, spread apart) → session start
/// - Pinch closed (thumb + index touching) → session pause
/// - Thumbs up (only thumb extended) → session done
///
/// **Left hand:**
/// - Finger count (1-5 extended fingers) → option selection
///
/// Uses a debounced state machine: gesture must be held for `holdThreshold`
/// before firing, with a `cooldownInterval` between firings.
final class HandGestureRecognizer: @unchecked Sendable {

    // MARK: - Types

    enum Gesture: Equatable {
        case rightSpreadOpen
        case rightPinchClosed
        case rightThumbsUp
        case leftFingerCount(Int)
    }

    private enum State {
        case idle
        case candidate(gesture: Gesture, since: Date, missCount: Int)
        case cooldown(until: Date)
    }

    // MARK: - Configuration

    /// How long a gesture must be held before it fires (seconds).
    var holdThreshold: TimeInterval = 0.5

    /// Minimum time between gesture firings (seconds).
    var cooldownInterval: TimeInterval = 1.0

    /// Minimum confidence for Vision landmark points.
    var minConfidence: Float = 0.5

    // MARK: - Callbacks

    var onGestureConfirmed: ((Gesture) -> Void)?

    // MARK: - State

    private var state: State = .idle
    private let maxMissFrames = 3  // allow brief jitter without resetting

    // MARK: - Process Frame

    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return
        }

        guard let observations = request.results, !observations.isEmpty else {
            handleNoGesture()
            return
        }

        // Separate left and right hands
        var rightHand: VNHumanHandPoseObservation?
        var leftHand: VNHumanHandPoseObservation?

        for obs in observations {
            if #available(macOS 14.0, *) {
                switch obs.chirality {
                case .right: rightHand = obs
                case .left:  leftHand = obs
                default: break
                }
            } else {
                // Fallback: first hand is right, second is left
                if rightHand == nil { rightHand = obs }
                else if leftHand == nil { leftHand = obs }
            }
        }

        // Classify gestures
        var detected: Gesture?

        if let right = rightHand {
            // Check pinch FIRST — pinch (thumb+index touching) can look like
            // thumbs up (thumb extended, others closed) since the thumb is still
            // far from wrist during a pinch. Pinch is more specific.
            if isPinchClosed(right) {
                detected = .rightPinchClosed
            } else if isThumbsUp(right) {
                detected = .rightThumbsUp
            } else if isSpreadOpen(right) {
                detected = .rightSpreadOpen
            }
        }

        // Left hand finger count (only if no right-hand gesture detected)
        if detected == nil, let left = leftHand {
            let count = countExtendedFingers(left)
            if count >= 1 && count <= 5 {
                detected = .leftFingerCount(count)
            }
        }

        if let gesture = detected {
            handleDetectedGesture(gesture)
        } else {
            handleNoGesture()
        }
    }

    // MARK: - State Machine

    private func handleDetectedGesture(_ gesture: Gesture) {
        let now = Date()

        switch state {
        case .idle:
            state = .candidate(gesture: gesture, since: now, missCount: 0)

        case .candidate(let current, let since, _):
            if current == gesture {
                // Same gesture still held — check if threshold reached
                if now.timeIntervalSince(since) >= holdThreshold {
                    fire(gesture)
                    state = .cooldown(until: now.addingTimeInterval(cooldownInterval))
                }
                // Otherwise keep waiting (reset miss count)
                else {
                    state = .candidate(gesture: gesture, since: since, missCount: 0)
                }
            } else {
                // Different gesture — restart candidate
                state = .candidate(gesture: gesture, since: now, missCount: 0)
            }

        case .cooldown(let until):
            if now >= until {
                state = .candidate(gesture: gesture, since: now, missCount: 0)
            }
            // else: still in cooldown, ignore
        }
    }

    private func handleNoGesture() {
        switch state {
        case .candidate(let gesture, let since, let missCount):
            if missCount + 1 >= maxMissFrames {
                state = .idle
            } else {
                state = .candidate(gesture: gesture, since: since, missCount: missCount + 1)
            }
        case .cooldown(let until):
            if Date() >= until { state = .idle }
        case .idle:
            break
        }
    }

    private func fire(_ gesture: Gesture) {
        onGestureConfirmed?(gesture)
    }

    // MARK: - Finger Detection

    /// Count extended fingers on a hand observation.
    private func countExtendedFingers(_ observation: VNHumanHandPoseObservation) -> Int {
        var count = 0

        // Check each finger: index, middle, ring, little
        let fingers: [(VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] = [
            (.indexTip, .indexPIP, .indexMCP),
            (.middleTip, .middlePIP, .middleMCP),
            (.ringTip, .ringPIP, .ringMCP),
            (.littleTip, .littlePIP, .littleMCP),
        ]

        for (tip, pip, mcp) in fingers {
            if isFingerExtended(observation: observation, tip: tip, pip: pip, mcp: mcp) {
                count += 1
            }
        }

        // Thumb: check if tip is far from index MCP (extended outward)
        if isThumbExtended(observation) {
            count += 1
        }

        return count
    }

    /// A finger is extended when tip is above pip with a tolerance margin.
    /// Aligned with MediaPipe reference: `tip.y > pip.y + margin` in Vision coords (y increases upward).
    /// Only checks tip vs pip (not the full 3-point chain) for more reliable detection.
    private func isFingerExtended(
        observation: VNHumanHandPoseObservation,
        tip: VNHumanHandPoseObservation.JointName,
        pip: VNHumanHandPoseObservation.JointName,
        mcp: VNHumanHandPoseObservation.JointName
    ) -> Bool {
        guard let tipPt = try? observation.recognizedPoint(tip),
              let pipPt = try? observation.recognizedPoint(pip),
              tipPt.confidence > minConfidence,
              pipPt.confidence > minConfidence
        else { return false }

        // Vision Y-up: tip.y > pip.y means finger points up. Add 0.025 margin for noise tolerance.
        return tipPt.location.y > pipPt.location.y + 0.025
    }

    /// Thumb is extended when tip is far from wrist (palm base).
    /// Aligned with MediaPipe reference: checks tip-to-wrist distance > threshold.
    private func isThumbExtended(_ observation: VNHumanHandPoseObservation) -> Bool {
        guard let tipPt = try? observation.recognizedPoint(.thumbTip),
              let wrist = try? observation.recognizedPoint(.wrist),
              tipPt.confidence > minConfidence,
              wrist.confidence > minConfidence
        else { return false }

        let dist = hypot(tipPt.location.x - wrist.location.x, tipPt.location.y - wrist.location.y)
        return dist > 0.12  // same threshold as reference
    }

    /// Thumbs up: only thumb extended, all other fingers closed.
    private func isThumbsUp(_ observation: VNHumanHandPoseObservation) -> Bool {
        guard isThumbExtended(observation) else { return false }
        // Count only the 4 non-thumb fingers — none should be extended
        let fingers: [(VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] = [
            (.indexTip, .indexPIP, .indexMCP),
            (.middleTip, .middlePIP, .middleMCP),
            (.ringTip, .ringPIP, .ringMCP),
            (.littleTip, .littlePIP, .littleMCP),
        ]
        for (tip, pip, mcp) in fingers {
            if isFingerExtended(observation: observation, tip: tip, pip: pip, mcp: mcp) {
                return false  // any non-thumb finger extended → not thumbs up
            }
        }
        return true
    }

    /// All 4+ fingers extended AND inter-finger tip distance indicates spread.
    /// Reference: sums adjacent tip distances × 3, checks > 0.3 → raw totalDist > 0.1.
    private func isSpreadOpen(_ observation: VNHumanHandPoseObservation) -> Bool {
        let count = countExtendedFingers(observation)
        guard count >= 4 else { return false }  // at least 4 fingers open (thumb detection can be tricky)

        // Check spread: total distance between adjacent fingertips (like reference)
        guard let indexTip = try? observation.recognizedPoint(.indexTip),
              let middleTip = try? observation.recognizedPoint(.middleTip),
              let ringTip = try? observation.recognizedPoint(.ringTip),
              let littleTip = try? observation.recognizedPoint(.littleTip),
              indexTip.confidence > minConfidence,
              middleTip.confidence > minConfidence,
              ringTip.confidence > minConfidence,
              littleTip.confidence > minConfidence
        else { return false }

        let d1 = distance(indexTip.location, middleTip.location)
        let d2 = distance(middleTip.location, ringTip.location)
        let d3 = distance(ringTip.location, littleTip.location)
        let totalSpread = d1 + d2 + d3

        return totalSpread > 0.10  // aligned with reference (totalDist * 3 > 0.3)
    }

    /// Pinch: thumb tip and index tip are very close together.
    /// Reference uses `1 - dist * 5` mapped to 0-1, with pinch considered active when value > 0.5.
    /// That maps to raw distance < 0.10 in normalized coords.
    private func isPinchClosed(_ observation: VNHumanHandPoseObservation) -> Bool {
        guard let thumbTip = try? observation.recognizedPoint(.thumbTip),
              let indexTip = try? observation.recognizedPoint(.indexTip),
              thumbTip.confidence > minConfidence,
              indexTip.confidence > minConfidence
        else { return false }

        let dist = distance(thumbTip.location, indexTip.location)
        return dist < 0.10  // relaxed from 0.05 — aligned with reference
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
