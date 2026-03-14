import Foundation

// MARK: - TaskScheduler
//
// Background service that fires scheduled tasks based on their cron expressions.
// Runs a repeating 60-second timer and checks TaskScheduleStore for due tasks.
// Integrates with AppState to execute capabilities or pipeline tasks.

@MainActor
final class TaskScheduler {

    static let shared = TaskScheduler()

    weak var appState: AppState?

    private var timer: Timer?
    private var isStarted = false

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        Log.info(.system, "TaskScheduler: started")
        // Fire immediately to catch any tasks missed while app was closed
        Task { @MainActor in tick() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isStarted = false
        Log.info(.system, "TaskScheduler: stopped")
    }

    // MARK: - Tick

    private func tick() {
        let enabled = TaskScheduleStore.shared.allEnabled()
        let now = Date()

        for schedule in enabled {
            let after = schedule.lastFiredAt ?? .distantPast
            guard let nextFire = CronEvaluator.nextDate(from: schedule.cronExpression, after: after) else {
                continue
            }
            guard nextFire <= now else { continue }

            Log.info(.pipeline, "TaskScheduler: firing '\(schedule.taskID)' (cron: \(schedule.cronExpression))")
            fireTask(taskID: schedule.taskID)
            TaskScheduleStore.shared.markFired(schedule.taskID)
        }
    }

    // MARK: - Firing

    private func fireTask(taskID: String) {
        guard let appState else {
            Log.warn(.system, "TaskScheduler: no appState, cannot fire \(taskID)")
            return
        }

        // Try capability first
        if let cap = CapabilityStore.shared.load(id: taskID) {
            appState.executeCapability(cap)
            return
        }

        // Fall back to pipeline task
        if appState.pipelineTasks.contains(where: { $0.id == taskID }) {
            appState.runPipelineTask(id: taskID)
            return
        }

        Log.warn(.system, "TaskScheduler: task not found for id \(taskID)")
    }
}
