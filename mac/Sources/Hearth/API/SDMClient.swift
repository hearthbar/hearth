import Foundation
import os

extension Logger {
    static let api = Logger(subsystem: "com.brianhubbell.Hearth", category: "api")
    static let store = Logger(subsystem: "com.brianhubbell.Hearth", category: "store")
}

/// Thin client for the Google Smart Device Management API.
struct SDMClient {
    private static let base = URL(string: "https://smartdevicemanagement.googleapis.com/v1/")!

    let auth: AuthService

    func thermostats(projectID: String) async throws -> [Thermostat] {
        let url = Self.base.appendingPathComponent("enterprises/\(projectID)/devices")
        let data = try await send(URLRequest(url: url))
        let list = try JSONDecoder().decode(SDMDeviceList.self, from: data)
        return (list.devices ?? [])
            .filter { $0.type == "sdm.devices.types.THERMOSTAT" }
            .map(Thermostat.init(device:))
    }

    /// Sends a command, retrying once with jitter if Google returns a 5xx.
    func execute(_ deviceID: String, _ command: String, _ params: [String: Any]) async throws {
        do {
            try await executeOnce(deviceID, command, params)
        } catch let error as SDMError where error.isServerError {
            let delay = Double.random(in: 1.0...2.5)
            Logger.api.notice("\(command, privacy: .public) got \(error.status), retrying in \(delay, format: .fixed(precision: 1))s")
            try await Task.sleep(for: .seconds(delay))
            try await executeOnce(deviceID, command, params)
        }
    }

    private func executeOnce(_ deviceID: String, _ command: String, _ params: [String: Any]) async throws {
        var req = URLRequest(url: Self.base.appendingPathComponent(deviceID + ":executeCommand"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "command": "sdm.devices.commands.\(command)",
            "params": params,
        ])
        _ = try await send(req)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        var req = request
        let token = try await auth.accessToken()
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20

        let label = "\(req.httpMethod ?? "GET") \(req.url?.lastPathComponent ?? "")"
        let started = Date()
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            Logger.api.error("\(label, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        guard (200..<300).contains(status) else {
            let error = SDMError(status: status, data: data)
            Logger.api.error("\(label, privacy: .public) -> \(status) in \(ms)ms: \(error.message, privacy: .public)")
            throw error
        }
        Logger.api.debug("\(label, privacy: .public) -> \(status) in \(ms)ms")
        return data
    }
}

struct SDMError: LocalizedError {
    let status: Int
    let message: String

    init(status: Int, data: Data) {
        self.status = status
        struct Envelope: Decodable { struct E: Decodable { let message: String? }; let error: E? }
        let decoded = (try? JSONDecoder().decode(Envelope.self, from: data))?.error?.message
        message = decoded ?? HTTPURLResponse.localizedString(forStatusCode: status)
    }

    var isServerError: Bool { (500..<600).contains(status) }
    var isRateLimited: Bool { status == 429 }

    var errorDescription: String? {
        switch status {
        case 429: return "Google is rate limiting requests. Try again in a minute."
        case 401, 403: return "Google rejected the request: \(message)"
        default: return message
        }
    }
}
