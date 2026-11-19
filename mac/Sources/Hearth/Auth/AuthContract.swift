import Foundation

/// Credentials from the Google Device Access console and Google Cloud console.
struct NestConfig: Codable, Equatable {
    var projectID: String      // Device Access project ID (UUID)
    var clientID: String       // Google Cloud OAuth client ID
    var clientSecret: String   // Google Cloud OAuth client secret

    /// Credentials shipped inside the app bundle as HearthCredentials.plist, if any.
    static let bundled: NestConfig? = {
        guard let url = bundledURL,
              let dict = NSDictionary(contentsOf: url) as? [String: Any],
              let projectID = dict["ProjectID"] as? String, !projectID.isEmpty,
              let clientID = dict["ClientID"] as? String, !clientID.isEmpty,
              let clientSecret = dict["ClientSecret"] as? String, !clientSecret.isEmpty
        else { return nil }
        return NestConfig(projectID: projectID, clientID: clientID, clientSecret: clientSecret)
    }()

    private static var bundledURL: URL? {
        if let url = Bundle.main.url(forResource: "HearthCredentials", withExtension: "plist") { return url }
        #if DEBUG
        // `swift run` builds have no bundle, so read the plist from the source tree.
        // HEARTH_NO_BUNDLED=1 simulates a build without it.
        if ProcessInfo.processInfo.environment["HEARTH_NO_BUNDLED"] == "1" { return nil }
        let mac = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = mac.appendingPathComponent("Resources/HearthCredentials.plist")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
        #else
        return nil
        #endif
    }
}

// MARK: - Validation

extension NestConfig {
    enum Field: CaseIterable {
        case projectID, clientID, clientSecret
    }

    static func isValid(_ value: String, for field: Field) -> Bool {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .projectID:
            return UUID(uuidString: v) != nil
        case .clientID:
            return v.hasSuffix(".apps.googleusercontent.com") && v.count > 30 && !v.contains(" ")
        case .clientSecret:
            return !v.contains(" ") && (v.hasPrefix("GOCSPX-") ? v.count > 12 : v.count >= 20)
        }
    }

    /// Guesses which field a pasted value belongs in.
    static func detect(_ value: String) -> Field? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValid(v, for: .projectID) { return .projectID }
        if isValid(v, for: .clientID) { return .clientID }
        if v.hasPrefix("GOCSPX-"), isValid(v, for: .clientSecret) { return .clientSecret }
        return nil
    }

    /// Reads the client file Google offers for download after creating an OAuth client.
    static func fromClientJSON(_ data: Data) -> (clientID: String, clientSecret: String)? {
        struct File: Decodable {
            struct Client: Decodable { let client_id: String; let client_secret: String? }
            let installed: Client?
            let web: Client?
        }
        guard let file = try? JSONDecoder().decode(File.self, from: data),
              let client = file.installed ?? file.web else { return nil }
        return (client.client_id, client.client_secret ?? "")
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case notConfigured
    case notSignedIn
    case cancelled
    case invalidClient
    case accessDenied
    case redirectMismatch
    case sessionExpired
    case noRefreshToken
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add your Google project details to connect."
        case .notSignedIn:
            return "Sign in with Google to connect your Nest."
        case .cancelled:
            return "Sign-in was cancelled."
        case .invalidClient:
            return "Google didn't accept the Client ID or Secret. Check they match a Desktop app client. A new client can take a few minutes to start working."
        case .accessDenied:
            return "Google denied access. If you didn't cancel, your Google account may need to be added as a test user."
        case .redirectMismatch:
            return "Google rejected the sign-in redirect. The OAuth client must be the Desktop app type."
        case .sessionExpired:
            return "Your Google session ended. Sign in again to reconnect."
        case .noRefreshToken:
            return "Google didn't return a long-lived token. Remove Hearth from your Google account's third-party access and sign in again."
        case .server(let msg):
            return msg
        }
    }

    /// A one-click fix the UI can offer next to the message. Console links only help
    /// people who run their own Google project.
    func recovery(ownProject: Bool) -> (title: String, url: URL)? {
        switch self {
        case .noRefreshToken: return ("Third-Party Access", Links.accountConnections)
        case .invalidClient where ownProject: return ("Open OAuth Clients", Links.clients)
        case .accessDenied where ownProject: return ("Add Test User", Links.audience)
        case .redirectMismatch where ownProject: return ("Open OAuth Clients", Links.clients)
        case .sessionExpired where ownProject: return ("Publish App", Links.audience)
        default: return nil
        }
    }

    /// Maps an OAuth error code from Google to a friendly case.
    init(oauthCode code: String, description: String?) {
        switch code {
        case "invalid_client", "unauthorized_client", "deleted_client": self = .invalidClient
        case "access_denied", "org_internal", "admin_policy_enforced": self = .accessDenied
        case "redirect_uri_mismatch": self = .redirectMismatch
        case "invalid_request" where (description ?? "").contains("redirect"): self = .redirectMismatch
        case "invalid_grant": self = .sessionExpired
        default: self = .server(description ?? "Google returned: \(code)")
        }
    }
}

enum Links {
    static let clients = URL(string: "https://console.cloud.google.com/auth/clients")!
    static let audience = URL(string: "https://console.cloud.google.com/auth/audience")!
    static let accountConnections = URL(string: "https://myaccount.google.com/connections")!
    static let setupGuide = URL(string: "https://hearthbar.app/setup.html")!
}
