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

    private var adjustable: Bool { t.isOnline && !t.ecoOn && t.mode != .off }

    var body: some View {
        VStack(spacing: 14) {
            header
            ZStack {
                DialView(t: t)
                    .opacity(store.isStale ? 0.6 : 1)
                    .saturation(store.isStale ? 0.4 : 1)
                stepper.offset(y: 98)
            }
            .padding(.top, 2)
            stats
            ModeBar(t: t)
            VStack(spacing: 0) {
                if t.ecoAvailable { EcoRow(t: t); Divider().padding(.leading, 44) }
                if t.hasFan { FanRow(t: t) }
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            footer
        }
        .padding(16)
        .disabled(!t.isOnline)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(t.isOnline ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            if store.thermostats.count > 1 {
                Menu {
                    ForEach(store.thermostats) { th in
                        Button(th.name) { store.selectedID = th.id }
                    }
                } label: {
                    Text(t.name).font(.headline)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                Text(t.name).font(.headline)
            }
            Spacer()
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

    private var stepper: some View {
        HStack(spacing: 46) {
            Button { store.nudge(-1) } label: { Image(systemName: "minus") }
                .help("Lower temperature")
                .keyboardShortcut(.downArrow, modifiers: [])
            Button { store.nudge(1) } label: { Image(systemName: "plus") }
                .help("Raise temperature")
                .keyboardShortcut(.upArrow, modifiers: [])
        }
        .buttonStyle(DialButtonStyle())
        .opacity(adjustable ? 1 : 0)
        .disabled(!adjustable)
    }

    private var stats: some View {
        HStack(spacing: 0) {
            Stat(symbol: "thermometer.medium", value: t.scale.format(t.ambientC), label: "Inside")
            Divider().frame(height: 28)
            Stat(symbol: "humidity.fill", value: t.humidity.map { "\(Int($0))%" } ?? "--", label: "Humidity")
            Divider().frame(height: 28)
            Stat(symbol: hvacSymbol, value: hvacText, label: "System", tint: t.glow)
        }
    }

    private var hvacSymbol: String {
        switch t.hvac {
        case .heating: return "flame.fill"
        case .cooling: return "snowflake"
        case .off: return "pause.circle"
        }
    }

    private var hvacText: String {
        switch t.hvac {
        case .heating: return "Heating"
        case .cooling: return "Cooling"
        case .off: return "Idle"
        }
    }

    private var footer: some View {
        HStack {
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            } else if let updated = store.lastUpdated {
                TimelineView(.periodic(from: .now, by: 15)) { _ in
                    Text("\(store.isStale ? "Stale, last updated" : "Updated") \(updated, format: .relative(presentation: .named))")
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.caption)
    }
}

private struct Stat: View {
    let symbol: String
    let value: String
    let label: String
    var tint: Color? = nil

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.caption).foregroundStyle(tint ?? .secondary)
                Text(value).font(.system(.callout, design: .rounded).weight(.semibold)).monospacedDigit()
            }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Mode bar

private struct ModeBar: View {
    @Environment(ThermostatStore.self) private var store
    let t: Thermostat
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(t.availableModes) { mode in
                let selected = t.mode == mode && !t.ecoOn
                Button {
                    store.setMode(mode)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: mode.symbol).font(.system(size: 14, weight: .semibold))
                        Text(mode.title).font(.caption2.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.75))
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Theme.accent(for: mode).gradient)
                                .matchedGeometryEffect(id: "mode", in: ns)
                                .shadow(color: Theme.accent(for: mode).opacity(0.4), radius: 4, y: 2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: t.mode)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: t.ecoOn)
    }
}

// MARK: - Rows

private struct EcoRow: View {
    @Environment(ThermostatStore.self) private var store
    let t: Thermostat

    var body: some View {
        RowShell(symbol: "leaf.fill", tint: Theme.eco, title: "Eco", subtitle: subtitle) {
            Toggle("", isOn: Binding(get: { t.ecoOn }, set: { store.setEco($0) }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.eco)
                .labelsHidden()
        }
    }

    private var subtitle: String {
        let lo = t.ecoHeatC.map { t.scale.format($0) }
        let hi = t.ecoCoolC.map { t.scale.format($0) }
        switch (lo, hi) {
        case let (l?, h?): return "Holds \(l) to \(h)"
        default: return "Saves energy while you're away"
        }
    }
}

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

struct DialButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(.white.opacity(configuration.isPressed ? 0.3 : 0.14), in: Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

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
