import CoreMedia
import Foundation
import Vision

// MARK: - HandGestureRecognizer

/// Processes camera frames to detect hand gestures using Apple Vision.
///
/// **Right hand:**
/// - Spread open (all fingers extended, spread apart) → session start
/// - Pinch closed (thumb + index touching) → session stop
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
    var minConfidence: Float = 0.3

    // MARK: - Callbacks

    var onGestureConfirmed: ((Gesture) -> Void)?

    // MARK: - State

    private var state: State = .idle
    private let maxMissFrames = 2  // allow brief jitter without resetting

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
            if isSpreadOpen(right) {
                detected = .rightSpreadOpen
            } else if isPinchClosed(right) {
                detected = .rightPinchClosed
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

    /// A finger is extended when tip.y > pip.y > mcp.y in Vision coords (y increases upward).
    private func isFingerExtended(
        observation: VNHumanHandPoseObservation,
        tip: VNHumanHandPoseObservation.JointName,
        pip: VNHumanHandPoseObservation.JointName,
        mcp: VNHumanHandPoseObservation.JointName
    ) -> Bool {
        guard let tipPt = try? observation.recognizedPoint(tip),
              let pipPt = try? observation.recognizedPoint(pip),
              let mcpPt = try? observation.recognizedPoint(mcp),
              tipPt.confidence > minConfidence,
              pipPt.confidence > minConfidence,
              mcpPt.confidence > minConfidence
        else { return false }

        return tipPt.location.y > pipPt.location.y && pipPt.location.y > mcpPt.location.y
    }

    /// Thumb is extended when tip is significantly farther from wrist than CMC joint.
    private func isThumbExtended(_ observation: VNHumanHandPoseObservation) -> Bool {
        guard let tipPt = try? observation.recognizedPoint(.thumbTip),
              let ipPt = try? observation.recognizedPoint(.thumbIP),
              let cmc = try? observation.recognizedPoint(.thumbCMC),
              tipPt.confidence > minConfidence,
              ipPt.confidence > minConfidence,
              cmc.confidence > minConfidence
        else { return false }

        // Thumb extended: tip is farther from CMC than IP is (in both x and y combined)
        let tipDist = hypot(tipPt.location.x - cmc.location.x, tipPt.location.y - cmc.location.y)
        let ipDist = hypot(ipPt.location.x - cmc.location.x, ipPt.location.y - cmc.location.y)
        return tipDist > ipDist * 1.2  // tip at least 20% farther than IP joint
    }

    /// All 5 fingers extended AND inter-finger tip distance indicates spread.
    private func isSpreadOpen(_ observation: VNHumanHandPoseObservation) -> Bool {
        let count = countExtendedFingers(observation)
        guard count >= 4 else { return false }  // at least 4 fingers open (thumb detection can be tricky)

        // Check spread: average distance between adjacent fingertips
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
        let avgSpread = (d1 + d2 + d3) / 3.0

        return avgSpread > 0.06  // threshold for "spread apart" in normalized coords
    }

    /// Pinch: thumb tip and index tip are very close together.
    private func isPinchClosed(_ observation: VNHumanHandPoseObservation) -> Bool {
        guard let thumbTip = try? observation.recognizedPoint(.thumbTip),
              let indexTip = try? observation.recognizedPoint(.indexTip),
              thumbTip.confidence > minConfidence,
              indexTip.confidence > minConfidence
        else { return false }

        let dist = distance(thumbTip.location, indexTip.location)
        return dist < 0.05  // close together = pinch
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
