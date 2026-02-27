import Foundation

// MARK: - Raw Chunk

struct RawChunk: Identifiable {
    let id: String
    let duration: String
    let text: String
}

// MARK: - Task Enums

enum TaskMode: String {
    case auto, ask, user
}

enum TaskStatus: String {
    case completed, ongoing, pending_approval, needs_input, upcoming, filtered
}

// MARK: - Task Result

struct TaskResult {
    let steps: [String]
    let finalStatus: String
    let duration: String
}

// MARK: - Pipeline Task

struct PipelineTask: Identifiable {
    let id: String
    let title: String
    let prompt: String
    let project: String
    let mode: TaskMode
    var status: TaskStatus
    let skill: String?
    let workflow: String?
    let workflowSteps: [String]
    let missingConnection: String?
    let pendingQuestion: String?
    let result: TaskResult
}

// MARK: - Pipeline Group

struct PipelineGroup: Identifiable {
    let id: String
    let rawChunks: [RawChunk]
    let cleaningTags: [String]
    let cleanedText: String?
    let analysisTags: [String]
    let analysisProject: String?
    let analysisText: String?
    let tasks: [PipelineTask]
    let placeTag: String?
    let personTag: String?
    let time: String
    let timeSeconds: Int

    // MARK: - Mock Data

    static func mockData() -> [PipelineGroup] {
        [mockG1(), mockG2(), mockG3(), mockG4(), mockG5(), mockG6(), mockG7()]
    }

    // MARK: g1 — Dynamic widget component

    private static func mockG1() -> PipelineGroup {
        PipelineGroup(
            id: "g1",
            rawChunks: [
                RawChunk(id: "26.01.03 43A", duration: "30s",
                         text: "So for the widget I think we need three modes — a compact one for the menu bar, a medium card, and then the full expanded view that shows the transcript live."),
                RawChunk(id: "26.01.03 43B", duration: "22s",
                         text: "The compact mode should just pulse with the accent colour when recording. Medium shows the last extraction. Full mode is basically the sustained transcript."),
                RawChunk(id: "26.01.03 43C", duration: "18s",
                         text: "Let's make each mode a separate SwiftUI component that conforms to a WidgetVariant protocol so they're hot-swappable."),
            ],
            cleaningTags: ["Continued transcript", "3 chunks merged"],
            cleanedText: "Design a dynamic widget system with three modes: compact (menu-bar pulse), medium (last extraction card), and full (sustained live transcript). Each mode should be a SwiftUI component conforming to a WidgetVariant protocol for hot-swapping.",
            analysisTags: ["dot p0"],
            analysisProject: "autoclawd",
            analysisText: "New feature request: dynamic widget component with three layout variants.",
            tasks: [
                PipelineTask(
                    id: "T-AC-048",
                    title: "Dynamic widget component per mode",
                    prompt: "Create a WidgetVariant protocol and three conforming SwiftUI views: CompactWidget, MediumWidget, FullWidget. Compact pulses accent colour when recording. Medium shows last ExtractionItem. Full streams transcript text with auto-scroll.",
                    project: "autoclawd",
                    mode: .auto,
                    status: .completed,
                    skill: "frontend-design",
                    workflow: "AutoClawd \u{2192} Claude Code CLI",
                    workflowSteps: [
                        "AutoClawd captures requirement",
                        "Prompt dispatched to Claude Code CLI",
                        "Claude Code generates Swift files",
                        "Files written to project Sources/",
                    ],
                    missingConnection: nil,
                    pendingQuestion: nil,
                    result: TaskResult(
                        steps: [
                            "Parsed requirement into 3 widget variants",
                            "Skill: frontend-design selected",
                            "Generated WidgetVariant protocol",
                            "Created CompactWidget.swift (42 lines)",
                            "Created MediumWidget.swift (67 lines)",
                            "Created FullWidget.swift (89 lines)",
                            "All 3 views compiled successfully",
                        ],
                        finalStatus: "3 widget components generated and compiled",
                        duration: "1m 34s"
                    )
                ),
            ],
            placeTag: "office",
            personTag: "you",
            time: "6:43 PM",
            timeSeconds: 18 * 3600 + 43 * 60
        )
    }

    // MARK: g2 — Beta feedback + API timeline

