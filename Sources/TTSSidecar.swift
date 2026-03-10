import Foundation

// MARK: - TTSSidecar

/// Manages the Python LuxTTS sidecar process lifecycle.
/// Spawns a FastAPI server (`uvicorn server:app`) from the TTSSidecar directory,
/// monitors its health, and auto-restarts on unexpected exit.
final class TTSSidecar: @unchecked Sendable {

    static let shared = TTSSidecar()

    // MARK: - Configuration

    static let port: Int = 7893
    static let baseURL = "http://127.0.0.1:\(port)"

    // MARK: - State

    private var process: Process?
    private var outputPipe: Pipe?
    private var isRunning = false
    private var restartCount = 0
    private let maxRestartAttempts = 5
    private var intentionallyStopped = false

    private let queue = DispatchQueue(label: "com.autoclawd.tts-sidecar", qos: .utility)

    private init() {}

    // MARK: - Python Discovery

    /// Find a compatible `python3` executable for ML workloads.
    /// Prefers Python 3.11-3.13 over 3.14+ since many ML packages lack 3.14 wheels.
    private static func findPython3() -> URL? {
        // 1. Prefer specific stable versions (3.13 → 3.12 → 3.11) for ML compatibility
        let versionedCandidates = [
            "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13",
            "/opt/homebrew/bin/python3.13",
            "/usr/local/bin/python3.13",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3.12",
            "/opt/homebrew/bin/python3.12",
            "/usr/local/bin/python3.12",
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3.11",
            "/opt/homebrew/bin/python3.11",
            "/usr/local/bin/python3.11",
        ]
        for path in versionedCandidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // 2. Fall back to generic python3 (may be 3.14+, but better than nothing)
        let genericCandidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        for path in genericCandidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // 3. Fall back to `which python3` via login shell
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-l", "-c", "which python3"]
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

    /// Path to the TTSSidecar directory.
    /// Checks: 1) App bundle Resources, 2) Development directory alongside Sources.
    private static func sidecarDirectory() -> URL? {
        // 1. Check inside app bundle
        if let bundlePath = Bundle.main.resourcePath {
            let bundled = URL(fileURLWithPath: bundlePath)
                .appendingPathComponent("TTSSidecar")
            if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("server.py").path) {
                return bundled
            }
        }
        // 2. Check development path (walk up from executable to find TTSSidecar/server.py)
        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        var dir = execURL.deletingLastPathComponent()
        for _ in 0..<5 {
            let candidate = dir.appendingPathComponent("TTSSidecar")
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("server.py").path) {
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
            Log.info(.system, "[TTS] Sidecar already running")
            return
        }

        intentionallyStopped = false

        guard let pythonURL = Self.findPython3() else {
            Log.warn(.system, "[TTS] python3 not found — cannot start TTS sidecar")
            return
        }

        guard let sidecarDir = Self.sidecarDirectory() else {
            Log.warn(.system, "[TTS] TTSSidecar directory not found")
            return
        }

        // Ensure venv and dependencies
        let venvDir = sidecarDir.appendingPathComponent(".venv")
        if !FileManager.default.fileExists(atPath: venvDir.path) {
            Log.info(.system, "[TTS] Creating Python venv...")
            ensureVenv(pythonURL: pythonURL, sidecarDir: sidecarDir)
        }

        // Use the venv python
        let venvPython = venvDir.appendingPathComponent("bin").appendingPathComponent("python3")
        guard FileManager.default.isExecutableFile(atPath: venvPython.path) else {
            Log.warn(.system, "[TTS] venv python3 not found — try deleting .venv and restarting")
            return
        }

        let proc = Process()
        proc.executableURL = venvPython
        proc.arguments = ["-m", "uvicorn", "server:app", "--host", "127.0.0.1", "--port", String(Self.port)]
        proc.currentDirectoryURL = sidecarDir

        var env = ProcessInfo.processInfo.environment
        env["PORT"] = String(Self.port)
        env["VOICES_DIR"] = FileStorageManager.shared.voicesDirectory.path
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
            Log.info(.system, "[TTS Sidecar] \(line)")
        }

        proc.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.isRunning = false
            Log.info(.system, "[TTS] Sidecar exited with code \(proc.terminationStatus)")

