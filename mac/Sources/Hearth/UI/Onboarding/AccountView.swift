import ServiceManagement
import SwiftUI

/// Account and settings, shown in the setup window once signed in.
struct AccountView: View {
    @Bindable var model: OnboardingModel
    let close: () -> Void

    @Environment(AuthService.self) private var auth
    @Environment(ThermostatStore.self) private var store
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                AppMark(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hearth").font(.title2.weight(.semibold))
                    Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                row("Google") {
                    Label(auth.usesBundledConfig ? "Connected" : "Connected, your project",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Divider()
                row("Thermostats") {
                    Text(store.thermostats.isEmpty ? "None shared" : store.thermostats.map(\.name).joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Divider()
                row("Open at login") {
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                }
            }
            .padding(.horizontal, 12)
            .background(Card())

            if let error = model.error {
                ErrorCard(error: error, ownProject: !auth.usesBundledConfig)
            }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Button(model.isSigningIn ? "Finish in your browser" : "Change Thermostat Access") {
                    Task { await model.signIn() }
                }
                .disabled(model.isSigningIn)
                if auth.hasBundledConfig {
                    Button(auth.usesBundledConfig ? "Use your own Google project" : "Use Hearth's built-in project",
                           action: model.switchProject)
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }

            Divider()

            HStack {
                Button("Sign Out", role: .destructive) {
                    auth.signOut()
                    store.reset()
                }
                Spacer()
                Button("Done", action: close)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 20)
    }

    private func row<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 16)
            trailing()
        }
        .font(.callout)
        .frame(minHeight: 36)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        loginError = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginError = "Couldn't change the login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
