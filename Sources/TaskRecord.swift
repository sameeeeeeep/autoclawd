import Foundation

// MARK: - TaskRecord
//
// Pure view-model bridging Capability, PipelineTaskRecord, and LearnSession
// into a unified type for the Tasks panel. Does NOT replace any storage model —
// it is built on-the-fly from live data and never persisted directly.

// MARK: - Supporting Types

enum TaskRecordSource {
    case capability(Capability)
    case pipelineTask(PipelineTaskRecord)
    case learnSession(LearnSession)
}

enum TaskRecordStatus {
    case idle
    case running
    case completed
    case failed
    case needsInput
    case pendingApproval
    case building      // Learn Mode FUCBC session in progress
}

enum NodeStatus: Equatable {
    case idle
    case running
    case done
    case failed
}

// MARK: - WorkflowNodeViewModel

/// A single node in the Cofia-style workflow canvas.
struct WorkflowNodeViewModel: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String           // SF Symbol name
    let invocation: String?
    var status: NodeStatus

    init(id: String = UUID().uuidString,
         name: String,
         description: String,
         icon: String? = nil,
         invocation: String? = nil,
         status: NodeStatus = .idle) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon ?? WorkflowNodeViewModel.inferIcon(name: name, invocation: invocation)
        self.invocation = invocation
        self.status = status
    }

    /// Infer an SF Symbol from the node's name and invocation keywords.
    static func inferIcon(name: String, invocation: String?) -> String {
        let combined = "\(name) \(invocation ?? "")".lowercased()
        let map: [(keyword: String, symbol: String)] = [
            ("sheets", "tablecells.fill"),
            ("spreadsheet", "tablecells.fill"),
            ("maps", "map.fill"),
            ("location", "map.fill"),
            ("github", "chevron.left.slash.chevron.right"),
            ("git", "chevron.left.slash.chevron.right"),
            ("slack", "bubble.left.and.bubble.right.fill"),
            ("discord", "bubble.left.fill"),
            ("email", "envelope.fill"),
            ("mail", "envelope.fill"),
            ("gmail", "envelope.fill"),
            ("video", "video.fill"),
            ("youtube", "play.rectangle.fill"),
            ("twitter", "bird.fill"),
            ("threads", "at.circle.fill"),
            ("salesforce", "cloud.fill"),
            ("notion", "doc.richtext.fill"),
            ("claude", "sparkles"),
            ("llm", "sparkles"),
            ("ai", "sparkles"),
            ("search", "magnifyingglass"),
            ("google", "magnifyingglass"),
            ("browser", "safari.fill"),
            ("web", "globe"),
            ("http", "network"),
            ("api", "network"),
            ("file", "doc.fill"),
            ("pdf", "doc.text.fill"),
            ("image", "photo.fill"),
            ("photo", "photo.fill"),
            ("download", "arrow.down.circle.fill"),
            ("upload", "arrow.up.circle.fill"),
            ("database", "cylinder.fill"),
            ("sql", "cylinder.fill"),
            ("calendar", "calendar"),
            ("schedule", "calendar"),
            ("code", "chevron.left.slash.chevron.right"),
            ("script", "chevron.left.slash.chevron.right"),
            ("terminal", "terminal.fill"),
            ("shell", "terminal.fill"),
            ("python", "terminal.fill"),
            ("node", "terminal.fill"),
            ("npm", "terminal.fill"),
        ]
        for (keyword, symbol) in map {
            if combined.contains(keyword) { return symbol }
        }
        return "wrench.fill"
    }
}

// MARK: - TaskRecord

struct TaskRecord: Identifiable {
    let id: String
    let title: String
    let emoji: String
    let description: String
    let projectID: String?
    let projectName: String?
    let nodes: [WorkflowNodeViewModel]
    let status: TaskRecordStatus
    let isRecurring: Bool
    let cronExpression: String?
    let nextFireDate: Date?
    let createdAt: Date
    let pendingQuestion: String?
    let source: TaskRecordSource

    // MARK: - Factory: from Capability