    private static func mockG2() -> PipelineGroup {
        PipelineGroup(
            id: "g2",
            rawChunks: [
                RawChunk(id: "26.01.03 38A", duration: "45s",
                         text: "Mukul was saying the beta feedback is all over the place — we need to compile it into themes. Also the API integration timeline needs to slip to next sprint, there's no way we finish the auth flow this week."),
            ],
            cleaningTags: ["Single chunk"],
            cleanedText: "Compile Trippy beta feedback into thematic clusters. Reschedule API integration work to the next sprint due to incomplete auth flow.",
            analysisTags: ["dot p1", "schedule change"],
            analysisProject: "trippy",
            analysisText: "Two action items: feedback synthesis and sprint rescheduling.",
            tasks: [
                PipelineTask(
                    id: "T-TR-031",
                    title: "Compile Trippy beta feedback",
                    prompt: "Aggregate all Trippy beta feedback entries, cluster by theme (UX, performance, features, bugs), and produce a ranked summary with occurrence counts.",
                    project: "trippy",
                    mode: .auto,
                    status: .completed,
                    skill: "data-analysis",
                    workflow: nil,
                    workflowSteps: [],
                    missingConnection: nil,
                    pendingQuestion: nil,
                    result: TaskResult(
                        steps: [
                            "Fetched 47 beta feedback entries",
                            "Skill: data-analysis selected",
                            "Clustered into 5 themes via embedding similarity",
                            "Top theme: offline mode (12 mentions)",
                            "Generated ranked summary document",
                        ],
                        finalStatus: "Feedback compiled into 5 themes, summary saved",
                        duration: "48s"
                    )
                ),
                PipelineTask(
                    id: "T-TR-032",
                    title: "Reschedule API integration to next sprint",
                    prompt: "Move all API integration tasks in Linear from Sprint 4 to Sprint 5. Update due dates and notify the team.",
                    project: "trippy",
                    mode: .ask,
                    status: .pending_approval,
                    skill: "project-management",
                    workflow: "AutoClawd \u{2192} Claude Code CLI \u{2192} Linear",
                    workflowSteps: [
                        "AutoClawd captures schedule change",
                        "Prompt dispatched to Claude Code CLI",
                        "Claude Code prepares Linear API calls",
                        "Linear tasks updated via API",
                    ],
                    missingConnection: nil,
                    pendingQuestion: "Move 4 API tasks from Sprint 4 to Sprint 5 and notify the team on Slack?",
                    result: TaskResult(
                        steps: [
                            "Identified 4 API integration tasks in Sprint 4",
                            "Skill: project-management selected",
                            "Prepared batch move to Sprint 5",
                            "Awaiting approval before executing",
                        ],
                        finalStatus: "Pending approval",
                        duration: "12s"
                    )
                ),
            ],
            placeTag: "office",
            personTag: "mukul",
            time: "10:00 AM",
            timeSeconds: 10 * 3600
        )
    }

    // MARK: g3 — Speaker diarization bug

    private static func mockG3() -> PipelineGroup {
        PipelineGroup(
            id: "g3",
            rawChunks: [
                RawChunk(id: "26.01.03 62A", duration: "8s",
                         text: "Is it not able to detect my voice? It keeps attributing everything to speaker 2."),
            ],
            cleaningTags: ["Short utterance"],
            cleanedText: "Speaker diarization is misattributing all speech to speaker 2 instead of recognising the primary user's voice.",
            analysisTags: ["bug", "dot p0"],
            analysisProject: "autoclawd",
            analysisText: "Bug report: speaker diarization failing to identify primary user.",
            tasks: [
                PipelineTask(
                    id: "T-AC-047",
                    title: "Fix speaker diarization bug",
                    prompt: "Investigate why pyannote diarization assigns all segments to speaker_02. Check the embedding model's voice enrollment for the primary user and verify the cosine-similarity threshold.",
                    project: "autoclawd",
                    mode: .auto,
                    status: .ongoing,
                    skill: "audio-ml",
                    workflow: nil,
                    workflowSteps: [],
                    missingConnection: nil,
                    pendingQuestion: nil,
                    result: TaskResult(
                        steps: [
                            "Reproduced issue with test recording",
                            "Skill: audio-ml selected",
                            "Found stale voice embedding in enrollment cache",
                            "Re-enrolling primary speaker voice print",
                            "Running validation on 10 test segments...",
                        ],
                        finalStatus: "In progress — re-enrollment running",
                        duration: "3m 12s"
                    )
                ),
            ],
            placeTag: "home",
            personTag: "you",
            time: "2:30 AM",
            timeSeconds: 2 * 3600 + 30 * 60
        )
    }

    // MARK: g4 — Book flights

