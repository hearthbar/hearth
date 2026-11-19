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
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 12) {
                        AppMark(size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hearth").font(.title2.weight(.semibold))
                            Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    section("Google") {
                        row("Status") {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        Divider()
                        row("Project") {
                            Text(auth.config?.projectID ?? "--")
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Divider()
                        row("Credentials") {
                            Text(auth.usesBundledConfig ? "Built in" : "Your Google project")
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                        row("Thermostats") {
                            Text(store.thermostats.isEmpty ? "None shared" : store.thermostats.map(\.name).joined(separator: ", "))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    if let error = model.error {
                        ErrorCard(error: error)
                    }

                    HStack(spacing: 8) {
                        Button {
                            Task { await model.signIn() }
                        } label: {
                            Label(model.isSigningIn ? "Waiting for browser" : "Change Thermostat Access",
                                  systemImage: "slider.horizontal.3")
                        }
                        .disabled(model.isSigningIn)
                        Link(destination: Links.accountConnections) {
                            Label("Google Account Access", systemImage: "arrow.up.right.square")
                        }
                        Spacer()
                    }

                    section("General") {
                        row("Open at login") {
                            Toggle("", isOn: $launchAtLogin)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                                .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                        }
                    }
                    if let loginError {
                        Text(loginError).font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 40)
                .padding(.bottom, 20)
            }

            HStack {
                Button("Sign Out", role: .destructive) {
                    auth.signOut()
                    store.reset()
                }
                Button("Use Different Credentials", action: model.changeCredentials)
                Spacer()
                Button("Done", action: close)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(alignment: .top) { Divider() }
        }
        .ignoresSafeArea(edges: .top)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 12)
                .background(Card())
        }
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
