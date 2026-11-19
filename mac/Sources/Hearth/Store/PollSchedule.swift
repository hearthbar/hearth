import Foundation

/// Decides how long to wait between polls. Pure so it can be tested.
struct PollSchedule {
    static let base: TimeInterval = 60
    static let fast: TimeInterval = 20
    static let maxBackoff: TimeInterval = 600
    static let fastWindow: TimeInterval = 120
    static let staleAfter: TimeInterval = 300

    /// Consecutive polls that failed with a rate limit, server or network error.
    private(set) var failures = 0
    private(set) var fastUntil = Date.distantPast

    func interval(now: Date = Date()) -> TimeInterval {
        if failures > 0 {
            return min(Self.base * pow(2, Double(failures - 1)), Self.maxBackoff)
        }
        return now < fastUntil ? Self.fast : Self.base
    }

    mutating func succeeded() { failures = 0 }

    mutating func failed(backoff: Bool) {
        if backoff { failures = min(failures + 1, 16) }
    }

    /// Polls faster for a while after a command so the real state shows up soon.
    mutating func commandSent(now: Date = Date()) {
        fastUntil = now.addingTimeInterval(Self.fastWindow)
    }

    static func isStale(lastUpdated: Date?, now: Date = Date()) -> Bool {
        guard let lastUpdated else { return false }
        return now.timeIntervalSince(lastUpdated) > staleAfter
    }

    /// Errors worth backing off for: rate limits, Google outages and lost connectivity.
    static func shouldBackOff(_ error: Error) -> Bool {
        if let e = error as? SDMError { return e.isRateLimited || e.isServerError }
        return error is URLError
    }
}
