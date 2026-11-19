import SwiftUI

extension OpenWindowAction {
    /// Opens the setup window and brings it in front of the browser.
    @MainActor func setup() {
        self(id: SetupWindow.id)
        NSApp.activate()
    }
}

/// Root of the setup window: sign in, the result, or the account view once signed in.
struct SetupWindow: View {
    static let id = "setup"

    @Environment(AuthService.self) private var auth
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var model = OnboardingModel()

    var body: some View {
        Group {
            switch model.mode {
            case .signIn: SignInView(model: model)
            case .done: DoneView(model: model, close: close)
            case .account: AccountView(model: model, close: close)
            }
        }
        // One fixed size for every state. The window doesn't track content height changes.
        .frame(width: 460, height: 500)
        .animation(.snappy, value: model.mode)
        .containerBackground(.thinMaterial, for: .window)
        .onExitCommand(perform: close)
        // Show a Dock icon while this window is open so Cmd-Tab gets back here from the browser.
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            withAnimation(.snappy) {
                if signedIn, model.mode == .signIn { model.mode = .done }
                if !signedIn, model.mode != .signIn { model.mode = .signIn }
            }
        }
    }

    private func close() {
        if model.isSigningIn { model.cancelSignIn() }
        dismissWindow(id: Self.id)
    }
}

// MARK: - Sign in

private struct SignInView: View {
    @Bindable var model: OnboardingModel
    @Environment(AuthService.self) private var auth

    var body: some View {
        VStack(spacing: 18) {
            AppMark(size: 64)
                .padding(.top, 12)

            VStack(spacing: 6) {
                Text("Control your Nest from the menu bar")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.showAdvanced {
                CredentialsForm(model: model)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let error = model.error {
                ErrorCard(error: error, ownProject: !auth.usesBundledConfig)
                    .transition(.opacity)
            }

            if model.isSigningIn {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Finish in your browser").font(.headline)
                    }
                    Button("Cancel", action: model.cancelSignIn)
                        .controlSize(.large)
                        .keyboardShortcut(.cancelAction)
                }
                .frame(minHeight: 52)
            } else {
                Button {
                    Task { await model.signIn() }
                } label: {
                    Text(model.error == nil ? "Sign in with Google" : "Try Again")
                        .frame(minWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSignIn)
                .frame(minHeight: 52)
            }

            if auth.hasBundledConfig && !model.isSigningIn {
                Button(model.showAdvanced ? "Use Hearth's built-in project" : "Use your own Google project",
                       action: model.toggleAdvanced)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .animation(.snappy, value: model.isSigningIn)
        .animation(.snappy, value: model.error?.localizedDescription)
    }

    private var subtitle: String {
        model.showAdvanced
            ? "Enter your Google project details, then sign in."
            : "Your browser opens. Pick your home and thermostat on Google's screen."
    }
}

// MARK: - Done

private struct DoneView: View {
    @Bindable var model: OnboardingModel
    let close: () -> Void
    @Environment(ThermostatStore.self) private var store
    @State private var loaded = false

    private var found: Bool { loaded && !store.thermostats.isEmpty }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: found || !loaded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(found || !loaded ? Color.green : Color.orange)
                .padding(.top, 12)

            VStack(spacing: 6) {
                Text(found ? "You're connected" : (loaded ? "No thermostats shared" : "Connected to Google"))
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !loaded {
                ProgressView().controlSize(.small)
            } else if found {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.thermostats) { ThermostatRow(t: $0) }
                    }
                }
                .frame(maxHeight: 200)
                .fixedSize(horizontal: false, vertical: true)
                Button(action: close) { Text("Done").frame(minWidth: 220) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    loaded = false
                    Task {
                        await model.signIn()
                        await load()
                    }
                } label: {
                    Text("Choose Thermostats").frame(minWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .task { await load() }
    }

    private var subtitle: String {
        if !loaded { return "Looking for your thermostats." }
        if found { return "Click the thermometer in your menu bar to control it." }
        return "On Google's screen, turn on each thermostat you want Hearth to control."
    }

    private func load() async {
        await store.refresh()
        // Another refresh may already be in flight from the menu bar; wait for it.
        while store.isLoading { try? await Task.sleep(for: .milliseconds(200)) }
        withAnimation(.snappy) { loaded = true }
    }
}

struct ThermostatRow: View {
    let t: Thermostat

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background((t.glow ?? Theme.faceEdge).gradient, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(t.name).font(.callout.weight(.medium))
                Text(t.isOnline ? t.statusText : "Offline").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(t.scale.format(t.ambientC))
                .font(.system(.title3, design: .rounded).weight(.medium))
                .monospacedDigit()
        }
        .padding(10)
        .background(Card())
    }
}

// MARK: - Shared pieces

/// The app's mark: a cool to warm gradient tile with a thermometer.
struct AppMark: View {
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: "thermometer.medium")
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [Theme.cool, Theme.heat], startPoint: .bottomLeading, endPoint: .topTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }
}

struct ErrorCard: View {
    let error: AuthError
    var ownProject = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(error.localizedDescription).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .font(.callout)
            if let recovery = error.recovery(ownProject: ownProject) {
                Link(destination: recovery.url) {
                    Label(recovery.title, systemImage: "arrow.up.right.square")
                }
                .font(.callout.weight(.medium))
                .padding(.leading, 26)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.orange.opacity(0.25)))
    }
}

struct Card: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.045))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}
