import Foundation

// MARK: - WhatsApp Models

enum WhatsAppStatus: String, Codable {
    case disconnected
    case connecting
    case waitingForQR = "waiting_for_qr"
    case connected
}

struct WhatsAppHealthResponse: Codable {
    let status: String
    let phoneNumber: String?
    let bufferedMessages: Int?
    let hasQR: Bool?
}

struct WhatsAppQRResponse: Codable {
    let status: String
    let qr: String? // base64 data URL
    let phoneNumber: String?
}

struct WhatsAppMessage: Codable, Identifiable {
    let id: String
    let jid: String
    let sender: String
    let senderName: String
    let text: String
    let timestamp: Double // Unix seconds
    let mediaPath: String?
    let isVoiceNote: Bool
    let isFromMe: Bool
}

struct WhatsAppMessagesResponse: Codable {
    let messages: [WhatsAppMessage]
}

struct WhatsAppSendRequest: Codable {
    let jid: String
    let text: String
}

// MARK: - WhatsAppService

/// Async HTTP client for the WhatsApp sidecar REST API.
final class WhatsAppService: @unchecked Sendable {

    static let shared = WhatsAppService()

    private let baseURL: String
    private let session: URLSession

    init(baseURL: String = WhatsAppSidecar.baseURL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Health

    /// Check current connection status.
    func checkHealth() async -> WhatsAppStatus {
        guard let url = URL(string: "\(baseURL)/health") else { return .disconnected }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .disconnected
            }
            let health = try JSONDecoder().decode(WhatsAppHealthResponse.self, from: data)
            return WhatsAppStatus(rawValue: health.status) ?? .disconnected
        } catch {
            return .disconnected
        }
    }

    // MARK: - QR Code

    /// Get the current QR code as a base64 data URL string, or nil.
    func getQRCode() async -> String? {
        guard let url = URL(string: "\(baseURL)/qr") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let qr = try JSONDecoder().decode(WhatsAppQRResponse.self, from: data)
            return qr.qr
        } catch {
            return nil
        }
    }

    // MARK: - Messages

    /// Poll messages since a Unix timestamp.
    func getMessages(since: TimeInterval) async -> [WhatsAppMessage] {
        guard let url = URL(string: "\(baseURL)/messages?since=\(since)") else { return [] }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let result = try JSONDecoder().decode(WhatsAppMessagesResponse.self, from: data)
            return result.messages
        } catch {
            return []
        }
    }

    // MARK: - Send

    /// Send a text message to a JID.
    func sendMessage(jid: String, text: String) async throws {
        guard let url = URL(string: "\(baseURL)/send") else {
            throw WhatsAppError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(WhatsAppSendRequest(jid: jid, text: text))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WhatsAppError.networkError
        }
        if http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw WhatsAppError.serverError(http.statusCode, body)
        }
    }

    // MARK: - Connect / Disconnect

    /// Initiate connection (starts Baileys socket on sidecar).
    func connect() async throws {
        guard let url = URL(string: "\(baseURL)/connect") else {
            throw WhatsAppError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WhatsAppError.networkError
        }
    }

    /// Disconnect from WhatsApp, optionally clearing saved auth.
    func disconnect(clearAuth: Bool = false) async throws {
        guard let url = URL(string: "\(baseURL)/disconnect") else {
            throw WhatsAppError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["clearAuth": clearAuth])

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WhatsAppError.networkError
        }
    }
}

// MARK: - Errors

enum WhatsAppError: LocalizedError {
    case invalidURL
    case networkError
    case serverError(Int, String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid WhatsApp sidecar URL"
        case .networkError: return "Failed to reach WhatsApp sidecar"
        case .serverError(let code, let msg): return "WhatsApp sidecar error \(code): \(msg)"
        case .notConnected: return "WhatsApp is not connected"
        }
    }
}
