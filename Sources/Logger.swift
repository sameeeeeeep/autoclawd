import Combine
import Foundation

// MARK: - Log Level

enum LogLevel: String, Comparable {
    case debug = "DEBUG"
    case info  = "INFO"
    case warn  = "WARN"
    case error = "ERROR"

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        let order: [LogLevel] = [.debug, .info, .warn, .error]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

// MARK: - Log Component

enum LogComponent: String {
    case audio     = "AUDIO"
    case transcribe = "TRANSCRIBE"
    case extract   = "EXTRACT"
    case world     = "WORLD"
    case todo      = "TODO"
    case clipboard = "CLIPBOARD"
    case system    = "SYSTEM"
    case ui        = "UI"
    case paste     = "PASTE"
    case qa        = "QA"
}

// MARK: - Log Entry

struct LogEntry {
    let timestamp: Date
    let level: LogLevel
    let component: LogComponent
    let message: String

    var formatted: String {
        let ts = LogEntry.formatter.string(from: timestamp)
        return "[\(ts)] [\(level.rawValue)] [\(component.rawValue)] \(message)"
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()
}

// MARK: - AutoClawdLogger

final class AutoClawdLogger: @unchecked Sendable {
    static let shared = AutoClawdLogger()

    /// Fires on every log entry, always on the main queue.
    static let toastPublisher = PassthroughSubject<LogEntry, Never>()

    private let queue = DispatchQueue(label: "com.autoclawd.logger", qos: .utility)
    private var fileHandle: FileHandle?
    private var currentLogDate: String = ""
    private let maxInMemory = 500
    private(set) var recentEntries: [LogEntry] = []

    var minimumLevel: LogLevel = .info
    var mirrorToConsole = true

    private init() {}

    func configure(storageManager: FileStorageManager) {
        queue.async { [weak self] in
            self?.openLogFile(storageManager: storageManager)
        }
    }

    func log(_ level: LogLevel, _ component: LogComponent, _ message: String) {
        guard level >= minimumLevel else { return }
        let entry = LogEntry(timestamp: Date(), level: level, component: component, message: message)
        queue.async { [weak self] in
            self?.write(entry)
        }
        DispatchQueue.main.async {
            AutoClawdLogger.toastPublisher.send(entry)
        }
    }

    // Convenience shorthand
    func debug(_ component: LogComponent, _ message: String) { log(.debug, component, message) }
    func info(_ component: LogComponent, _ message: String)  { log(.info,  component, message) }
    func warn(_ component: LogComponent, _ message: String)  { log(.warn,  component, message) }
    func error(_ component: LogComponent, _ message: String) { log(.error, component, message) }

    // Thread-safe snapshot of recent entries (for log viewer UI)
    func snapshot(limit: Int = 100, component: LogComponent? = nil) -> [LogEntry] {
        queue.sync {
            let entries = recentEntries
            let filtered = component == nil ? entries : entries.filter { $0.component == component }
            return Array(filtered.suffix(limit))
        }
    }

    // MARK: - Private

    private func write(_ entry: LogEntry) {
        // In-memory ring buffer
        recentEntries.append(entry)
        if recentEntries.count > maxInMemory {
            recentEntries.removeFirst(recentEntries.count - maxInMemory)
        }

        let line = entry.formatted + "\n"

        // Console mirror
        if mirrorToConsole {
            print(line, terminator: "")
        }

        // File write
        if let data = line.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }

    private func openLogFile(storageManager: FileStorageManager) {
        let dateStr = todayString()
        let url = storageManager.logFile(for: dateStr)
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
        fileHandle = try? FileHandle(forWritingTo: url)
        fileHandle?.seekToEndOfFile()
        currentLogDate = dateStr

        // Purge logs older than 7 days
        purgeOldLogs(storageManager: storageManager)
    }

    private func purgeOldLogs(storageManager: FileStorageManager) {
        let logDir = storageManager.logsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: logDir, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        for file in files where file.pathExtension == "log" {
            if let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
               let created = attrs.creationDate, created < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

// MARK: - Global shortcut

let Log = AutoClawdLogger.shared
