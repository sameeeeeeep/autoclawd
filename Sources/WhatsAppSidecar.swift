import Foundation

// MARK: - WhatsAppSidecar

/// Manages the Node.js WhatsApp sidecar process lifecycle.
/// Spawns `npx tsx src/index.ts` from the bundled WhatsAppSidecar directory,
/// monitors its health, and auto-restarts on unexpected exit.
final class WhatsAppSidecar: @unchecked Sendable {

    static let shared = WhatsAppSidecar()

    // MARK: - Configuration

    static let port: Int = 7891
    static let baseURL = "http://127.0.0.1:\(port)"

    // MARK: - State

    private var process: Process?
    private var outputPipe: Pipe?
    private var isRunning = false
    private var restartCount = 0
    private let maxRestartAttempts = 5
    private var intentionallyStopped = false

    private let queue = DispatchQueue(label: "com.autoclawd.whatsapp-sidecar", qos: .utility)

    private init() {}

    // MARK: - Node.js Discovery

    /// Find the `node` executable, checking common paths then falling back to `which`.
    private static func findNode() -> URL? {
        let candidates = [
            "/usr/local/bin/node",
            "/opt/homebrew/bin/node",
            "/usr/bin/node",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        // Fall back to `which node` via login shell
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-l", "-c", "which node"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let found = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !found.isEmpty,
           FileManager.default.isExecutableFile(atPath: found) {
            return URL(fileURLWithPath: found)
        }
        return nil
    }

    /// Find the `npx` executable alongside node.
    private static func findNpx() -> URL? {
        if let nodeURL = findNode() {
            let npxPath = nodeURL.deletingLastPathComponent().appendingPathComponent("npx").path
            if FileManager.default.isExecutableFile(atPath: npxPath) {
                return URL(fileURLWithPath: npxPath)
            }
        }
        // Direct check
        let candidates = [
            "/usr/local/bin/npx",
            "/opt/homebrew/bin/npx",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// Path to the bundled WhatsAppSidecar directory.
    /// Checks: 1) App bundle Resources, 2) Development directory alongside Sources.
    private static func sidecarDirectory() -> URL? {
        // 1. Check inside app bundle
        if let bundlePath = Bundle.main.resourcePath {
            let bundled = URL(fileURLWithPath: bundlePath)
                .appendingPathComponent("WhatsAppSidecar")
            if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("package.json").path) {
                return bundled
            }
        }
        // 2. Check development path (same directory as the executable, up to project root)
        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        var dir = execURL.deletingLastPathComponent()
        // Walk up to find WhatsAppSidecar/package.json
        for _ in 0..<5 {
            let candidate = dir.appendingPathComponent("WhatsAppSidecar")
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("package.json").path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    // MARK: - Lifecycle

    /// Start the sidecar process.
    func start() {
        queue.async { [weak self] in
            self?.startSync()
        }
    }

    private func startSync() {
        guard !isRunning else {
            Log.info(.system, "[WhatsApp] Sidecar already running")
            return
        }

        intentionallyStopped = false

        guard let npxURL = Self.findNpx() else {
            Log.warn(.system, "[WhatsApp] npx not found — cannot start sidecar. Install Node.js >= 20.")
            return
        }

        guard let sidecarDir = Self.sidecarDirectory() else {
            Log.warn(.system, "[WhatsApp] WhatsAppSidecar directory not found")
            return
        }

        // Ensure node_modules exist
        let nodeModules = sidecarDir.appendingPathComponent("node_modules")
        if !FileManager.default.fileExists(atPath: nodeModules.path) {
            Log.info(.system, "[WhatsApp] Installing sidecar dependencies...")
            installDependencies(npxURL: npxURL, sidecarDir: sidecarDir)
        }

        let authDir = FileStorageManager.shared.whatsappAuthDirectory.path
        let mediaDir = FileStorageManager.shared.whatsappMediaDirectory.path

        let proc = Process()
        proc.executableURL = npxURL
        proc.arguments = ["tsx", "src/index.ts"]
        proc.currentDirectoryURL = sidecarDir

        var env = ProcessInfo.processInfo.environment
        env["PORT"] = String(Self.port)
        env["AUTH_DIR"] = authDir
        env["MEDIA_DIR"] = mediaDir
        // Ensure node can find npx/tsx in the same bin directory
        if let nodeBin = Self.findNode()?.deletingLastPathComponent().path {
            let existingPath = env["PATH"] ?? "/usr/bin:/bin"
            env["PATH"] = "\(nodeBin):\(existingPath)"
        }
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        outputPipe = pipe

        // Read output asynchronously
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty else { return }
            Log.info(.system, "[WhatsApp Sidecar] \(line)")
        }

        proc.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.isRunning = false
            Log.info(.system, "[WhatsApp] Sidecar exited with code \(proc.terminationStatus)")

            if !self.intentionallyStopped && self.restartCount < self.maxRestartAttempts {
                self.restartCount += 1
                let delay = min(Double(self.restartCount) * 2.0, 30.0)
                Log.info(.system, "[WhatsApp] Restarting sidecar in \(delay)s (attempt \(self.restartCount))")
                self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.startSync()
                }
            }
        }

        do {
            try proc.run()
            process = proc
            isRunning = true
            restartCount = 0
            Log.info(.system, "[WhatsApp] Sidecar started (PID: \(proc.processIdentifier))")
        } catch {
            Log.warn(.system, "[WhatsApp] Failed to start sidecar: \(error)")
        }
    }

    /// Stop the sidecar process.
    func stop() {
        queue.async { [weak self] in
            self?.stopSync()
        }
    }

    private func stopSync() {
        intentionallyStopped = true
        guard let proc = process, proc.isRunning else {
            isRunning = false
            return
        }

        Log.info(.system, "[WhatsApp] Stopping sidecar (PID: \(proc.processIdentifier))...")
        proc.terminate() // SIGTERM

        // Force kill after 5 seconds if still running
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, let p = self.process, p.isRunning else { return }
            Log.warn(.system, "[WhatsApp] Force killing sidecar")
            p.interrupt() // SIGINT
        }

        isRunning = false
        process = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
    }

    /// Restart the sidecar.
    func restart() {
        queue.async { [weak self] in
            self?.stopSync()
            // Small delay to let the process fully exit
            self?.queue.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.startSync()
            }
        }
    }

    // MARK: - Dependency Installation

    private func installDependencies(npxURL: URL, sidecarDir: URL) {
        // Find npm alongside npx
        let npmPath = npxURL.deletingLastPathComponent().appendingPathComponent("npm").path
        guard FileManager.default.isExecutableFile(atPath: npmPath) else {
            Log.warn(.system, "[WhatsApp] npm not found — cannot install sidecar dependencies")
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: npmPath)
        proc.arguments = ["install", "--production"]
        proc.currentDirectoryURL = sidecarDir

        var env = ProcessInfo.processInfo.environment
        if let nodeBin = Self.findNode()?.deletingLastPathComponent().path {
            let existingPath = env["PATH"] ?? "/usr/bin:/bin"
            env["PATH"] = "\(nodeBin):\(existingPath)"
        }
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                Log.info(.system, "[WhatsApp] Dependencies installed successfully")
            } else {
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                Log.warn(.system, "[WhatsApp] npm install failed: \(output)")
            }
        } catch {
            Log.warn(.system, "[WhatsApp] Failed to run npm install: \(error)")
        }
    }

    // MARK: - Status

    var running: Bool { isRunning }
}