            if !self.intentionallyStopped && self.restartCount < self.maxRestartAttempts {
                self.restartCount += 1
                let delay = min(Double(self.restartCount) * 2.0, 30.0)
                Log.info(.system, "[TTS] Restarting sidecar in \(delay)s (attempt \(self.restartCount))")
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
            Log.info(.system, "[TTS] Sidecar started (PID: \(proc.processIdentifier))")
        } catch {
            Log.warn(.system, "[TTS] Failed to start sidecar: \(error)")
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

        Log.info(.system, "[TTS] Stopping sidecar (PID: \(proc.processIdentifier))...")
        proc.terminate() // SIGTERM

        // Force kill after 5 seconds if still running
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, let p = self.process, p.isRunning else { return }
            Log.warn(.system, "[TTS] Force killing sidecar")
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
            self?.queue.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.startSync()
            }
        }
    }

    // MARK: - Venv & Dependency Installation

    private func ensureVenv(pythonURL: URL, sidecarDir: URL) {
        // Create venv
        let venvProc = Process()
        venvProc.executableURL = pythonURL
        venvProc.arguments = ["-m", "venv", ".venv"]
        venvProc.currentDirectoryURL = sidecarDir
        venvProc.standardOutput = Pipe()
        venvProc.standardError = Pipe()

        do {
            try venvProc.run()
            venvProc.waitUntilExit()
            guard venvProc.terminationStatus == 0 else {
                Log.warn(.system, "[TTS] Failed to create venv (exit \(venvProc.terminationStatus))")
                return
            }
            Log.info(.system, "[TTS] venv created")
        } catch {
            Log.warn(.system, "[TTS] Failed to create venv: \(error)")
            return
        }

        let pipPath = sidecarDir
            .appendingPathComponent(".venv")
            .appendingPathComponent("bin")
            .appendingPathComponent("pip3")

        guard FileManager.default.isExecutableFile(atPath: pipPath.path) else {
            Log.warn(.system, "[TTS] pip3 not found in venv")
            return
        }

        // Step 1: Install base dependencies from our requirements.txt
        let reqFile = sidecarDir.appendingPathComponent("requirements.txt")
        let pipProc = Process()
        pipProc.executableURL = pipPath
        pipProc.arguments = ["install", "-r", reqFile.path]
        pipProc.currentDirectoryURL = sidecarDir

        let pipe = Pipe()
        pipProc.standardOutput = pipe
        pipProc.standardError = pipe

        do {
            try pipProc.run()
            pipProc.waitUntilExit()
            if pipProc.terminationStatus == 0 {
                Log.info(.system, "[TTS] Base dependencies installed")
            } else {
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                Log.warn(.system, "[TTS] pip install failed: \(output.prefix(500))")
            }
        } catch {
            Log.warn(.system, "[TTS] Failed to run pip install: \(error)")
        }

        // Step 2: Git clone LuxTTS and install from its requirements.txt
        // (the pyproject.toml references `linacodec` which isn't on PyPI —
        //  the requirements.txt has the correct git URL for LinaCodec)
        let tmpClone = FileManager.default.temporaryDirectory.appendingPathComponent("LuxTTS_clone")
        try? FileManager.default.removeItem(at: tmpClone)

        let gitProc = Process()
        gitProc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        gitProc.arguments = ["clone", "--depth=1", "https://github.com/ysharma3501/LuxTTS.git", tmpClone.path]
        let gitPipe = Pipe()
        gitProc.standardOutput = gitPipe
        gitProc.standardError = gitPipe

        do {
            try gitProc.run()
            gitProc.waitUntilExit()
            guard gitProc.terminationStatus == 0 else {
                let output = String(data: gitPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                Log.warn(.system, "[TTS] git clone LuxTTS failed: \(output.prefix(500))")
                return
            }
            Log.info(.system, "[TTS] LuxTTS cloned")
        } catch {
            Log.warn(.system, "[TTS] Failed to clone LuxTTS: \(error)")
            return
        }

        // Install LuxTTS deps from the cloned requirements.txt (has correct git URLs)
        let luxReqFile = tmpClone.appendingPathComponent("requirements.txt")
        if FileManager.default.fileExists(atPath: luxReqFile.path) {
            let luxReqProc = Process()
            luxReqProc.executableURL = pipPath
            luxReqProc.arguments = ["install", "-r", luxReqFile.path]
            luxReqProc.currentDirectoryURL = sidecarDir
            let luxReqPipe = Pipe()
            luxReqProc.standardOutput = luxReqPipe
            luxReqProc.standardError = luxReqPipe

            do {
                try luxReqProc.run()
                luxReqProc.waitUntilExit()
                if luxReqProc.terminationStatus == 0 {
                    Log.info(.system, "[TTS] LuxTTS requirements installed")
                } else {
                    let output = String(data: luxReqPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    Log.warn(.system, "[TTS] LuxTTS requirements install failed: \(output.prefix(500))")
                }
            } catch {
                Log.warn(.system, "[TTS] Failed to install LuxTTS requirements: \(error)")
            }
        }

        // Install the LuxTTS package itself (--no-deps since deps came from requirements.txt)
        let luxPkgProc = Process()
        luxPkgProc.executableURL = pipPath
        luxPkgProc.arguments = ["install", "--no-deps", tmpClone.path]
        luxPkgProc.currentDirectoryURL = sidecarDir
        let luxPkgPipe = Pipe()
        luxPkgProc.standardOutput = luxPkgPipe
        luxPkgProc.standardError = luxPkgPipe

        do {
            try luxPkgProc.run()
            luxPkgProc.waitUntilExit()
            if luxPkgProc.terminationStatus == 0 {
                Log.info(.system, "[TTS] LuxTTS package installed successfully")
            } else {
                let output = String(data: luxPkgPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                Log.warn(.system, "[TTS] LuxTTS package install failed: \(output.prefix(500))")
            }
        } catch {
            Log.warn(.system, "[TTS] Failed to install LuxTTS package: \(error)")
        }

        // Cleanup clone
        try? FileManager.default.removeItem(at: tmpClone)
    }

    // MARK: - Status

    var running: Bool { isRunning }
}
