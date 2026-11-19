import SwiftUI

@main
struct HearthApp: App {
    @State private var store = ThermostatStore.shared
    @State private var auth = AuthService.shared

    /// First run opens setup on its own. HEARTH_ONBOARDING=1 forces it, for screenshots.
    private var showSetupAtLaunch: Bool {
        if ProcessInfo.processInfo.environment["HEARTH_ONBOARDING"] == "1" { return true }
        return !store.isDemo && !auth.isSignedIn
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(store)
                .environment(auth)
        } label: {
            MenuBarLabel(thermostat: store.selected)
                .task { store.startPolling() }
        }
        .menuBarExtraStyle(.window)

        Window("Hearth", id: SetupWindow.id) {
            SetupWindow()
                .environment(store)
                .environment(auth)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(showSetupAtLaunch ? .presented : .suppressed)

        // Only shown in demo mode, so the panel can be viewed and captured as a window.
        Window("Hearth Demo", id: "demo") {
            PopoverView()
                .environment(store)
                .environment(auth)
                .background(.regularMaterial)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(store.isDemo ? .presented : .suppressed)
    }
}

struct MenuBarLabel: View {
    let thermostat: Thermostat?

    var body: some View {
        if let t = thermostat {
            HStack(spacing: 3) {
                Image(systemName: symbol(for: t))
                Text(t.scale.format(t.ambientC))
                    .monospacedDigit()
            }
        } else {
            Image(systemName: "thermometer.medium")
        }
    }

    private func symbol(for t: Thermostat) -> String {
        if !t.isOnline { return "thermometer.medium.slash" }
        switch t.hvac {
        case .heating: return "flame.fill"
        case .cooling: return "snowflake"
        case .off: return t.ecoOn ? "leaf.fill" : "thermometer.medium"
        }
    }
}
