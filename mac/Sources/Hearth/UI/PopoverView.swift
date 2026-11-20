import SwiftUI

struct PopoverView: View {
    @Environment(ThermostatStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            if !store.isDemo && (auth.config == nil || !auth.isSignedIn) {
                WelcomeCard()
            } else if let t = store.selected {
                ThermostatView(t: t)
            } else {
                loading
            }
        }
        .frame(width: 320)
        .task { await store.refresh() }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { Task { await store.refresh() } } else { store.reset() }
        }
    }

    private var loading: some View {
        VStack(spacing: 12) {
            if let error = store.error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle).foregroundStyle(.orange)
                Text(error).multilineTextAlignment(.center).font(.callout)
                HStack {
                    Button("Retry") { Task { await store.refresh() } }
                    Button("Settings") { openWindow.setup() }
                }
            } else {
                ProgressView()
                Text("Finding your thermostat").foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

struct ThermostatView: View {
    @Environment(ThermostatStore.self) private var store
    let t: Thermostat
    @Environment(\.openWindow) private var openWindow
    private var theme = ThemeSettings()
    @State private var askingZip = false

    var body: some View {
        // Re-checked each minute so Auto flips at sunrise and sunset while the panel is open.
        TimelineView(.everyMinute) { context in
            content.preferredColorScheme(theme.scheme(at: context.date))
        }
    }

    private var content: some View {
        VStack(spacing: 12) {
            ChannelCard(t: t)
            if theme.mode == .auto && (!theme.hasPlace || askingZip) {
                ZipPrompt(zip: theme.$zip, latitude: theme.$latitude, longitude: theme.$longitude) { askingZip = false }
                    .disabled(false)
            }
            if t.hasFan {
                VStack(spacing: 0) {
                    FanRow(t: t)
                }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            }
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .padding(14)
        .disabled(!t.isOnline)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            status
            Spacer()
            ThemeSwitch(mode: theme.$modeRaw)
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(store.isLoading ? 360 : 0))
                    .animation(store.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                               value: store.isLoading)
            }
            .buttonStyle(IconButtonStyle())
            .help("Refresh")
            Menu {
                Button("Account and Settings") { openWindow.setup() }
                Button(theme.hasPlace ? "Change ZIP Code (\(theme.zip))…" : "Set ZIP Code for Sunrise and Sunset…") {
                    theme.modeRaw = ThemeMode.auto.rawValue
                    askingZip = true
                }
                Divider()
                Button("Quit Hearth") { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .disabled(false)
    }

    /// Online dot plus when the data was last fetched.
    private var status: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(t.isOnline ? (store.isStale ? Color.orange : Color.green) : Color.red)
                .frame(width: 6, height: 6)
            TimelineView(.periodic(from: .now, by: 15)) { _ in
                Text(statusLine)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var statusLine: String {
        guard t.isOnline else { return "Offline" }
        guard let updated = store.lastUpdated else { return "Connecting" }
        let when = updated.formatted(.relative(presentation: .named))
        return store.isStale ? "Last updated \(when)" : "Updated \(when)"
    }
}

// MARK: - Rows

private struct FanRow: View {
    @Environment(ThermostatStore.self) private var store
    let t: Thermostat
    private let durations = [15, 30, 60, 120, 240, 480, 720]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            RowShell(symbol: "fan.fill", tint: .teal, title: "Fan", subtitle: subtitle, spinning: t.fanRunning) {
                if t.fanRunning {
                    Button("Stop") { store.setFan(minutes: nil) }
                        .controlSize(.small)
                } else {
                    Menu("Run") {
                        ForEach(durations, id: \.self) { m in
                            Button(label(m)) { store.setFan(minutes: m) }
                        }
                    }
                    .controlSize(.small)
                    .fixedSize()
                }
            }
        }
    }

    private var subtitle: String {
        guard t.fanRunning, let until = t.fanUntil else { return "Off" }
        return "Running until \(until.formatted(date: .omitted, time: .shortened))"
    }

    private func label(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) minutes" : (minutes == 60 ? "1 hour" : "\(minutes / 60) hours")
    }
}

private struct RowShell<Trailing: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    var spinning = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .symbolEffect(.rotate, isActive: spinning)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

// MARK: - Button styles


struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(.primary.opacity(configuration.isPressed ? 0.12 : 0), in: Circle())
            .contentShape(Circle())
    }
}
