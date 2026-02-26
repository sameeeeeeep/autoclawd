import SwiftUI

// MARK: - Color Palette

enum PersonColor: Int, CaseIterable, Codable {
    case neonGreen, cyan, orange, purple, pink, yellow, teal, red

    var color: Color {
        switch self {
        case .neonGreen: return AppTheme.green
        case .cyan:      return Color(red: 0.0, green: 0.85, blue: 1.0)
        case .orange:    return Color(red: 1.0, green: 0.65, blue: 0.0)
        case .purple:    return Color(red: 0.72, green: 0.38, blue: 1.0)
        case .pink:      return Color(red: 1.0, green: 0.40, blue: 0.75)
        case .yellow:    return Color(red: 1.0, green: 0.90, blue: 0.20)
        case .teal:      return Color(red: 0.20, green: 0.80, blue: 0.70)
        case .red:       return Color(red: 1.0, green: 0.28, blue: 0.28)
        }
    }
}

// MARK: - Person

struct Person: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var colorIndex: Int          // PersonColor.rawValue
    var mapPosition: CGPoint     // normalized 0..1
    var isMe: Bool
    var isMusic: Bool

    var personColor: PersonColor {
        PersonColor(rawValue: colorIndex) ?? .cyan
    }

    var color: Color { personColor.color }

    static func makeMe() -> Person {
        Person(id: UUID(), name: "You", colorIndex: PersonColor.neonGreen.rawValue,
               mapPosition: CGPoint(x: 0.50, y: 0.58), isMe: true)
    }

    static func makeMusic() -> Person {
        Person(id: UUID(), name: "Music ♫",
               colorIndex: PersonColor.pink.rawValue,
               mapPosition: CGPoint(x: 0.82, y: 0.80),
               isMe: false, isMusic: true)
    }

    // CGPoint is not Codable by default
    enum CodingKeys: String, CodingKey {
        case id, name, colorIndex, posX, posY, isMe, isMusic
    }
    init(id: UUID, name: String, colorIndex: Int, mapPosition: CGPoint, isMe: Bool, isMusic: Bool = false) {
        self.id = id; self.name = name; self.colorIndex = colorIndex
        self.mapPosition = mapPosition; self.isMe = isMe; self.isMusic = isMusic
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(UUID.self,    forKey: .id)
        name        = try c.decode(String.self,  forKey: .name)
        colorIndex  = try c.decode(Int.self,     forKey: .colorIndex)
        isMe        = try c.decode(Bool.self,    forKey: .isMe)
        isMusic     = (try? c.decode(Bool.self, forKey: .isMusic)) ?? false
        let x       = try c.decode(CGFloat.self, forKey: .posX)
        let y       = try c.decode(CGFloat.self, forKey: .posY)
        mapPosition = CGPoint(x: x, y: y)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,             forKey: .id)
        try c.encode(name,           forKey: .name)
        try c.encode(colorIndex,     forKey: .colorIndex)
        try c.encode(isMe,           forKey: .isMe)
        try c.encode(isMusic,        forKey: .isMusic)
        try c.encode(mapPosition.x,  forKey: .posX)
        try c.encode(mapPosition.y,  forKey: .posY)
    }
}
