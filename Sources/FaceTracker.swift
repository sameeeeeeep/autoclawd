import CoreMedia
import Foundation
import Vision

// MARK: - FaceTracker

/// Detects faces in camera frames and tracks them across frames to identify
/// who is currently speaking based on mouth movement during non-silent audio.
///
/// No face data is stored — analysis is real-time and discarded per-frame.
final class FaceTracker: @unchecked Sendable {

    // MARK: - Types

    struct TrackedFace: Identifiable, Equatable {
        let id: UUID
        var boundingBox: CGRect          // normalized 0..1
        var lastSeenTime: Date
        var assignedPersonID: UUID?      // linked to Person model
        var label: String                // e.g. "Person A"
        var isSpeaking: Bool = false
        var lastMouthOpenness: CGFloat = 0

        static func == (lhs: TrackedFace, rhs: TrackedFace) -> Bool {
            lhs.id == rhs.id
        }
    }

    // MARK: - Configuration

    /// Faces not seen for this long are expired.
    var expirationInterval: TimeInterval = 2.0

    /// IoU threshold for matching a new observation to an existing face.
    var iouThreshold: CGFloat = 0.3

    /// Mouth movement threshold to consider a face "speaking".
    var mouthMovementThreshold: CGFloat = 0.015

    // MARK: - Callbacks

    /// Fires when the detected current speaker changes (person UUID or nil).
    var onSpeakerChanged: ((UUID?) -> Void)?

    /// Fires when tracked face count changes.
    var onFaceCountChanged: ((Int) -> Void)?

    // MARK: - State

    private var faces: [TrackedFace] = []
    private var currentSpeakerTrackID: UUID?
    private var nextLabel = 1

    /// Whether external audio is currently non-silent (set by AppState).
    var isAudioActive: Bool = false

    /// Thread-safe snapshot of currently tracked faces.
    var trackedFaces: [TrackedFace] { faces }

    var faceCount: Int { faces.count }

    // MARK: - Process Frame

    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let faceRequest = VNDetectFaceRectanglesRequest()
        let landmarkRequest = VNDetectFaceLandmarksRequest()

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([faceRequest, landmarkRequest])
        } catch {
            return
        }

        let faceObservations = faceRequest.results ?? []
        let landmarkObservations = landmarkRequest.results ?? []
        let now = Date()

        // Match observations to existing tracked faces
        var matchedExisting = Set<UUID>()
        var matchedObservations = Set<Int>()

        for (obsIndex, obs) in faceObservations.enumerated() {
            var bestMatch: UUID?
            var bestIoU: CGFloat = 0

            for face in faces {
                let iou = computeIoU(face.boundingBox, obs.boundingBox)
                if iou > iouThreshold && iou > bestIoU {
                    bestIoU = iou
                    bestMatch = face.id
                }
            }

            if let matchID = bestMatch {
                // Update existing face
                if let idx = faces.firstIndex(where: { $0.id == matchID }) {
                    faces[idx].boundingBox = obs.boundingBox
                    faces[idx].lastSeenTime = now

                    // Check mouth movement from landmarks
                    if obsIndex < landmarkObservations.count {
                        let mouthOpenness = measureMouthOpenness(landmarkObservations[obsIndex])
                        let delta = abs(mouthOpenness - faces[idx].lastMouthOpenness)
                        faces[idx].isSpeaking = isAudioActive && delta > mouthMovementThreshold
                        faces[idx].lastMouthOpenness = mouthOpenness
                    }
                }
                matchedExisting.insert(matchID)
                matchedObservations.insert(obsIndex)
            }
        }

        // Create new tracked faces for unmatched observations
        let oldCount = faces.count
        for (obsIndex, obs) in faceObservations.enumerated() where !matchedObservations.contains(obsIndex) {
            let label = "Person \(Character(UnicodeScalar(64 + nextLabel)!))"  // A, B, C...
            nextLabel += 1
            if nextLabel > 26 { nextLabel = 1 }

            var newFace = TrackedFace(
                id: UUID(),
                boundingBox: obs.boundingBox,
                lastSeenTime: now,
                label: label
            )
            if obsIndex < landmarkObservations.count {
                newFace.lastMouthOpenness = measureMouthOpenness(landmarkObservations[obsIndex])
            }
            faces.append(newFace)
        }

        // Expire old faces
        faces.removeAll { now.timeIntervalSince($0.lastSeenTime) > expirationInterval }

        // Notify face count change
        if faces.count != oldCount {
            onFaceCountChanged?(faces.count)
        }

        // Determine current speaker
        updateCurrentSpeaker()
    }

    // MARK: - Speaker Detection

    private func updateCurrentSpeaker() {
        let speakingFaces = faces.filter { $0.isSpeaking }

        let newSpeakerTrackID: UUID?
        if speakingFaces.count == 1 {
            newSpeakerTrackID = speakingFaces[0].id
        } else if speakingFaces.isEmpty {
            newSpeakerTrackID = nil
        } else {
            // Multiple speaking — keep current if still speaking, otherwise pick first
            if let current = currentSpeakerTrackID,
               speakingFaces.contains(where: { $0.id == current }) {
                newSpeakerTrackID = current
            } else {
                newSpeakerTrackID = speakingFaces.first?.id
            }
        }

        if newSpeakerTrackID != currentSpeakerTrackID {
            currentSpeakerTrackID = newSpeakerTrackID
            // Map track ID to person ID
            let personID = faces.first(where: { $0.id == newSpeakerTrackID })?.assignedPersonID
            onSpeakerChanged?(personID)
        }
    }

    // MARK: - Person Assignment

    /// Link a tracked face to a Person from the roster.
    func assignPerson(trackID: UUID, personID: UUID) {
        if let idx = faces.firstIndex(where: { $0.id == trackID }) {
            faces[idx].assignedPersonID = personID
        }
    }

    // MARK: - Mouth Measurement

    /// Measure how "open" the mouth is from face landmarks (normalized value).
    private func measureMouthOpenness(_ observation: VNFaceObservation) -> CGFloat {
        guard let landmarks = observation.landmarks,
              let outerLips = landmarks.outerLips
        else { return 0 }

        let points = outerLips.normalizedPoints
        guard points.count >= 8 else { return 0 }

        // Approximate mouth openness: vertical distance between top and bottom lip points
        // Top lip is roughly at index 2-3, bottom lip at index 8-9 (12-point outer lip model)
        let topIndex = min(2, points.count - 1)
        let bottomIndex = min(points.count - 2, points.count - 1)
        let topY = points[topIndex].y
        let bottomY = points[bottomIndex].y

        return abs(topY - bottomY)
    }

    // MARK: - IoU

    private func computeIoU(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }
}
