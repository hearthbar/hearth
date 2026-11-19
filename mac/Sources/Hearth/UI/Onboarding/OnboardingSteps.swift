import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Shared title block and padding for each step.
private struct StepPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .padding(.horizontal, 28)
        .padding(.top, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Welcome

struct WelcomeStep: View {
    var body: some View {
        StepPage(title: "Control your Nest from the menu bar",
                 subtitle: "Google requires everyone using its Nest API to register once. This walks you through it.") {
            VStack(spacing: 10) {
                Requirement(symbol: "person.crop.circle.fill", tint: .blue,
                            title: "The Google account that owns your thermostat",
                            detail: "The same one you use in the Google Home or Nest app.")
                Requirement(symbol: "creditcard.fill", tint: .green,
                            title: "A one-time $5 fee",
                            detail: "Paid to Google for Device Access. Not a subscription.")
                Requirement(symbol: "clock.fill", tint: .orange,
                            title: "About 15 minutes",
                            detail: "Most of it is clicking through Google's consoles.")
            }
            Label("Hearth never sees your Google password. Tokens stay in your Mac's Keychain.",
                  systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct Requirement: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Card())
    }
}

// MARK: - Google Cloud

struct CloudStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        StepPage(title: "Set up Google Cloud",
                 subtitle: "Create the OAuth client Hearth signs in with. Use any Google Cloud project.") {
            VStack(spacing: 8) {
                TaskRow(model: model, id: "client", number: 1,
                        title: "Create an OAuth client",
                        detail: "Application type: Desktop app. Copy the Client ID and Secret, or download the JSON.",
                        link: Links.createClient)
                TaskRow(model: model, id: "api", number: 2,
                        title: "Enable the Smart Device Management API",
                        detail: "Same project as the client.",
                        link: Links.enableAPI)
                TaskRow(model: model, id: "audience", number: 3,
                        title: "Add yourself as a test user",
                        detail: "Audience page, under Test users. Use the account that owns the thermostat.",
                        link: Links.audience)
            }
            Tip(symbol: "lightbulb.fill",
                text: "On the Audience page, click Publish App. Otherwise Google signs you out every 7 days. Unverified is fine for personal use.")
        }
    }
}

// MARK: - Device Access

struct DeviceAccessStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        StepPage(title: "Create a Device Access project",
                 subtitle: "This links your Google Cloud client to your Nest devices.") {
            VStack(spacing: 8) {
                TaskRow(model: model, id: "register", number: 1,
                        title: "Open the Device Access console",
                        detail: "Accept the terms and pay the $5 fee if asked.",
                        link: Links.deviceAccess)
                TaskRow(model: model, id: "project", number: 2,
                        title: "Create a project",
                        detail: "Paste your OAuth Client ID when asked.")
                TaskRow(model: model, id: "events", number: 3,
                        title: "Leave Events off",
                        detail: "Hearth refreshes on its own. Click Create project.")
                TaskRow(model: model, id: "projectid", number: 4,
                        title: "Copy the Project ID",
                        detail: "It looks like 1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d.")
            }
        }
    }
}

// MARK: - Credentials

