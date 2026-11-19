import SwiftUI

/// Shown in the menu bar panel until Hearth is connected. Setup itself runs in its own window.
struct WelcomeCard: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.openWindow) private var openWindow

    private var returning: Bool { auth.config != nil }

    var body: some View {
        VStack(spacing: 14) {
            AppMark(size: 48)
                .padding(.top, 8)
            VStack(spacing: 4) {
                Text(returning ? "Sign in to Hearth" : "Welcome to Hearth").font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                openWindow.setup()
            } label: {
                Text(returning ? "Sign In" : "Set Up Hearth").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Button("Quit Hearth") { NSApp.terminate(nil) }
                .buttonStyle(.link)
                .font(.caption)
        }
        .padding(20)
    }

    private var message: String {
        if let error = auth.lastError { return error.localizedDescription }
        return returning
            ? "Your Google session ended. Sign in again to reconnect your thermostat."
            : "Control your Nest thermostat from the menu bar. Setup takes about 15 minutes."
    }
}
