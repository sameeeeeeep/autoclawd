import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import Vision

// MARK: - FaceTracker

/// Detects faces in camera frames and tracks them across frames to identify
/// who is currently speaking based on mouth movement during non-silent audio.
///
/// Uses Vision feature prints for face re-identification: when a person leaves
/// the frame and returns, their identity (label, avatar) is preserved.
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
        var featurePrint: VNFeaturePrintObservation?  // for re-identification
        var avatarSeed: UInt64 = 0       // deterministic seed for pixel art avatar

        static func == (lhs: TrackedFace, rhs: TrackedFace) -> Bool {
            lhs.id == rhs.id
        }
    }

    // MARK: - Types (internal)

    /// A face observation that has not yet been stable long enough to become a TrackedFace.
    private struct PendingObservation {
        var id: UUID
        var box: CGRect
        var firstSeen: Date
        var lastSeen: Date
        var featurePrint: VNFeaturePrintObservation?
        var seed: UInt64
        var label: String
    }

    // MARK: - Configuration

    /// A new face must be continuously visible for this long before becoming a TrackedFace.
    var newFaceStabilityInterval: TimeInterval = 5.0

    /// Faces not seen for this long are removed from active tracking.
    var expirationInterval: TimeInterval = 2.0

    /// Expired faces kept for re-identification (longer window).
    var reIdRetentionInterval: TimeInterval = 120.0

    /// IoU threshold for matching a new observation to an existing face.
    var iouThreshold: CGFloat = 0.3

    /// Maximum feature print distance for re-identification match.
    var featurePrintDistanceThreshold: Float = 18.0

    /// Mouth movement threshold to consider a face "speaking".
    var mouthMovementThreshold: CGFloat = 0.015

    /// How often to extract/refresh in-memory feature prints for active faces.
    var featurePrintUpdateInterval: TimeInterval = 2.0

    /// How often to re-save enrolled face embeddings to disk (named faces only).
    var enrollmentRefreshInterval: TimeInterval = 30.0

    // MARK: - Persistent Recognition

    /// Injected by AppState after init. Used to persist and load face embeddings.
    var embeddingStore: FaceEmbeddingStore?

    /// In-memory cache of stored embeddings loaded at app start.
    /// Checked in findReIdMatch() so cross-session recognition needs zero disk access per frame.
    private var storedEmbeddings: [FaceEmbeddingStore.StoredEmbedding] = []

    // MARK: - Callbacks

    /// Fires when the detected current speaker changes (person UUID or nil).
    var onSpeakerChanged: ((UUID?) -> Void)?

    /// Fires when tracked face count changes.
    var onFaceCountChanged: ((Int) -> Void)?

    // MARK: - State

    /// Lock protecting all mutable state — processFrame runs on the AVFoundation
    /// camera thread, while trackedFaces / faceCount are read from the main thread.
    private let lock = NSLock()
    private var faces: [TrackedFace] = []
    private var recentlyExpired: [TrackedFace] = []  // for re-identification
    /// New faces that haven't yet passed the stability threshold.
    private var pendingObservations: [PendingObservation] = []
    private var currentSpeakerTrackID: UUID?
    private var nextLabel = 1
    private var lastFeaturePrintTime: Date = .distantPast
    private var lastEnrollmentTime: Date = .distantPast

    /// Whether external audio is currently non-silent (set by AppState).
    var isAudioActive: Bool = false

    /// Thread-safe snapshot of currently tracked faces.
    var trackedFaces: [TrackedFace] { lock.withLock { faces } }

    var faceCount: Int { lock.withLock { faces.count } }

    // MARK: - Persistent Recognition

    /// Load stored embeddings from disk into memory. Call once after injecting embeddingStore.
    func loadStoredEmbeddings() {
        guard let store = embeddingStore else { return }
        let loaded = store.loadAll()
        lock.withLock { storedEmbeddings = loaded }
    }

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

        lock.lock()
        defer { lock.unlock() }

        // Match observations to existing tracked faces via IoU
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
                if let idx = faces.firstIndex(where: { $0.id == matchID }) {
                    faces[idx].boundingBox = obs.boundingBox
                    faces[idx].lastSeenTime = now

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

        // Handle unmatched observations — re-identify or queue in pending pool
        let oldCount = faces.count
        for (obsIndex, obs) in faceObservations.enumerated() where !matchedObservations.contains(obsIndex) {
            let featurePrint = extractFeaturePrint(from: pixelBuffer, faceBox: obs.boundingBox)

            if let fp = featurePrint, let reIdMatch = findReIdMatch(featurePrint: fp) {
                // Re-identified — bypass pending pool, restore identity immediately
                var reusedFace = TrackedFace(
                    id: UUID(),
                    boundingBox: obs.boundingBox,
                    lastSeenTime: now,
                    assignedPersonID: reIdMatch.assignedPersonID,
                    label: reIdMatch.label,
                    featurePrint: fp,
                    avatarSeed: reIdMatch.avatarSeed
                )
                if obsIndex < landmarkObservations.count {
                    reusedFace.lastMouthOpenness = measureMouthOpenness(landmarkObservations[obsIndex])
                }
                faces.append(reusedFace)
                recentlyExpired.removeAll { $0.label == reIdMatch.label }
            } else {
                // Brand new face — add/update in pending pool.
                // Must persist for newFaceStabilityInterval before becoming a TrackedFace.
                if let pendingIdx = pendingObservations.indices.first(where: {
                    computeIoU(pendingObservations[$0].box, obs.boundingBox) > iouThreshold
                }) {
                    pendingObservations[pendingIdx].box = obs.boundingBox
                    pendingObservations[pendingIdx].lastSeen = now
                    if let fp = featurePrint {
                        pendingObservations[pendingIdx].featurePrint = fp
                    }
                } else {
                    let label = "Person \(Character(UnicodeScalar(64 + nextLabel)!))"
                    nextLabel += 1
                    if nextLabel > 26 { nextLabel = 1 }
                    let seed = featurePrint.map { computeAvatarSeed(from: $0) } ?? UInt64.random(in: 0...UInt64.max)
                    pendingObservations.append(PendingObservation(
                        id: UUID(),
                        box: obs.boundingBox,
                        firstSeen: now,
                        lastSeen: now,
                        featurePrint: featurePrint,
                        seed: seed,
                        label: label
                    ))
                }
            }
        }

        // Periodically refresh feature prints on active faces
        if now.timeIntervalSince(lastFeaturePrintTime) >= featurePrintUpdateInterval {
            lastFeaturePrintTime = now
            for i in faces.indices {
                if faces[i].featurePrint == nil {
                    faces[i].featurePrint = extractFeaturePrint(from: pixelBuffer, faceBox: faces[i].boundingBox)
                    if let fp = faces[i].featurePrint, faces[i].avatarSeed == 0 {
                        faces[i].avatarSeed = computeAvatarSeed(from: fp)
                    }
                }
            }
        }

        // Periodically re-save enrolled (named) faces to disk to improve embedding quality
        if now.timeIntervalSince(lastEnrollmentTime) >= enrollmentRefreshInterval,
           let store = embeddingStore {
            lastEnrollmentTime = now
            for face in faces where face.assignedPersonID != nil {
                if let fp = face.featurePrint, let personID = face.assignedPersonID {
                    store.save(personID: personID, personName: face.label, featurePrint: fp)
                    // Update in-memory cache
                    if let idx = storedEmbeddings.firstIndex(where: { $0.personID == personID }) {
                        storedEmbeddings[idx] = FaceEmbeddingStore.StoredEmbedding(
                            personID: personID, personName: face.label,
                            featurePrint: fp, sampleCount: storedEmbeddings[idx].sampleCount + 1
                        )
                    } else {
                        storedEmbeddings.append(FaceEmbeddingStore.StoredEmbedding(
                            personID: personID, personName: face.label,
                            featurePrint: fp, sampleCount: 1
                        ))
                    }
                }
            }
        }

        // Move expired faces to re-id pool before removing
        let expiring = faces.filter { now.timeIntervalSince($0.lastSeenTime) > expirationInterval }
        for face in expiring where face.featurePrint != nil {
            // Only keep faces that have a feature print for re-id
            if !recentlyExpired.contains(where: { $0.label == face.label }) {
                recentlyExpired.append(face)
            }
        }
        faces.removeAll { now.timeIntervalSince($0.lastSeenTime) > expirationInterval }

        // Expire old re-id candidates
        recentlyExpired.removeAll { now.timeIntervalSince($0.lastSeenTime) > reIdRetentionInterval }

        // Promote stable pending observations → tracked faces (5s stability threshold)
        pendingObservations = pendingObservations.compactMap { pending in
            guard now.timeIntervalSince(pending.lastSeen) <= expirationInterval else {
                return nil  // expired without becoming stable
            }
            guard now.timeIntervalSince(pending.firstSeen) >= newFaceStabilityInterval else {
                return pending  // still building stability
            }
            // Stable enough — promote to tracked face
            var newFace = TrackedFace(
                id: UUID(),
                boundingBox: pending.box,
                lastSeenTime: pending.lastSeen,
                label: pending.label,
                featurePrint: pending.featurePrint,
                avatarSeed: pending.seed
            )
            if let fp = pending.featurePrint, newFace.avatarSeed == 0 {
                newFace.avatarSeed = computeAvatarSeed(from: fp)
            }
            faces.append(newFace)
            return nil
        }

        // Notify face count change
        if faces.count != oldCount {
            onFaceCountChanged?(faces.count)
        }

        // Determine current speaker
        updateCurrentSpeaker()
    }

    // MARK: - Feature Print Extraction

    /// Crop the face region and generate a Vision feature print for re-identification.
    private func extractFeaturePrint(from pixelBuffer: CVPixelBuffer, faceBox: CGRect) -> VNFeaturePrintObservation? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let imageWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let imageHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        // Vision bbox: origin is bottom-left, y goes up — same as CIImage
        let cropRect = CGRect(
            x: faceBox.origin.x * imageWidth,
            y: faceBox.origin.y * imageHeight,
            width: faceBox.width * imageWidth,
            height: faceBox.height * imageHeight
        ).insetBy(dx: -10, dy: -10)  // slight padding for better embedding

        let croppedImage = ciImage.cropped(to: cropRect)
        guard croppedImage.extent.width > 10, croppedImage.extent.height > 10 else { return nil }

        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(ciImage: croppedImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        return request.results?.first
    }

    /// Find a matching face by feature print similarity.
    /// Checks in-session recently-expired pool first (fast path), then cross-session stored embeddings.
    /// Returns a TrackedFace template to restore identity from.
    private func findReIdMatch(featurePrint: VNFeaturePrintObservation) -> TrackedFace? {
        var bestMatch: TrackedFace?
        var bestDistance: Float = featurePrintDistanceThreshold

        // 1. In-session re-identification (recently left frame)
        for expired in recentlyExpired {
            guard let expiredPrint = expired.featurePrint else { continue }
            var distance: Float = 0
            do { try featurePrint.computeDistance(&distance, to: expiredPrint) } catch { continue }
            if distance < bestDistance {
                bestDistance = distance
                bestMatch = expired
            }
        }
        if bestMatch != nil { return bestMatch }

        // 2. Cross-session recognition (stored embeddings from previous sessions)
        for stored in storedEmbeddings {
            var distance: Float = 0
            do { try featurePrint.computeDistance(&distance, to: stored.featurePrint) } catch { continue }
            if distance < bestDistance {
                bestDistance = distance
                // Synthesise a TrackedFace shell carrying the stored person identity
                bestMatch = TrackedFace(
                    id: UUID(),
                    boundingBox: .zero,
                    lastSeenTime: Date(),
                    assignedPersonID: stored.personID,
                    label: stored.personName,
                    featurePrint: featurePrint,
                    avatarSeed: computeAvatarSeed(from: featurePrint)
                )
            }
        }
        return bestMatch
    }

    // MARK: - Avatar Seed

    /// Compute a deterministic hash from the feature print data for avatar generation.
    private func computeAvatarSeed(from featurePrint: VNFeaturePrintObservation) -> UInt64 {
        let data = featurePrint.data
        var hash: UInt64 = 5381
        data.withUnsafeBytes { buffer in
            for byte in buffer {
                hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
            }
        }
        return hash
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
            if let current = currentSpeakerTrackID,
               speakingFaces.contains(where: { $0.id == current }) {
                newSpeakerTrackID = current
            } else {
                newSpeakerTrackID = speakingFaces.first?.id
            }
        }

        if newSpeakerTrackID != currentSpeakerTrackID {
            currentSpeakerTrackID = newSpeakerTrackID
            let personID = faces.first(where: { $0.id == newSpeakerTrackID })?.assignedPersonID
            onSpeakerChanged?(personID)
        }
    }

    // MARK: - Person Assignment

    func assignPerson(trackID: UUID, personID: UUID, personName: String? = nil) {
        lock.withLock {
            guard let idx = faces.firstIndex(where: { $0.id == trackID }) else { return }
            faces[idx].assignedPersonID = personID
            if let name = personName { faces[idx].label = name }

            // Immediately enroll — persist embedding so the person is recognised next session
            if let fp = faces[idx].featurePrint, let store = embeddingStore {
                let name = faces[idx].label
                store.save(personID: personID, personName: name, featurePrint: fp)
                // Update in-memory cache
                let entry = FaceEmbeddingStore.StoredEmbedding(
                    personID: personID, personName: name, featurePrint: fp, sampleCount: 1
                )
                if let ei = storedEmbeddings.firstIndex(where: { $0.personID == personID }) {
                    storedEmbeddings[ei] = entry
                } else {
                    storedEmbeddings.append(entry)
                }
                Log.info(.camera, "FaceTracker: enrolled \(name) → persisted embedding")
            }
        }
    }

    // MARK: - Mouth Measurement

    private func measureMouthOpenness(_ observation: VNFaceObservation) -> CGFloat {
        guard let landmarks = observation.landmarks,
              let outerLips = landmarks.outerLips
        else { return 0 }

        let points = outerLips.normalizedPoints
        guard points.count >= 8 else { return 0 }

        let topIndex = min(2, points.count - 1)
        let bottomIndex = min(points.count - 2, points.count - 1)
        return abs(points[topIndex].y - points[bottomIndex].y)
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

// MARK: - PixelAvatar

/// Generates a deterministic pixel art avatar from a UInt64 seed.
/// Creates a 5×7 character face with mirrored symmetry — each person
/// gets a unique but stable avatar derived from their face embedding.
struct PixelAvatar {

    /// Palette of skin/feature colors — index chosen by seed bits.
    static let skinTones: [CGColor] = [
        CGColor(red: 1.00, green: 0.87, blue: 0.75, alpha: 1),  // light
        CGColor(red: 0.96, green: 0.80, blue: 0.65, alpha: 1),
        CGColor(red: 0.87, green: 0.68, blue: 0.53, alpha: 1),
        CGColor(red: 0.76, green: 0.57, blue: 0.42, alpha: 1),
        CGColor(red: 0.60, green: 0.42, blue: 0.30, alpha: 1),
        CGColor(red: 0.44, green: 0.30, blue: 0.22, alpha: 1),  // dark
    ]

    static let hairColors: [CGColor] = [
        CGColor(red: 0.15, green: 0.10, blue: 0.07, alpha: 1),  // black
        CGColor(red: 0.40, green: 0.26, blue: 0.13, alpha: 1),  // brown
        CGColor(red: 0.85, green: 0.65, blue: 0.20, alpha: 1),  // blonde
        CGColor(red: 0.70, green: 0.22, blue: 0.10, alpha: 1),  // red
        CGColor(red: 0.55, green: 0.55, blue: 0.60, alpha: 1),  // grey
        CGColor(red: 0.20, green: 0.50, blue: 0.90, alpha: 1),  // blue
        CGColor(red: 0.80, green: 0.20, blue: 0.60, alpha: 1),  // pink
        CGColor(red: 0.30, green: 0.75, blue: 0.45, alpha: 1),  // green
    ]

    static let eyeColor = CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
    static let bgColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)

    /// Generate a 5×7 pixel grid. Each cell is a CGColor.
    /// The grid is left-right mirrored (columns 0,1,2 are unique; 3=mirror of 1; 4=mirror of 0).
    static func generate(seed: UInt64) -> [[CGColor]] {
        let skinIdx = Int((seed >> 0) & 0x7) % skinTones.count
        let hairIdx = Int((seed >> 3) & 0x7) % hairColors.count
        let hairStyle = Int((seed >> 6) & 0x3)   // 0-3
        let eyeStyle = Int((seed >> 8) & 0x1)    // 0-1
        let mouthStyle = Int((seed >> 9) & 0x1)  // 0-1
        let hasGlasses = (seed >> 10) & 0x1 == 1

        let skin = skinTones[skinIdx]
        let hair = hairColors[hairIdx]
        let eye = eyeColor
        let bg = bgColor

        // Build left half (3 columns) × 7 rows, then mirror
        // Row layout: [hair, hair, forehead, eyes, nose, mouth, neck]
        var left: [[CGColor]] = Array(repeating: Array(repeating: bg, count: 3), count: 7)

        // Row 0: hair top
        switch hairStyle {
        case 0: left[0] = [bg, hair, hair]     // flat top
        case 1: left[0] = [hair, hair, hair]   // full top
        case 2: left[0] = [bg, hair, hair]     // side part
        case 3: left[0] = [hair, hair, bg]     // mohawk-ish
        default: left[0] = [bg, hair, hair]
        }

        // Row 1: hair sides + forehead
        switch hairStyle {
        case 0: left[1] = [bg, skin, skin]
        case 1: left[1] = [hair, skin, skin]
        case 2: left[1] = [hair, hair, skin]
        case 3: left[1] = [bg, skin, skin]
        default: left[1] = [bg, skin, skin]
        }

        // Row 2: forehead
        left[2] = [bg, skin, skin]

        // Row 3: eyes
        let eyePixel = hasGlasses ? CGColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1) : eye
        if eyeStyle == 0 {
            left[3] = [bg, eyePixel, skin]   // eyes at column 1
        } else {
            left[3] = [bg, skin, eyePixel]   // eyes at column 2
        }

        // Row 4: nose
        left[4] = [bg, skin, skin]

        // Row 5: mouth
        let mouthColor = CGColor(red: 0.8, green: 0.3, blue: 0.3, alpha: 1)
        if mouthStyle == 0 {
            left[5] = [bg, skin, mouthColor]  // small mouth
        } else {
            left[5] = [bg, mouthColor, mouthColor]  // wide mouth
        }

        // Row 6: neck/body
        let shirtColor = hairColors[Int((seed >> 12) & 0x7) % hairColors.count]
        left[6] = [bg, shirtColor, shirtColor]

        // Mirror to create 5-column grid
        var grid: [[CGColor]] = []
        for row in left {
            let fullRow = [row[0], row[1], row[2], row[1], row[0]]
            grid.append(fullRow)
        }

        return grid
    }
}
