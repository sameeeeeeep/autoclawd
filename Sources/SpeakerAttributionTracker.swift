import Foundation

// MARK: - SpeakerAttributionTracker

/// Tracks timestamped speaker-change events from FaceTracker.
/// Used at session end to annotate the transcript with speaker attribution context.
///
/// Flow:
///   FaceTracker.onSpeakerChanged → logSpeakerChange(personID:name:)
///   AppState.stopUserSession     → speakerSummary(from:to:) → passed to pipeline
///   TranscriptCleaningService    → injects summary into LLM prompt
final class SpeakerAttributionTracker: @unchecked Sendable {

    // MARK: - Types

    struct SpeakerEvent {
        let personID: UUID?
        let name: String?
        let at: Date
    }

    // MARK: - State

    private let lock = NSLock()
    private var events: [SpeakerEvent] = []
    private(set) var sessionStartTime: Date = Date()

    // MARK: - Session Lifecycle

    func beginSession() {
        lock.withLock {
            events.removeAll()
            sessionStartTime = Date()
        }
    }

    func endSession() {
        // Events are kept until next beginSession() so callers can still query after stop.
    }

    // MARK: - Logging

    /// Record a speaker-change event. Called from FaceTracker.onSpeakerChanged.
    func logSpeakerChange(personID: UUID?, name: String?) {
        let event = SpeakerEvent(personID: personID, name: name, at: Date())
        lock.withLock { events.append(event) }
    }

    // MARK: - Attribution Query

    /// Returns speaker segments within [start, end], ordered chronologically.
    /// Each entry has the speaker name (nil = unknown/silence) and duration in seconds.
    func attributedSegments(from start: Date, to end: Date) -> [(name: String?, duration: TimeInterval)] {
        let chunkDuration = end.timeIntervalSince(start)
        guard chunkDuration > 0 else { return [] }

        let allEvents = lock.withLock { events }

        // Who was speaking at chunk start (last event before start)
        let initialSpeaker = allEvents.last(where: { $0.at <= start })

        // Events inside the chunk window
        let windowEvents = allEvents.filter { $0.at > start && $0.at < end }

        // Build timeline: [(name, segmentStart)]
        var timeline: [(name: String?, at: Date)] = []
        if let initial = initialSpeaker {
            timeline.append((name: initial.name, at: start))
        } else {
            timeline.append((name: nil, at: start))  // unknown at chunk start
        }
        for ev in windowEvents {
            timeline.append((name: ev.name, at: ev.at))
        }
        timeline.append((name: nil, at: end))  // sentinel

        // Convert to (name, duration) pairs
        var segments: [(name: String?, duration: TimeInterval)] = []
        for i in 0..<timeline.count - 1 {
            let duration = timeline[i + 1].at.timeIntervalSince(timeline[i].at)
            if duration > 0.5 {  // skip sub-half-second noise
                segments.append((name: timeline[i].name, duration: duration))
            }
        }
        return segments
    }

    /// Human-readable speaker summary for a time window, e.g. "Alice: 90s, Bob: 45s".
    /// Returns nil when only one unidentified speaker is detected.
    func speakerSummary(from start: Date, to end: Date) -> String? {
        let segments = attributedSegments(from: start, to: end)
        let named = segments.filter { $0.name != nil }
        guard !named.isEmpty else { return nil }

        // Aggregate by name
        var totals: [String: TimeInterval] = [:]
        for seg in named {
            guard let name = seg.name else { continue }
            totals[name, default: 0] += seg.duration
        }
        guard !totals.isEmpty else { return nil }

        let sorted = totals.sorted { $0.value > $1.value }
        // Single named speaker — simple format
        if sorted.count == 1, let only = sorted.first {
            return "Speaker: \(only.key)"
        }
        // Multiple — list with durations
        return sorted.map { "\($0.key): \(Int($0.value))s" }.joined(separator: ", ")
    }

    /// Full-session summary from sessionStartTime to now.
    func sessionSpeakerSummary() -> String? {
        speakerSummary(from: sessionStartTime, to: Date())
    }
}