    private static func mockG4() -> PipelineGroup {
        PipelineGroup(
            id: "g4",
            rawChunks: [
                RawChunk(id: "26.01.03 35A", duration: "12s",
                         text: "I need to book flights from Mumbai to Bangalore, sometime next week. Check what's available."),
            ],
            cleaningTags: ["Single chunk"],
            cleanedText: "Book Mumbai to Bangalore flights for next week.",
            analysisTags: ["personal", "travel"],
            analysisProject: "personal",
            analysisText: "Personal travel booking request.",
            tasks: [
                PipelineTask(
                    id: "T-PS-012",
                    title: "Book Mumbai \u{2192} Bangalore flights",
                    prompt: "Search for Mumbai (BOM) to Bangalore (BLR) flights for next week. Show options sorted by price with departure times.",
                    project: "personal",
                    mode: .ask,
                    status: .needs_input,
                    skill: "travel-booking",
                    workflow: nil,
                    workflowSteps: [],
                    missingConnection: "No flight booking API connected",
                    pendingQuestion: "Which dates next week? One-way or round trip?",
                    result: TaskResult(
                        steps: [
                            "Parsed travel request: BOM \u{2192} BLR",
                            "Skill: travel-booking selected",
                            "No flight booking connector found",
                            "Blocked — awaiting API connection and date clarification",
                        ],
                        finalStatus: "Needs input — missing connection and dates",
                        duration: "4s"
                    )
                ),
            ],
            placeTag: "cafe",
            personTag: "you",
            time: "1:00 PM",
            timeSeconds: 13 * 3600
        )
    }

    // MARK: g5 — Filtered "Thank you"

    private static func mockG5() -> PipelineGroup {
        PipelineGroup(
            id: "g5",
            rawChunks: [
                RawChunk(id: "26.01.03 54A", duration: "3s",
                         text: "Thank you so much, that was really helpful."),
            ],
            cleaningTags: ["Filtered"],
            cleanedText: nil,
            analysisTags: [],
            analysisProject: nil,
            analysisText: nil,
            tasks: [],
            placeTag: "cafe",
            personTag: "priya",
            time: "7:09 PM",
            timeSeconds: 19 * 3600 + 9 * 60
        )
    }

    // MARK: g6 — Sustained transcript mode

    private static func mockG6() -> PipelineGroup {
        PipelineGroup(
            id: "g6",
            rawChunks: [
                RawChunk(id: "26.01.03 30A", duration: "25s",
                         text: "We should add a sustained transcript mode to the widget — where it just keeps streaming text as you talk, like live captions but persisted."),
            ],
            cleaningTags: ["Single chunk"],
            cleanedText: "Add a sustained transcript mode to the widget that streams and persists live caption text.",
            analysisTags: ["feature", "dot p1"],
            analysisProject: "autoclawd",
            analysisText: "Feature request: sustained live transcript mode for the widget.",
            tasks: [
                PipelineTask(
                    id: "T-AC-049",
                    title: "Sustained transcript mode for widget",
                    prompt: "Implement a FullWidget variant that streams transcript text in real-time with auto-scroll anchoring. Text persists across recording sessions.",
                    project: "autoclawd",
                    mode: .auto,
                    status: .upcoming,
                    skill: "frontend-design",
                    workflow: nil,
                    workflowSteps: [],
                    missingConnection: nil,
                    pendingQuestion: nil,
                    result: TaskResult(
                        steps: [
                            "Queued for execution",
                            "Skill: frontend-design pre-selected",
                            "Depends on T-AC-048 (WidgetVariant protocol)",
                        ],
                        finalStatus: "Upcoming",
                        duration: "—"
                    )
                ),
            ],
            placeTag: "office",
            personTag: "mukul",
            time: "2:00 PM",
            timeSeconds: 14 * 3600
        )
    }

    // MARK: g7 — Monotone theme

    private static func mockG7() -> PipelineGroup {
        PipelineGroup(
            id: "g7",
            rawChunks: [
                RawChunk(id: "26.01.03 28A", duration: "15s",
                         text: "I want to add a monotone appearance theme — all greys, no colour accents. For when you want minimal visual distraction."),
            ],
            cleaningTags: ["Single chunk"],
            cleanedText: "Add a monotone greyscale appearance theme with no colour accents for minimal visual distraction.",
            analysisTags: ["feature", "dot p2"],
            analysisProject: "autoclawd",
            analysisText: "Feature request: monotone/greyscale theme option.",
            tasks: [
                PipelineTask(
                    id: "T-AC-050",
                    title: "Add monotone appearance theme",
                    prompt: "Create a new ThemePalette.monotone with greyscale-only colours. Add ThemeKey.monotone case. All accent, tag, and glow colours should be shades of grey.",
                    project: "autoclawd",
                    mode: .user,
                    status: .upcoming,
                    skill: "frontend-design",
                    workflow: nil,
                    workflowSteps: [],
                    missingConnection: nil,
                    pendingQuestion: nil,
                    result: TaskResult(
                        steps: [
                            "Queued for execution",
                            "Skill: frontend-design pre-selected",
                            "User-initiated — will run on explicit trigger",
                        ],
                        finalStatus: "Upcoming",
                        duration: "—"
                    )
                ),
            ],
            placeTag: "office",
            personTag: "you",
            time: "11:30 AM",
            timeSeconds: 11 * 3600 + 30 * 60
        )
    }
}