struct CredentialsStep: View {
    @Bindable var model: OnboardingModel
    @State private var dropTargeted = false
    private let clipboardTimer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    var body: some View {
        StepPage(title: "Enter your credentials",
                 subtitle: "Paste each value, or drop the client JSON from Google Cloud here.") {
            VStack(spacing: 12) {
                CredentialField(model: model, field: .projectID,
                                placeholder: "1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
                                hint: "A UUID from the Device Access console")
                CredentialField(model: model, field: .clientID,
                                placeholder: "1234-abc.apps.googleusercontent.com",
                                hint: "Ends with .apps.googleusercontent.com")
                CredentialField(model: model, field: .clientSecret, secure: true,
                                placeholder: "GOCSPX-...",
                                hint: "Usually starts with GOCSPX-")
            }

            HStack(spacing: 8) {
                Button {
                    model.pasteFromClipboard()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .overlay(alignment: .topTrailing) {
                    if model.clipboardHasNew {
                        Circle().fill(Color.accentColor).frame(width: 8, height: 8).offset(x: 3, y: -3)
                    }
                }
                Button {
                    model.importJSON()
                } label: {
                    Label("Import JSON", systemImage: "square.and.arrow.down")
                }
                Spacer()
                if let notice = model.notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else if model.clipboardHasNew {
                    Text("New text on your clipboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .animation(.snappy, value: model.notice)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(Label("Drop client JSON", systemImage: "doc.badge.plus").font(.headline))
                    .padding(12)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.importJSON(at: url) }
            }
            return true
        }
        .onReceive(clipboardTimer) { _ in model.checkClipboard() }
        .task(id: model.notice) {
            guard model.notice != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            model.notice = nil
        }
    }
}

private struct CredentialField: View {
    @Bindable var model: OnboardingModel
    let field: NestConfig.Field
    var secure = false
    let placeholder: String
    let hint: String

    @State private var reveal = false

    private var text: Binding<String> {
        Binding(get: { model.value(field) }, set: { model.set($0, for: field) })
    }

    private var value: String { model.value(field) }
    private var valid: Bool { model.isValid(field) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.label(field)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if !value.isEmpty {
                    Label(valid ? "Looks good" : hint,
                          systemImage: valid ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(valid ? Color.green : Color.orange)
                        .labelStyle(.titleAndIcon)
                        .transition(.opacity)
                }
            }
            HStack(spacing: 6) {
                Group {
                    if secure && !reveal {
                        SecureField(placeholder, text: text)
                    } else {
                        TextField(placeholder, text: text)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit { model.reroute(field) }
                .onChange(of: value) { model.reroute(field) }
                if secure {
                    Button {
                        reveal.toggle()
                    } label: {
                        Image(systemName: reveal ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(reveal ? "Hide" : "Show")
                }
            }
        }
        .animation(.snappy, value: valid)
    }
}

// MARK: - Sign in

struct SignInStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 92, height: 92)
                if model.isSigningIn {
                    ProgressView().controlSize(.large)
                } else {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(Color.accentColor)
                        .symbolRenderingMode(.hierarchical)
                }
            }

            VStack(spacing: 6) {
                Text(model.isSigningIn ? "Waiting for you in the browser" : "Sign in with Google")
                    .font(.title2.weight(.semibold))
                Text(model.isSigningIn
                     ? "Pick your account, select your home, and turn on each thermostat. Then come back here."
                     : "Your browser opens. On the Nest screen, turn on each thermostat you want to control.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = model.error {
                ErrorCard(error: error)
                    .frame(maxWidth: 380)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            if model.isSigningIn {
                Button("Cancel", action: model.cancelSignIn)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
            } else {
                Button {
                    Task { await model.signIn() }
                } label: {
                    Label(model.error == nil ? "Sign in with Google" : "Try Again", systemImage: "arrow.up.forward.app")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)
            }

            if model.useBundled && !model.isSigningIn {
                Button("Use my own Google project", action: model.useOwnProject)
                    .buttonStyle(.link)
                    .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy, value: model.isSigningIn)
        .animation(.snappy, value: model.error?.localizedDescription)
    }
}

struct ErrorCard: View {
    let error: AuthError

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(error.localizedDescription).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .font(.callout)
            if let recovery = error.recovery {
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

// MARK: - Done

struct DoneStep: View {
    @Bindable var model: OnboardingModel
    @Environment(ThermostatStore.self) private var store
    @State private var loaded = false

    var body: some View {
        StepPage(title: found ? "You're connected" : (loaded ? "No thermostats yet" : "Connected to Google"),
                 subtitle: subtitle) {
            if !loaded {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Looking for your thermostats").foregroundStyle(.secondary)
                }
            } else if found {
                VStack(spacing: 8) {
                    ForEach(store.thermostats) { t in
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
                Label("Click the thermometer in your menu bar to control it.", systemImage: "menubar.arrow.up.rectangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                if let error = store.error {
                    ErrorCard(error: .server(error))
                }
                Button {
                    loaded = false
                    model.go(.signIn)
                    Task { await model.signIn() }
                } label: {
                    Label("Fix Permissions", systemImage: "slider.horizontal.3")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
        }
        .task { await load() }
    }

    private var found: Bool { loaded && !store.thermostats.isEmpty }

    private var subtitle: String {
        if !loaded { return "Signed in. Checking which devices you shared." }
        if found {
            return store.thermostats.count == 1 ? "Found your thermostat." : "Found \(store.thermostats.count) thermostats."
        }
        return "Google didn't share any thermostats with Hearth. Sign in again and turn on each thermostat on the Nest permissions screen."
    }

    private func load() async {
        await store.refresh()
        // Another refresh may already be in flight from the menu bar; wait for it.
        while store.isLoading { try? await Task.sleep(for: .milliseconds(200)) }
        withAnimation(.snappy) { loaded = true }
    }
}

// MARK: - Shared pieces

private struct TaskRow: View {
    @Bindable var model: OnboardingModel
    let id: String
    let number: Int
    let title: String
    let detail: String
    var link: URL?

    private var done: Bool { model.checkedTasks.contains(id) }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy) {
                    if done { model.checkedTasks.remove(id) } else { model.checkedTasks.insert(id) }
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(done ? Color.clear : Color.secondary.opacity(0.5), lineWidth: 1.5)
                        .background(Circle().fill(done ? Color.green : Color.clear))
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    } else {
                        Text("\(number)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(done ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                    .strikethrough(done, color: .secondary)
                    .foregroundStyle(done ? .secondary : .primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let link {
                Button {
                    NSWorkspace.shared.open(link)
                    withAnimation(.snappy) { _ = model.checkedTasks.insert(id) }
                } label: {
                    Label("Open", systemImage: "arrow.up.right")
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Card())
    }
}

private struct Tip: View {
    let symbol: String
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.yellow)
        }
        .font(.caption)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct Card: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.045))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}
