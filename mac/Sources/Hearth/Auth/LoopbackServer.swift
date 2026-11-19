import Foundation
import Network

/// One-shot HTTP server on 127.0.0.1 that captures the OAuth redirect.
final class LoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.brianhubbell.Hearth.loopback")
    private var continuation: CheckedContinuation<[URLQueryItem], Error>?
    private var finished = false
    private var started = false  // guards the start continuation, touched only on `queue`

    private(set) var port: UInt16 = 0

    init() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params)
    }

    /// Starts listening and returns the bound port.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, !self.started else { return }
                switch state {
                case .ready:
                    self.started = true
                    let port = self.listener.port?.rawValue ?? 0
                    self.port = port
                    cont.resume(returning: port)
                case .failed(let error):
                    self.started = true
                    cont.resume(throwing: error)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            listener.start(queue: queue)
        }
    }

    /// Waits for the redirect request and returns its query items.
    func waitForCallback(timeout: TimeInterval = 300) async throws -> [URLQueryItem] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                queue.async {
                    if self.finished { cont.resume(throwing: AuthError.cancelled); return }
                    self.continuation = cont
                    self.queue.asyncAfter(deadline: .now() + timeout) {
                        self.finish(.failure(AuthError.server("Sign-in timed out. Try again.")))
                    }
                }
            }
        } onCancel: {
            self.queue.async { self.finish(.failure(AuthError.cancelled)) }
        }
    }

    func stop() {
        queue.async { self.finish(.failure(AuthError.cancelled)) }
    }

    // Must be called on `queue`.
    private func finish(_ result: Result<[URLQueryItem], Error>) {
        guard !finished else { return }
        finished = true
        listener.cancel()
        continuation?.resume(with: result)
        continuation = nil
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self else { conn.cancel(); return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let requestLine = request.split(separator: "\r\n").first.map(String.init) ?? ""
            let parts = requestLine.split(separator: " ")
            let target = parts.count >= 2 ? String(parts[1]) : "/"

            // Browsers often ask for a favicon; ignore anything that is not the callback.
            let components = URLComponents(string: "http://127.0.0.1\(target)")
            let items = components?.queryItems ?? []
            let isCallback = items.contains { $0.name == "code" || $0.name == "error" }

            guard isCallback, !self.finished else {
                self.respond(conn, status: "404 Not Found", body: "")
                return
            }

            let failed = items.contains { $0.name == "error" }
            self.respond(conn, status: "200 OK", body: Self.page(success: !failed))
            self.finish(.success(items))
        }
    }

    private func respond(_ conn: NWConnection, status: String, body: String) {
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(header.utf8) + bodyData, completion: .contentProcessed { _ in conn.cancel() })
    }

    private static func page(success: Bool) -> String {
        let title = success ? "Connected." : "Sign-in failed."
        let detail = success ? "You can close this tab and return to Hearth." : "Close this tab and try again from Hearth."
        let accent = success ? "#34c759" : "#ff453a"
        let mark = success ? "&#10003;" : "&#33;"
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Hearth</title>
        <style>
        :root{color-scheme:light dark;--bg:#f5f5f7;--card:#fff;--fg:#1d1d1f;--muted:#6e6e73}
        @media (prefers-color-scheme:dark){:root{--bg:#000;--card:#1c1c1e;--fg:#f5f5f7;--muted:#98989d}}
        body{margin:0;min-height:100vh;display:grid;place-items:center;background:var(--bg);color:var(--fg);
        font:16px/1.5 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif}
        .card{background:var(--card);padding:40px 48px;border-radius:20px;text-align:center;
        box-shadow:0 10px 40px rgba(0,0,0,.12);max-width:360px}
        .mark{width:56px;height:56px;border-radius:50%;margin:0 auto 16px;display:grid;place-items:center;
        background:\(accent);color:#fff;font-size:28px;font-weight:700}
        h1{font-size:22px;margin:0 0 6px}p{margin:0;color:var(--muted)}
        </style></head><body><div class="card"><div class="mark">\(mark)</div>
        <h1>\(title)</h1><p>\(detail)</p></div></body></html>
        """
    }
}
