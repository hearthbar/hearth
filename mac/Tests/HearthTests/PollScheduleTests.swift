import Foundation
import Testing
@testable import Hearth

@Suite("Poll schedule")
struct PollScheduleTests {
    @Test func baseInterval() {
        #expect(PollSchedule().interval() == 60)
    }

    @Test func fastAfterCommand() {
        var s = PollSchedule()
        let now = Date()
        s.commandSent(now: now)
        #expect(s.interval(now: now.addingTimeInterval(30)) == 20)
        #expect(s.interval(now: now.addingTimeInterval(121)) == 60)
    }

    @Test func exponentialBackoffCapsAndResets() {
        var s = PollSchedule()
        let expected: [TimeInterval] = [60, 120, 240, 480, 600, 600]
        for value in expected {
            s.failed(backoff: true)
            #expect(s.interval() == value)
        }
        s.succeeded()
        #expect(s.interval() == 60)
    }

    @Test func backoffWinsOverFastPolling() {
        var s = PollSchedule()
        s.commandSent()
        s.failed(backoff: true)
        s.failed(backoff: true)
        #expect(s.interval() == 120)
    }

    @Test func nonRetryableErrorsDontBackOff() {
        var s = PollSchedule()
        s.failed(backoff: false)
        #expect(s.interval() == 60)
    }

    @Test func whichErrorsBackOff() {
        #expect(PollSchedule.shouldBackOff(SDMError(status: 429, data: Data())))
        #expect(PollSchedule.shouldBackOff(SDMError(status: 503, data: Data())))
        #expect(PollSchedule.shouldBackOff(URLError(.notConnectedToInternet)))
        #expect(!PollSchedule.shouldBackOff(SDMError(status: 400, data: Data())))
        #expect(!PollSchedule.shouldBackOff(SDMError(status: 401, data: Data())))
    }

    @Test func staleness() {
        let now = Date()
        #expect(!PollSchedule.isStale(lastUpdated: nil, now: now))
        #expect(!PollSchedule.isStale(lastUpdated: now.addingTimeInterval(-60), now: now))
        #expect(PollSchedule.isStale(lastUpdated: now.addingTimeInterval(-301), now: now))
    }
}
