import SwiftUI

/// Shown in the menu bar panel until Hearth is connected.
struct WelcomeCard: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 14) {
            AppMark(size: 48)
                .padding(.top, 8)
            VStack(spacing: 4) {
                Text("Welcome to Hearth").font(.headline)
                Text(auth.lastError?.localizedDescription ?? "Control your Nest thermostat from the menu bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                // The window shows progress and errors. With no credentials it shows the form.
                openWindow.setup()
                if auth.config != nil, !auth.isSigningIn {
                    Task { try? await auth.signIn() }
                }
            } label: {
                Text(auth.isSigningIn ? "Finish in your browser" : "Sign in with Google").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(auth.isSigningIn)

            Button("Quit Hearth") { NSApp.terminate(nil) }
                .buttonStyle(.link)
                .font(.caption)
        }
        .padding(20)
    }
}
