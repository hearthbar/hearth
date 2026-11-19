import AppKit
import CryptoKit
import Foundation
import Observation

@MainActor @Observable
final class AuthService {
    static let shared = AuthService()

    private(set) var config: NestConfig?
    private(set) var isSignedIn: Bool
    private(set) var isSigningIn = false
    /// Why the last sign-in or token refresh failed, for the UI to explain.
    private(set) var lastError: AuthError?

    /// True when running on credentials shipped in the app bundle.
    var usesBundledConfig: Bool { Keychain.config == nil && NestConfig.bundled != nil }
    var hasBundledConfig: Bool { NestConfig.bundled != nil }

    private static let scope = "https://www.googleapis.com/auth/sdm.service"
    private static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

    private var accessTokenValue: String?
    private var accessTokenExpiry: Date = .distantPast
    private var refreshTask: Task<String, Error>?
    private var activeServer: LoopbackServer?

    private init() {
        config = Keychain.config ?? NestConfig.bundled
        isSignedIn = Keychain.refreshToken != nil
    }

    func saveConfig(_ config: NestConfig) {
        let trimmed = NestConfig(
            projectID: config.projectID.trimmingCharacters(in: .whitespacesAndNewlines),
            clientID: config.clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            clientSecret: config.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        // New credentials invalidate any existing session.
        if trimmed != self.config, self.config != nil { signOut() }
        self.config = trimmed
        Keychain.config = trimmed
    }

    /// Forgets the user's own project and goes back to the built-in one.
    func useBuiltInProject() {
        guard let bundled = NestConfig.bundled else { return }
        signOut()
        Keychain.config = nil
        config = bundled
    }

    func signOut() {
        activeServer?.stop()
        activeServer = nil
        refreshTask?.cancel()
        refreshTask = nil
        accessTokenValue = nil
        accessTokenExpiry = .distantPast
        Keychain.refreshToken = nil
        isSignedIn = false
        lastError = nil
    }

    /// Stops waiting for the browser. The pending signIn() throws AuthError.cancelled.
    func cancelSignIn() {
        activeServer?.stop()
    }

    // MARK: Sign in

    func signIn() async throws {
        lastError = nil
        do {
            try await performSignIn()
        } catch AuthError.cancelled {
            throw AuthError.cancelled
        } catch let error as AuthError {
            lastError = error
            throw error
        } catch {
            lastError = .server(error.localizedDescription)
            throw error
        }
    }

    private func performSignIn() async throws {
        guard let config else { throw AuthError.notConfigured }
        activeServer?.stop()
        isSigningIn = true
        defer { isSigningIn = false; activeServer = nil }

        let server = try LoopbackServer()
        activeServer = server
        let port = try await server.start()
        let redirectURI = "http://127.0.0.1:\(port)"

        let verifier = Self.randomURLSafe(bytes: 32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
        let state = Self.randomURLSafe(bytes: 16)

        var components = URLComponents(string: "https://nestservices.google.com/partnerconnections/\(config.projectID)/auth")!
        components.queryItems = [
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
            .init(name: "client_id", value: config.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scope),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = components.url else { throw AuthError.server("Could not build the sign-in URL.") }
        NSWorkspace.shared.open(url)

        let items = try await server.waitForCallback()
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") {
            throw AuthError(oauthCode: error, description: value("error_description"))
        }
        guard value("state") == state else { throw AuthError.server("Sign-in state did not match. Try again.") }
        guard let code = value("code") else { throw AuthError.server("No authorization code was returned.") }

        let response = try await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": config.clientID,
            "client_secret": config.clientSecret,
            "code_verifier": verifier,
        ])
        guard let refresh = response.refresh_token else {
            throw AuthError.noRefreshToken
        }
        Keychain.refreshToken = refresh
        store(response)
        isSignedIn = true
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Access token

    func accessToken() async throws -> String {
        if let token = accessTokenValue, accessTokenExpiry.timeIntervalSinceNow > 60 { return token }
        if let refreshTask { return try await refreshTask.value }

        let task = Task { @MainActor in try await self.refresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func refresh() async throws -> String {
        guard let config else { throw AuthError.notConfigured }
        guard let refresh = Keychain.refreshToken else {
            isSignedIn = false
            throw AuthError.notSignedIn
        }
        do {
            let response = try await tokenRequest([
                "grant_type": "refresh_token",
                "refresh_token": refresh,
                "client_id": config.clientID,
                "client_secret": config.clientSecret,
            ])
            if let rotated = response.refresh_token { Keychain.refreshToken = rotated }
            return store(response)
        } catch TokenError.invalidGrant {
            accessTokenValue = nil
            Keychain.refreshToken = nil
            isSignedIn = false
            lastError = .sessionExpired
            throw AuthError.sessionExpired
        }
    }

    @discardableResult
    private func store(_ response: TokenResponse) -> String {
        accessTokenValue = response.access_token
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(response.expires_in ?? 3600))
        return response.access_token
    }

    // MARK: Token endpoint

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Int?
        let refresh_token: String?
    }

    private struct TokenErrorBody: Decodable {
        let error: String
        let error_description: String?
    }

    private enum TokenError: Error { case invalidGrant }

    private func tokenRequest(_ form: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(form).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if let body = try? JSONDecoder().decode(TokenErrorBody.self, from: data) {
                if body.error == "invalid_grant", form["grant_type"] == "refresh_token" { throw TokenError.invalidGrant }
                if body.error == "invalid_grant" { throw AuthError.server("The sign-in code expired. Try again.") }
                throw AuthError(oauthCode: body.error, description: body.error_description)
            }
            throw AuthError.server("Token request failed (HTTP \(status)).")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: Helpers

    private static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
    }

    private static func randomURLSafe(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64URLEncoded()
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