    static func from(_ capability: Capability, schedule: TaskSchedule? = nil) -> TaskRecord {
        let nodes = capability.subWorkflows.map { sw in
            WorkflowNodeViewModel(
                id: sw.id,
                name: sw.name,
                description: sw.description,
                invocation: sw.invocation
            )
        }

        let cron = schedule?.cronExpression
        let nextFire = cron.flatMap { CronEvaluator.nextDate(from: $0) }

        return TaskRecord(
            id: capability.id,
            title: capability.name,
            emoji: capability.emoji,
            description: capability.description,
            projectID: nil,
            projectName: nil,
            nodes: nodes.isEmpty ? [defaultNode()] : nodes,
            status: .idle,
            isRecurring: schedule != nil,
            cronExpression: cron,
            nextFireDate: nextFire,
            createdAt: capability.createdAt,
            pendingQuestion: nil,
            source: .capability(capability)
        )
    }

    // MARK: - Factory: from PipelineTaskRecord

    static func from(_ record: PipelineTaskRecord) -> TaskRecord {
        let nodes: [WorkflowNodeViewModel] = record.workflowSteps.map { stepName in
            WorkflowNodeViewModel(name: stepName, description: stepName)
        }

        let status: TaskRecordStatus
        switch record.status {
        case .completed:          status = .completed
        case .ongoing:            status = .running
        case .pending_approval:   status = .pendingApproval
        case .needs_input:        status = .needsInput
        case .upcoming:           status = .idle
        case .filtered:           status = .idle
        }

        let schedule = TaskScheduleStore.shared.schedule(for: record.id)
        let cron = schedule?.cronExpression
        let nextFire = cron.flatMap { CronEvaluator.nextDate(from: $0) }

        return TaskRecord(
            id: record.id,
            title: record.title,
            emoji: emojiForTask(record),
            description: record.prompt.components(separatedBy: "\n").first ?? record.title,
            projectID: record.projectID,
            projectName: record.projectName,
            nodes: nodes.isEmpty ? [defaultNode()] : nodes,
            status: status,
            isRecurring: schedule != nil,
            cronExpression: cron,
            nextFireDate: nextFire,
            createdAt: record.createdAt,
            pendingQuestion: record.pendingQuestion,
            source: .pipelineTask(record)
        )
    }

    // MARK: - Factory: from LearnSession

    static func fromLearnSession(_ session: LearnSession) -> TaskRecord {
        let status: TaskRecordStatus
        switch session.phase {
        case .collecting:         status = .running
        case .building:           status = .building
        case .done:               status = .completed
        case .failed:             status = .failed
        }

        let eventCount = session.events.count
        let desc = eventCount == 0
            ? "Starting learn session…"
            : "\(eventCount) event\(eventCount == 1 ? "" : "s") captured · \(eventCount * 5)s"

        return TaskRecord(
            id: "learn-\(session.id.uuidString)",
            title: "Building Capability",
            emoji: "🧠",
            description: desc,
            projectID: nil,
            projectName: nil,
            nodes: [],         // detail view shows AICanvasView instead
            status: status,
            isRecurring: false,
            cronExpression: nil,
            nextFireDate: nil,
            createdAt: session.startedAt,
            pendingQuestion: nil,
            source: .learnSession(session)
        )
    }

    // MARK: - Helpers

    private static func defaultNode() -> WorkflowNodeViewModel {
        WorkflowNodeViewModel(name: "Run", description: "Execute capability", icon: "sparkles")
    }

    private static func emojiForTask(_ record: PipelineTaskRecord) -> String {
        let title = record.title.lowercased()
        if title.contains("write") || title.contains("draft")  { return "✍️" }
        if title.contains("send") || title.contains("email")   { return "📧" }
        if title.contains("search") || title.contains("find")  { return "🔍" }
        if title.contains("build") || title.contains("create") { return "🔨" }
        if title.contains("fix") || title.contains("bug")      { return "🐛" }
        if title.contains("test")                              { return "🧪" }
        if title.contains("deploy")                            { return "🚀" }
        if title.contains("analyse") || title.contains("analyze") { return "📊" }
        return "⚡️"
    }
}
