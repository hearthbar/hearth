import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class OnboardingModel {
    enum Mode { case onboarding, account }

    enum Step: Int, CaseIterable, Identifiable {
        case welcome, cloud, deviceAccess, credentials, signIn, done

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .cloud: return "Google Cloud"
            case .deviceAccess: return "Device Access"
            case .credentials: return "Credentials"
            case .signIn: return "Sign In"
            case .done: return "Done"
            }
        }

        var symbol: String {
            switch self {
            case .welcome: return "hand.wave.fill"
            case .cloud: return "cloud.fill"
            case .deviceAccess: return "house.fill"
            case .credentials: return "key.fill"
            case .signIn: return "person.crop.circle.badge.checkmark"
            case .done: return "checkmark.seal.fill"
            }
        }
    }

    var mode: Mode
    var step: Step
    /// Skips the Google setup steps when the app ships with credentials.
    var useBundled: Bool

    var projectID = ""
    var clientID = ""
    var clientSecret = ""

    var error: AuthError?
    var notice: String?
    /// The clipboard changed since the user last looked, so offer to paste.
    var clipboardHasNew = false
    var checkedTasks: Set<String> = []

    private let auth = AuthService.shared
    private var lastChangeCount = NSPasteboard.general.changeCount

    init() {
        let auth = AuthService.shared
        mode = auth.isSignedIn ? .account : .onboarding
        useBundled = auth.usesBundledConfig
        if let c = auth.config, !auth.usesBundledConfig {
            projectID = c.projectID
            clientID = c.clientID
            clientSecret = c.clientSecret
        }
        // Returning users with saved credentials go straight to sign in.
        step = (auth.config != nil) ? .signIn : .welcome
        error = auth.lastError

        // Screenshot hook: HEARTH_ONBOARDING_STEP=<step index> opens a given step.
        let env = ProcessInfo.processInfo.environment
        if env["HEARTH_ONBOARDING_STEP"] == "account" { mode = .account }
        if let raw = env["HEARTH_ONBOARDING_STEP"].flatMap(Int.init), let forced = Step(rawValue: raw) {
            step = forced
            if forced == .credentials {
                projectID = "3f2a9c1e-7b4d-4e8a-9c21-5d6e8f0a1b2c"
                clientID = "123456789012-example.apps.google"
            }
        }
    }

    var steps: [Step] { useBundled ? [.signIn, .done] : Step.allCases }

    var isSigningIn: Bool { auth.isSigningIn }

    // MARK: Navigation

    var canGoBack: Bool {
        guard let i = steps.firstIndex(of: step) else { return false }
        return i > 0 && step != .done && !isSigningIn
    }

    var canContinue: Bool {
        switch step {
        case .credentials: return credentialsValid
        case .signIn, .done: return false
        default: return true
        }
    }

    func next() {
        guard canContinue, let i = steps.firstIndex(of: step), i + 1 < steps.count else { return }
        if step == .credentials { saveCredentials() }
        go(steps[i + 1])
    }

    func back() {
        guard canGoBack, let i = steps.firstIndex(of: step) else { return }
        go(steps[i - 1])
    }

    func go(_ target: Step) {
        error = nil
        withAnimation(.snappy(duration: 0.28)) { step = target }
    }

    func useOwnProject() {
        useBundled = false
        go(.welcome)
    }

    /// Starts over from the credentials step, for a different Google project.
    func changeCredentials() {
        auth.signOut()
        useBundled = false
        mode = .onboarding
        go(.credentials)
    }

    // MARK: Credentials

    func value(_ field: NestConfig.Field) -> String {
        switch field {
        case .projectID: return projectID
        case .clientID: return clientID
        case .clientSecret: return clientSecret
        }
    }

    func set(_ value: String, for field: NestConfig.Field) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .projectID: projectID = v
        case .clientID: clientID = v
        case .clientSecret: clientSecret = v
        }
    }

    func isValid(_ field: NestConfig.Field) -> Bool {
        NestConfig.isValid(value(field), for: field)
    }

    var credentialsValid: Bool { NestConfig.Field.allCases.allSatisfy(isValid) }

    /// Moves a value typed or pasted into the wrong field to the field it belongs in.
    func reroute(_ field: NestConfig.Field) {
        let v = value(field)
        guard let detected = NestConfig.detect(v), detected != field else { return }
        set(v, for: detected)
        set("", for: field)
        notice = "Moved that to \(label(detected))."
    }

    func pasteFromClipboard() {
        clipboardHasNew = false
        lastChangeCount = NSPasteboard.general.changeCount
        guard let text = NSPasteboard.general.string(forType: .string) else {
            notice = "The clipboard is empty."
            return
        }
        if let data = text.data(using: .utf8), applyClientJSON(data) { return }
        if let field = NestConfig.detect(text) {
            set(text, for: field)
            notice = "Pasted \(label(field))."
        } else {
            notice = "That doesn't look like a Project ID, Client ID, or Client Secret."
        }
    }

    func checkClipboard() {
        let count = NSPasteboard.general.changeCount
        if count != lastChangeCount {
            lastChangeCount = count
            clipboardHasNew = true
        }
    }

    func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose the client file you downloaded from Google Cloud."
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importJSON(at: url)
    }

    func importJSON(at url: URL) {
        guard let data = try? Data(contentsOf: url), applyClientJSON(data) else {
            notice = "Couldn't read a Client ID from that file."
            return
        }
    }

    @discardableResult
    private func applyClientJSON(_ data: Data) -> Bool {
        guard let client = NestConfig.fromClientJSON(data) else { return false }
        clientID = client.clientID
        if !client.clientSecret.isEmpty { clientSecret = client.clientSecret }
        notice = "Imported Client ID and Secret."
        return true
    }

    func label(_ field: NestConfig.Field) -> String {
        switch field {
        case .projectID: return "Project ID"
        case .clientID: return "Client ID"
        case .clientSecret: return "Client Secret"
        }
    }

    private func saveCredentials() {
        auth.saveConfig(NestConfig(projectID: projectID, clientID: clientID, clientSecret: clientSecret))
    }

    // MARK: Sign in

    func signIn() async {
        error = nil
        if !useBundled, credentialsValid { saveCredentials() }
        do {
            try await auth.signIn()
            mode = .onboarding
            go(.done)
        } catch AuthError.cancelled {
            error = nil
        } catch let e as AuthError {
            error = e
        } catch {
            self.error = .server(error.localizedDescription)
        }
    }

    func cancelSignIn() {
        auth.cancelSignIn()
    }
}
