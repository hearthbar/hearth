import AppKit
import Foundation
import Network
import Observation
import os

@MainActor @Observable
final class ThermostatStore {
    static let shared = ThermostatStore()

    private(set) var thermostats: [Thermostat] = []
    private(set) var isLoading = false
    private(set) var lastUpdated: Date?
    var error: String?

    /// True when the last good read is older than five minutes.
    var isStale: Bool { PollSchedule.isStale(lastUpdated: lastUpdated) }

    var selectedID: String? {
        didSet { UserDefaults.standard.set(selectedID, forKey: "selectedThermostat") }
    }

    var selected: Thermostat? {
        thermostats.first { $0.id == selectedID } ?? thermostats.first
    }

    private let auth = AuthService.shared
    private var client: SDMClient { SDMClient(auth: auth) }
    private var pollTask: Task<Void, Never>?
    private var setpointTask: Task<Void, Never>?
    private var followUpTask: Task<Void, Never>?
    /// Ignore poll results while a local change is in flight so the UI doesn't jump back.
    private var holdUntil = Date.distantPast
    private var schedule = PollSchedule()
    /// Polling stops while the Mac sleeps or the screen is locked.
    private var isPaused = false
    private var kickTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var lastPathSatisfied = true

    /// Set HEARTH_DEMO=1 to run against sample data with no Google account.
    let isDemo = ProcessInfo.processInfo.environment["HEARTH_DEMO"] == "1"

    private init() {
        selectedID = UserDefaults.standard.string(forKey: "selectedThermostat")
        if isDemo {
            thermostats = Thermostat.samples
            lastUpdated = Date()
        } else {
            observeSystem()
        }
    }

    // MARK: Polling

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.isPaused { await self.refresh() }
                let wait = self.schedule.interval()
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    /// Refreshes soon and restarts the poll loop. Debounced so bursts of events cost one request.
    private func kick(_ reason: String) {
        kickTask?.cancel()
        kickTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, !self.isPaused, self.pollTask != nil else { return }
            Logger.store.info("Refreshing after \(reason, privacy: .public)")
            self.stopPolling()
            self.startPolling()
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        if isDemo { lastUpdated = Date(); return }
        guard let config = auth.config, auth.isSignedIn else { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await client.thermostats(projectID: config.projectID)
            if Date() >= holdUntil { thermostats = fresh }
            lastUpdated = Date()
            schedule.succeeded()
            error = fresh.isEmpty ? "No thermostats found. Re-run sign in and share your thermostat." : nil
        } catch {
            schedule.failed(backoff: PollSchedule.shouldBackOff(error))
            Logger.store.error("Refresh failed, next poll in \(Int(self.schedule.interval()))s: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
        }
    }

    func reset() {
        thermostats = []
        lastUpdated = nil
        error = nil
    }

    // MARK: Commands

    func setMode(_ mode: ThermostatMode) {
        update { $0.mode = mode; if mode != .off { $0.ecoOn = false } }
        // Setting a mode while Eco is on fails, so turn Eco off first.
        let needsEcoOff = selected?.ecoOn == true
        send { id, c in
            if needsEcoOff { try await c.execute(id, "ThermostatEco.SetMode", ["mode": "OFF"]) }
            try await c.execute(id, "ThermostatMode.SetMode", ["mode": mode.rawValue])
        }
    }

    func setEco(_ on: Bool) {
        update { $0.ecoOn = on }
        send { id, c in
            try await c.execute(id, "ThermostatEco.SetMode", ["mode": on ? "MANUAL_ECO" : "OFF"])
        }
    }

    func setFan(minutes: Int?) {
        update { $0.fanUntil = minutes.map { Date().addingTimeInterval(Double($0) * 60) } }
        send { id, c in
            if let minutes {
                try await c.execute(id, "Fan.SetTimer", ["timerMode": "ON", "duration": "\(minutes * 60)s"])
            } else {
                try await c.execute(id, "Fan.SetTimer", ["timerMode": "OFF"])
            }
        }
    }

    /// Updates setpoints locally right away and sends them after the user stops adjusting.
    func setTargets(heatC: Double?, coolC: Double?) {
        guard let t = selected else { return }
        update { $0.heatC = heatC ?? $0.heatC; $0.coolC = coolC ?? $0.coolC }
        holdUntil = Date().addingTimeInterval(8)

        setpointTask?.cancel()
        let mode = t.mode
        setpointTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, let self, let now = self.selected else { return }
            self.send { id, c in
                switch mode {
                case .heat:
                    if let h = now.heatC { try await c.execute(id, "ThermostatTemperatureSetpoint.SetHeat", ["heatCelsius": h]) }
                case .cool:
                    if let cl = now.coolC { try await c.execute(id, "ThermostatTemperatureSetpoint.SetCool", ["coolCelsius": cl]) }
                case .heatCool:
                    if let h = now.heatC, let cl = now.coolC {
                        try await c.execute(id, "ThermostatTemperatureSetpoint.SetRange",
                                            ["heatCelsius": h, "coolCelsius": cl])
                    }
                case .off:
                    break
                }
            }
        }
    }

    /// Nudges the active setpoint(s) by one display step.
    func nudge(_ direction: Double) {
        guard let t = selected else { return }
        func bump(_ c: Double?) -> Double? { c.map { t.scale.nudged($0, by: direction) } }
        switch t.mode {
        case .heat: setTargets(heatC: bump(t.heatC), coolC: nil)
        case .cool: setTargets(heatC: nil, coolC: bump(t.coolC))
        case .heatCool: setTargets(heatC: bump(t.heatC), coolC: bump(t.coolC))
        case .off: break
        }
    }

    // MARK: Plumbing

    private func update(_ change: (inout Thermostat) -> Void) {
        guard let id = selected?.id, let i = thermostats.firstIndex(where: { $0.id == id }) else { return }
        change(&thermostats[i])
        holdUntil = Date().addingTimeInterval(8)
    }

    private func send(_ work: @escaping (String, SDMClient) async throws -> Void) {
        guard let id = selected?.id, !isDemo else { return }
        let client = self.client
        Task {
            do {
                try await work(id, client)
                error = nil
                schedule.commandSent()
            } catch {
                Logger.store.error("Command failed: \(error.localizedDescription, privacy: .public)")
                self.error = error.localizedDescription
                holdUntil = .distantPast
            }
            scheduleFollowUp()
        }
    }

    /// SDM state takes a few seconds to settle after a command; re-read once it has.
    private func scheduleFollowUp() {
        followUpTask?.cancel()
        followUpTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self else { return }
            self.holdUntil = .distantPast
            await self.refresh()
        }
    }

    // MARK: System events

    private func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setPaused(true, reason: "sleep") }
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setPaused(false, reason: "wake") }
        }

        let dist = DistributedNotificationCenter.default()
        dist.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setPaused(true, reason: "screen lock") }
        }
        dist.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setPaused(false, reason: "screen unlock") }
        }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let cameBack = satisfied && !self.lastPathSatisfied
                self.lastPathSatisfied = satisfied
                if cameBack { self.kick("network change") }
            }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor
    }

    private func setPaused(_ paused: Bool, reason: String) {
        guard paused != isPaused else { return }
        isPaused = paused
        Logger.store.info("Polling \(paused ? "paused" : "resumed", privacy: .public) on \(reason, privacy: .public)")
        if !paused { kick(reason) }
    }
}
