import Foundation

// MARK: - TaskSchedule

/// Associates a cron expression with a task ID.
/// Capabilities and pipeline tasks are both referenced by their `id`.
struct TaskSchedule: Codable, Identifiable {
    let id: String               // == taskID
    let taskID: String
    let cronExpression: String
    var enabled: Bool
    var lastFiredAt: Date?
    let createdAt: Date

    var nextFireDate: Date? { CronEvaluator.nextDate(from: cronExpression) }
    var humanSchedule: String { CronEvaluator.humanReadable(cronExpression) }
}

// MARK: - TaskScheduleStore

/// Thread-safe persistence of task schedules to
/// `~/.autoclawd/schedules/index.json`.
final class TaskScheduleStore: @unchecked Sendable {

    static let shared = TaskScheduleStore()

    private let queue = DispatchQueue(label: "com.autoclawd.taskschedulestore", qos: .utility)
    private var schedules: [String: TaskSchedule] = [:]   // keyed by taskID
    private let storeURL: URL

    // MARK: - Init

    private init() {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".autoclawd/schedules", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        storeURL = base.appendingPathComponent("index.json")
        load()
    }

    // MARK: - Read

    func schedule(for taskID: String) -> TaskSchedule? {
        queue.sync { schedules[taskID] }
    }

    func allEnabled() -> [TaskSchedule] {
        queue.sync { Array(schedules.values).filter { $0.enabled } }
    }

    func all() -> [TaskSchedule] {
        queue.sync { Array(schedules.values) }
    }

    // MARK: - Write

    func save(_ schedule: TaskSchedule) {
        queue.async { [weak self] in
            guard let self else { return }
            self.schedules[schedule.taskID] = schedule
            self.persist()
        }
    }

    func delete(taskID: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.schedules.removeValue(forKey: taskID)
            self.persist()
        }
    }

    func markFired(_ taskID: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard var schedule = self.schedules[taskID] else { return }
            schedule = TaskSchedule(
                id: schedule.id,
                taskID: schedule.taskID,
                cronExpression: schedule.cronExpression,
                enabled: schedule.enabled,
                lastFiredAt: Date(),
                createdAt: schedule.createdAt
            )
            self.schedules[taskID] = schedule
            self.persist()
        }
    }

    func setEnabled(_ enabled: Bool, taskID: String) {
        queue.async { [weak self] in
            guard let self, var schedule = self.schedules[taskID] else { return }
            schedule = TaskSchedule(
                id: schedule.id,
                taskID: schedule.taskID,
                cronExpression: schedule.cronExpression,
                enabled: enabled,
                lastFiredAt: schedule.lastFiredAt,
                createdAt: schedule.createdAt
            )
            self.schedules[taskID] = schedule
            self.persist()
        }
    }

    // MARK: - Persistence

    private func load() {
        queue.sync {
            guard let data = try? Data(contentsOf: storeURL) else { return }
            let decoded = (try? JSONDecoder().decode([TaskSchedule].self, from: data)) ?? []
            schedules = Dictionary(uniqueKeysWithValues: decoded.map { ($0.taskID, $0) })
        }
    }

    private func persist() {
        let items = Array(schedules.values)
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
