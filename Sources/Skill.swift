import Foundation

// MARK: - Skill Category

enum SkillCategory: String, Codable, CaseIterable {
    case pipeline       // transcript-cleaning, transcript-analysis, task-creation
    case development    // frontend-design, backend-dev
    case analysis       // data-analysis
    case management     // project-management
    case creative       // video-generation, image-generation
    case marketing      // campaign-activation
    case other
}

// MARK: - Skill

/// A skill defines a prompt template and optional workflow for a specific task type.
/// Skills are stored as individual JSON files in ~/.autoclawd/skills/ so users can view/edit them.
struct Skill: Identifiable, Codable {
    let id: String
    var name: String
    var description: String
    var promptTemplate: String
    var workflowID: String?
    var category: SkillCategory
    var isBuiltin: Bool
}
