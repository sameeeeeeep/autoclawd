import AppKit
import Foundation

// MARK: - Step Status

enum StepStatus: Equatable {
    case pending
    case running(progress: Double?)   // nil = indeterminate spinner
    case done
    case failed(String)

    static func == (lhs: StepStatus, rhs: StepStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending),
             (.done, .done):                      return true
        case (.running(let a), .running(let b)):  return a == b
        case (.failed(let a), .failed(let b)):    return a == b
        default:                                  return false
        }
    }
}

// MARK: - DependencyInstaller

@MainActor
final class DependencyInstaller: ObservableObject {
    static let shared = DependencyInstaller()

    @Published var ollamaStatus:       StepStatus = .pending
    @Published var modelStatus:        StepStatus = .pending
    @Published var groqStatus:         StepStatus = .pending
    @Published var accessStatus:       StepStatus = .pending
    @Published var modelProgress:      Double     = 0
    @Published var modelProgressText:  String     = ""
    @Published var isComplete:         Bool       = false

    private let ollamaDownloadURL = URL(string: "https://ollama.com/download/Ollama-darwin.zip")!
    let modelName = "llama3.2"

    private init() {}

    // MARK: - Check All (called on setup view appear)

    func checkAll() async {
        await checkOllama()
        await checkModel()
        await checkGroqKey()
        checkAccessibility()
        refreshCompletion()
    }

    func checkOllama() async {
        if await OllamaService().isAvailable() {
            ollamaStatus = .done
        }
    }

    func checkModel() async {
        if await isModelAvailable(modelName) {
            modelStatus = .done
        }
    }

    func checkGroqKey() async {
        let key = SettingsManager.shared.groqAPIKey
        guard !key.isEmpty else { return }
        if await TranscriptionService.validateAPIKey(key) {
            groqStatus = .done
        }
    }

    func checkAccessibility() {
        if AXIsProcessTrusted() { accessStatus = .done }
    }

    // MARK: - Install Ollama

    func installOllama() async {
        ollamaStatus = .running(progress: nil)

        // Already running?
        if await OllamaService().isAvailable() {
            ollamaStatus = .done
            refreshCompletion()
            return
        }

        // Already installed as app?
        let appURLs: [URL] = [
            URL(fileURLWithPath: "/Applications/Ollama.app"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Ollama.app")
        ]
        if let existing = appURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.open(existing)
            await waitForOllama()
            return
        }

        // Download + install
        do {
            try await downloadAndInstallOllama()
            await waitForOllama()
        } catch {
            ollamaStatus = .failed(error.localizedDescription)
        }
        refreshCompletion()
    }

    // MARK: - Pull Model

    func pullModel() async {
        guard case .done = ollamaStatus else {
            modelStatus = .failed("Install Ollama first")
            return
        }
        modelStatus    = .running(progress: 0)
        modelProgress  = 0
        modelProgressText = "Starting download…"
        do {
            try await pullModelWithProgress(modelName)
            modelStatus = .done
        } catch {
            modelStatus = .failed(error.localizedDescription)
        }
        refreshCompletion()
    }

    // MARK: - Groq Key

    /// Returns true if valid.
    func validateAndSaveGroqKey(_ key: String) async -> Bool {
        groqStatus = .running(progress: nil)
        let valid = await TranscriptionService.validateAPIKey(key)
        if valid {
            SettingsManager.shared.groqAPIKey = key
            groqStatus = .done
        } else {
            groqStatus = .failed("Invalid key — get a free key at console.groq.com")
        }
        refreshCompletion()
        return valid
    }

    // MARK: - Accessibility

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        Task {
            // Poll until granted or 10s timeout
            for _ in 0..<10 {
                try? await Task.sleep(for: .seconds(1))
                if AXIsProcessTrusted() {
                    accessStatus = .done
                    refreshCompletion()
                    // Re-register global monitors now that permission is granted
                    GlobalHotkeyMonitor.shared.stop()
                    GlobalHotkeyMonitor.shared.start()
                    return
                }
            }
        }
    }

    // MARK: - Private: Download + Install Ollama

    private func downloadAndInstallOllama() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollama-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let zipPath = tmp.appendingPathComponent("Ollama-darwin.zip")
        let (data, _) = try await URLSession.shared.data(from: ollamaDownloadURL)
        try data.write(to: zipPath)

        // Unzip
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", zipPath.path, "-d", tmp.path]
        try unzip.run()
        unzip.waitUntilExit()

        // Find the .app
        let candidates = try FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)
        guard let appSrc = candidates.first(where: { $0.pathExtension == "app" }) else {
            throw InstallError.ollamaAppNotFound
        }

        // Try /Applications first, then ~/Applications
        let destinations: [URL] = [
            URL(fileURLWithPath: "/Applications").appendingPathComponent(appSrc.lastPathComponent),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications")
                .appendingPathComponent(appSrc.lastPathComponent)
        ]

        var installed: URL?
        for dest in destinations {
            do {
                try FileManager.default.createDirectory(
                    at: dest.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: appSrc, to: dest)
                installed = dest
                break
            } catch {
                continue
            }
        }

        guard let dest = installed else {
            throw InstallError.installFailed("Could not copy Ollama.app to Applications")
        }

        // Launch — Ollama.app installs its CLI on first run and starts the daemon
        NSWorkspace.shared.open(dest)
    }

    // MARK: - Private: Wait for Ollama Daemon

    private func waitForOllama() async {
        for i in 0..<30 {
            let progress = Double(i) / 30.0
            ollamaStatus = .running(progress: progress)
            try? await Task.sleep(for: .seconds(2))
            if await OllamaService().isAvailable() {
                ollamaStatus = .done
                return
            }
        }
        ollamaStatus = .failed("Ollama didn't start — try opening Ollama.app manually")
    }

    // MARK: - Private: Check Model Available

    func isModelAvailable(_ name: String) async -> Bool {
        guard let url = URL(string: "http://localhost:11434/api/tags") else { return false }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return false }
        return models.contains { ($0["name"] as? String)?.hasPrefix(name) == true }
    }

    // MARK: - Private: Pull via Ollama Streaming API

    private func pullModelWithProgress(_ name: String) async throws {
        guard let url = URL(string: "http://localhost:11434/api/pull") else {
            throw InstallError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "stream": true])

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw InstallError.pullFailed("HTTP error from Ollama")
        }

        for try await line in asyncBytes.lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if let error = json["error"] as? String {
                throw InstallError.pullFailed(error)
            }

            let status    = json["status"] as? String ?? ""
            let completed = json["completed"] as? Double ?? 0
            let total     = json["total"] as? Double ?? 0
            let progress  = total > 0 ? completed / total : nil

            modelProgressText = status
            if let p = progress {
                modelProgress  = p
                modelStatus    = .running(progress: p)
            } else {
                modelStatus = .running(progress: nil)
            }
        }
    }

    // MARK: - Completion

    func refreshCompletion() {
        let coreSteps: [StepStatus] = [ollamaStatus, modelStatus, groqStatus]
        isComplete = coreSteps.allSatisfy { if case .done = $0 { return true } else { return false } }
    }
}

// MARK: - Errors

private enum InstallError: LocalizedError {
    case ollamaAppNotFound
    case invalidURL
    case installFailed(String)
    case pullFailed(String)

    var errorDescription: String? {
        switch self {
        case .ollamaAppNotFound:      return "Ollama.app not found in downloaded archive"
        case .invalidURL:             return "Invalid Ollama API URL"
        case .installFailed(let m):   return "Install failed: \(m)"
        case .pullFailed(let m):      return "Model pull failed: \(m)"
        }
    }
}
