import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class OnboardingModel {
    enum Mode { case signIn, done, account }

    var mode: Mode
    /// Shows the form for the user's own Google project instead of the built-in one.
    var showAdvanced: Bool

    var projectID = ""
    var clientID = ""
    var clientSecret = ""

    var notice: String?
    /// The clipboard changed since the user last looked, so offer to paste.
    var clipboardHasNew = false

    private let auth = AuthService.shared
    private var lastChangeCount = NSPasteboard.general.changeCount

    init() {
        let auth = AuthService.shared
        mode = auth.isSignedIn ? .account : .signIn
        showAdvanced = !auth.usesBundledConfig
        if let c = auth.config, !auth.usesBundledConfig {
            projectID = c.projectID
            clientID = c.clientID
            clientSecret = c.clientSecret
        }

        // Screenshot hook: HEARTH_ONBOARDING_STEP=advanced|done|account.
        switch ProcessInfo.processInfo.environment["HEARTH_ONBOARDING_STEP"] {
        case "advanced":
            showAdvanced = true
            projectID = "3f2a9c1e-7b4d-4e8a-9c21-5d6e8f0a1b2c"
            clientID = "123456789012-example.apps.google"
        case "done": mode = .done
        case "account": mode = .account
        default: break
        }
    }

    var isSigningIn: Bool { auth.isSigningIn }

    /// The last failure worth showing. A cancelled sign-in isn't one.
    var error: AuthError? { auth.lastError }

    var canSignIn: Bool { showAdvanced ? credentialsValid : auth.hasBundledConfig }

    // MARK: Actions

    func signIn() async {
        if showAdvanced {
            auth.saveConfig(NestConfig(projectID: projectID, clientID: clientID, clientSecret: clientSecret))
        } else if !auth.usesBundledConfig {
            auth.useBuiltInProject()
        }
        try? await auth.signIn()
    }

    func cancelSignIn() { auth.cancelSignIn() }

    func toggleAdvanced() {
        withAnimation(.snappy) { showAdvanced.toggle() }
    }

    /// From the account view: sign out and switch to the user's own project, or back.
    func switchProject() {
        if auth.usesBundledConfig {
            auth.signOut()
            showAdvanced = true
        } else {
            auth.useBuiltInProject()
            showAdvanced = false
        }
        withAnimation(.snappy) { mode = .signIn }
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
}
