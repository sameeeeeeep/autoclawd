import Foundation
import SwiftUI

// MARK: - ParticipantKind

enum ParticipantKind: Equatable {
    case llama                                                      // AutoClawd PM — always present
    case claudeCode                                                 // joins via MCP session
    case connection(id: String, name: String, systemImage: String)  // plugin/tool participants
}

// MARK: - ParticipantState

enum ParticipantState {
    case idle        // present, quiet
    case thinking    // processing (spinner)
    case streaming   // outputting text
    case paused      // muted — not receiving transcript context
}

// MARK: - CallParticipant

struct CallParticipant: Identifiable {
    let id: String
    let kind: ParticipantKind
    var state: ParticipantState = .idle
    var isPaused: Bool = false
    var lastActivity: Date?

    var displayName: String {
        switch kind {
        case .llama:                             return "AutoClawd"
        case .claudeCode:                        return "Claw'd"
        case .connection(_, let name, _):        return name
        }
    }

    var mascotSystemImage: String {
        switch kind {
        case .llama:                             return "brain"
        case .claudeCode:                        return "hammer.fill"
        case .connection(_, _, let icon):        return icon
        }
    }

    /// Consistent color per participant — connections derive hue from their ID.
    var tileColor: Color {
        switch kind {
        case .llama:      return .teal
        case .claudeCode: return .orange
        case .connection(let id, _, _):
            let hash = id.unicodeScalars.reduce(0) { ($0 &+ Int($1.value)) % 360 }
            return Color(hue: Double(hash) / 360.0, saturation: 0.65, brightness: 0.95)
        }
    }

    /// Gesture finger slot (1-based) based on current participant order.
    /// Updated externally by CallRoom when participants array changes.
    var gestureSlot: Int = 1
}

// MARK: - CallRoom

/// Manages the set of participants in the active call and which one the user is addressing.
/// Llama is always participant[0] and cannot be removed.
@MainActor
final class CallRoom: ObservableObject {

    // MARK: Published State

    @Published private(set) var participants: [CallParticipant] = []
    @Published var activeParticipantID: String = "llama"

    // MARK: Init

    init() {
        var llama = CallParticipant(id: "llama", kind: .llama)
        llama.gestureSlot = 1
        participants = [llama]
    }

    // MARK: - Active Participant

    var activeParticipant: CallParticipant? {
        participants.first { $0.id == activeParticipantID }
    }

    /// Select participant by left-hand finger count (1-based index into participants array).
    func selectByGesture(fingerCount: Int) {
        let index = fingerCount - 1
        guard index >= 0, index < participants.count else { return }
        activeParticipantID = participants[index].id
    }

    // MARK: - Join / Leave

    func claudeCodeJoined() {
        guard !participants.contains(where: { $0.kind == .claudeCode }) else {
            // Already present — refresh lastActivity
            updateLastActivity(id: "claude-code")
            return
        }
        var p = CallParticipant(id: "claude-code", kind: .claudeCode, lastActivity: Date())
        rebuildSlots()
        p.gestureSlot = participants.count + 1
        participants.append(p)
        rebuildSlots()
    }

    func claudeCodeLeft() {
        participants.removeAll { $0.kind == .claudeCode }
        if activeParticipantID == "claude-code" { activeParticipantID = "llama" }
        rebuildSlots()
    }

    func connectionJoined(id: String, name: String, systemImage: String = "cable.connector") {
        guard !participants.contains(where: { $0.id == id }) else {
            updateLastActivity(id: id)
            return
        }
        var p = CallParticipant(id: id, kind: .connection(id: id, name: name, systemImage: systemImage))
        p.gestureSlot = participants.count + 1
        participants.append(p)
        rebuildSlots()
    }

    func connectionLeft(id: String) {
        participants.removeAll { $0.id == id }
        if activeParticipantID == id { activeParticipantID = "llama" }
        rebuildSlots()
    }

    // MARK: - Pause / Resume / Remove

    func togglePause(id: String) {
        guard let idx = participants.firstIndex(where: { $0.id == id }) else { return }
        participants[idx].isPaused.toggle()
        if participants[idx].isPaused { participants[idx].state = .paused }
        else if participants[idx].state == .paused { participants[idx].state = .idle }
    }

    /// Remove a participant (Llama cannot be removed).
    func remove(id: String) {
        guard id != "llama" else { return }
        participants.removeAll { $0.id == id }
        if activeParticipantID == id { activeParticipantID = "llama" }
        rebuildSlots()
    }

    // MARK: - State Updates

    func setState(_ state: ParticipantState, for id: String) {
        guard let idx = participants.firstIndex(where: { $0.id == id }) else { return }
        guard !participants[idx].isPaused else { return }
        participants[idx].state = state
        participants[idx].lastActivity = Date()
    }

    func updateLastActivity(id: String) {
        guard let idx = participants.firstIndex(where: { $0.id == id }) else { return }
        participants[idx].lastActivity = Date()
    }

    // MARK: - MCP Pause Gating

    /// True when Claude Code is in the room and NOT paused — MCP transcript is live.
    var claudeCodeIsActive: Bool {
        guard let p = participants.first(where: { $0.kind == .claudeCode }) else { return false }
        return !p.isPaused
    }

    var claudeCodeIsPresent: Bool {
        participants.contains { $0.kind == .claudeCode }
    }

    // MARK: - Helpers

    private func rebuildSlots() {
        for i in participants.indices {
            participants[i].gestureSlot = i + 1
        }
    }
}
