import CoreMedia
import Foundation
import Vision

// MARK: - VisualContextSampler

/// Periodically samples camera frames for scene classification and body pose.
/// Runs at a much lower cadence than face/gesture detection — designed for
/// session-level metadata, not real-time feedback.
///
/// All Vision requests are batched into a single VNImageRequestHandler call
/// (one frame decode, multiple request types = negligible extra cost).
///
/// Usage (from AppState.cameraService.onFrame):
///   visualContextSampler.processFrame(sampleBuffer, personCount: faceTracker.faceCount)
///
/// On session end:
///   let ctx = visualContextSampler.finalizeContext()
///   sessionStore.updateSessionVisualContext(id: sessionID, json: ctx.asJSON())
final class VisualContextSampler: @unchecked Sendable {

    // MARK: - Output Model

    struct VisualSessionContext: Codable {
        var sceneLabels: [String] = []          // e.g. ["indoor", "office", "desk"]
        var personCountSamples: [Int] = []      // raw person count observations
        var bodyPoseStates: [String] = []       // e.g. ["seated", "standing"]
        var isMeetingLikely: Bool = false        // true when avg person count > 1.3

        var avgPersonCount: Double {
            guard !personCountSamples.isEmpty else { return 0 }
            return Double(personCountSamples.reduce(0, +)) / Double(personCountSamples.count)
        }
        var dominantScene: String? { sceneLabels.mostFrequent() }
        var dominantPosture: String? { bodyPoseStates.mostFrequent() }

        /// Encode to a compact JSON string for storage in SQLite.
        func asJSON() -> String? {
            guard let data = try? JSONEncoder().encode(self) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        /// Human-readable summary for LLM context injection.
        func summary() -> String {
            var parts: [String] = []
            if let scene = dominantScene { parts.append("Scene: \(scene)") }
            if let posture = dominantPosture { parts.append("Posture: \(posture)") }
            let avg = avgPersonCount
            if avg > 0 { parts.append("People in frame: ~\(Int(avg.rounded()))") }
            if isMeetingLikely { parts.append("Meeting detected") }
            return parts.joined(separator: " | ")
        }
    }

    // MARK: - Configuration

    /// Interval between scene classification runs (seconds). Scenes change slowly.
    var sceneInterval: TimeInterval = 60.0

    /// Interval between body pose sampling runs (seconds).
    var poseInterval: TimeInterval = 15.0

    // MARK: - State

    private let lock = NSLock()
    private var context = VisualSessionContext()
    private var lastSceneTime: Date = .distantPast
    private var lastPoseTime: Date = .distantPast

    // MARK: - Session Lifecycle

    func resetForNewSession() {
        lock.withLock {
            context = VisualSessionContext()
            lastSceneTime = .distantPast
            lastPoseTime = .distantPast
        }
    }

    // MARK: - Frame Processing

    /// Call from the camera frame handler. Internally throttled — cheap to call at full FPS.
    /// personCount is taken from FaceTracker.faceCount (already computed, no extra Vision request).
    func processFrame(_ sampleBuffer: CMSampleBuffer, personCount: Int) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Always accumulate person count (it's just an Int, zero overhead)
        lock.withLock { context.personCountSamples.append(personCount) }

        let now = Date()
        let runScene = now.timeIntervalSince(lastSceneTime) >= sceneInterval
        let runPose  = now.timeIntervalSince(lastPoseTime)  >= poseInterval
        guard runScene || runPose else { return }

        // Build request batch — both requests share one frame decode
        var requests: [VNRequest] = []
        let sceneReq = runScene ? VNClassifyImageRequest() : nil
        let poseReq  = runPose  ? VNDetectHumanBodyPoseRequest() : nil
        if let r = sceneReq { requests.append(r) }
        if let r = poseReq  { requests.append(r) }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do { try handler.perform(requests) } catch { return }

        if let req = sceneReq {
            lastSceneTime = now
            let labels = (req.results ?? [])
                .filter { $0.confidence > 0.3 }
                .prefix(5)
                .map { $0.identifier }
            lock.withLock { context.sceneLabels.append(contentsOf: labels) }
            Log.info(.camera, "VisualContextSampler: scene → \(labels.joined(separator: ", "))")
        }

        if let req = poseReq {
            lastPoseTime = now
            let poses = req.results ?? []
            let states = poses.compactMap { classifyPosture($0) }
            if !states.isEmpty {
                lock.withLock { context.bodyPoseStates.append(contentsOf: states) }
                Log.info(.camera, "VisualContextSampler: pose → \(states.joined(separator: ", "))")
            }
        }
    }

    /// Force an immediate scene + pose sample regardless of cadence.
    /// Call on session start so every session has at least one snapshot.
    func sampleNow(_ sampleBuffer: CMSampleBuffer, personCount: Int) {
        lock.withLock {
            lastSceneTime = .distantPast
            lastPoseTime  = .distantPast
        }
        processFrame(sampleBuffer, personCount: personCount)
    }

    /// Aggregate and return the final context. Call at session end.
    func finalizeContext() -> VisualSessionContext {
        lock.withLock {
            context.isMeetingLikely = context.avgPersonCount > 1.3
            return context
        }
    }

    // MARK: - Posture Classification

    private func classifyPosture(_ observation: VNHumanBodyPoseObservation) -> String? {
        guard let joints = try? observation.recognizedPoints(.all) else { return nil }

        let sL = joints[.leftShoulder]
        let sR = joints[.rightShoulder]
        guard let sL, let sR, sL.confidence > 0.5, sR.confidence > 0.5 else { return nil }

        let shoulderY = (sL.location.y + sR.location.y) / 2

        let hL = joints[.leftHip]
        let hR = joints[.rightHip]
        if let hL, let hR, hL.confidence > 0.4, hR.confidence > 0.4 {
            // Vision y=0 is bottom; standing = hips much lower than shoulders
            let hipY = (hL.location.y + hR.location.y) / 2
            let span = abs(shoulderY - hipY)
            return span > 0.2 ? "standing" : "seated"
        }

        // Hips not detected — likely seated at desk (only upper body visible)
        return "seated"
    }
}

// MARK: - Array Helper

private extension Array where Element == String {
    func mostFrequent() -> String? {
        guard !isEmpty else { return nil }
        var counts: [String: Int] = [:]
        forEach { counts[$0, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}
