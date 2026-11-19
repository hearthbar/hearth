import SwiftUI

extension OpenWindowAction {
    /// Opens the setup window and brings it in front of the browser.
    @MainActor func setup() {
        self(id: SetupWindow.id)
        NSApp.activate()
    }
}

/// Root of the setup window: onboarding steps, or the account pane once signed in.
struct SetupWindow: View {
    static let id = "setup"

    @Environment(AuthService.self) private var auth
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var model = OnboardingModel()

    var body: some View {
        Group {
            switch model.mode {
            case .account: AccountView(model: model, close: close)
            case .onboarding: OnboardingView(model: model, close: close)
            }
        }
        .frame(width: 600, height: 500)
        .containerBackground(.thinMaterial, for: .window)
        .onExitCommand(perform: close)
        // Show a Dock icon while this window is open so Cmd-Tab gets back here from the browser.
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if !signedIn, model.mode == .account { model.mode = .onboarding; model.go(.signIn) }
        }
    }

    private func close() {
        if model.isSigningIn { model.cancelSignIn() }
        dismissWindow(id: Self.id)
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    let close: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                ZStack {
                    content
                        .id(model.step)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                footer
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                AppMark(size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Hearth").font(.headline)
                    Text("Setup").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 44)
            .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(model.steps) { step in
                    StepRow(step: step, state: state(of: step))
                }
            }
            Spacer()
            if !model.useBundled {
                Label("About 15 minutes", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 18)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 180)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.035))
    }

    private func state(of step: Step) -> StepRow.State {
        guard let current = model.steps.firstIndex(of: model.step),
              let i = model.steps.firstIndex(of: step) else { return .upcoming }
        if i < current || model.step == .done { return .complete }
        return i == current ? .current : .upcoming
    }

    typealias Step = OnboardingModel.Step

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .welcome: WelcomeStep()
        case .cloud: CloudStep(model: model)
        case .deviceAccess: DeviceAccessStep(model: model)
        case .credentials: CredentialsStep(model: model)
        case .signIn: SignInStep(model: model)
        case .done: DoneStep(model: model)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if model.canGoBack {
                Button("Back", action: model.back)
                    .keyboardShortcut(.leftArrow, modifiers: .command)
            }
            Spacer()
            switch model.step {
            case .done:
                Button("Finish", action: close)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .signIn:
                EmptyView()
            default:
                Button("Continue", action: model.next)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canContinue)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(minHeight: 64)
        .background(alignment: .top) { Divider() }
    }
}

private struct StepRow: View {
    enum State { case complete, current, upcoming }
    let step: OnboardingModel.Step
    let state: State

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(state == .upcoming ? Color.primary.opacity(0.08) : Color.accentColor)
                    .frame(width: 22, height: 22)
                Image(systemName: state == .complete ? "checkmark" : step.symbol)
                    .font(.system(size: state == .complete ? 10 : 10, weight: .bold))
                    .foregroundStyle(state == .upcoming ? Color.secondary : Color.white)
            }
            Text(step.title)
                .font(.callout.weight(state == .current ? .semibold : .regular))
                .foregroundStyle(state == .upcoming ? .secondary : .primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            if state == .current {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07))
            }
        }
        .animation(.snappy, value: state)
    }
}

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
