import Foundation
import Testing
@testable import Hearth

@Suite("Channel")
struct ChannelGeometryTests {
    let g = ChannelGeometry(visible: 60...84)

    @Test func warmerIsHigher() {
        #expect(g.y(84) == ChannelGeometry.top)
        #expect(g.y(60) == ChannelGeometry.bottom)
        #expect(g.y(72) < g.y(68))
    }

    @Test func valueRoundTrips() {
        for v in [60.0, 66, 71, 79, 84] { #expect(abs(g.value(atY: g.y(v)) - v) < 0.0001) }
        #expect(g.value(atY: -500) == 84)
    }

    @Test func bendSitsBetweenTheSetpoints() {
        #expect(ChannelGeometry.bend(heat: 68, cool: 76, gap: 3) == 68...76)
        #expect(ChannelGeometry.bend(heat: 68, cool: nil, gap: 3) == 68...71)
        #expect(ChannelGeometry.bend(heat: nil, cool: 76, gap: 3) == 73...76)
        #expect(ChannelGeometry.bend(heat: nil, cool: nil, gap: 3) == nil)
    }

    @Test func channelRunsHeatLaneBelowAndCoolLaneAbove() {
        let bend = 68.0...76.0
        #expect(g.center(atY: g.y(64), bend: bend) == ChannelGeometry.heatLane)
        #expect(g.center(atY: g.y(80), bend: bend) == ChannelGeometry.coolLane)
        let mid = g.center(atY: g.y(72), bend: bend)
        #expect(abs(mid - (ChannelGeometry.heatLane + ChannelGeometry.coolLane) / 2) < 0.5)
    }
}

@Suite("Sun times")
struct SunTimesTests {
    var newYork: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }

    private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    @Test func midsummerInNewYork() {
        // Published: sunrise 5:25 AM EDT (09:25 UTC), sunset 8:31 PM EDT (00:31 UTC next day).
        let t = SunTimes.times(on: date("2026-06-21T16:00:00Z"), latitude: 40.7128, longitude: -74.006, calendar: newYork)!
        #expect(abs(t.rise.timeIntervalSince(date("2026-06-21T09:25:00Z"))) < 300)
        #expect(abs(t.set.timeIntervalSince(date("2026-06-22T00:31:00Z"))) < 300)
    }

    @Test func midwinterInNewYork() {
        // Published: sunrise 7:17 AM EST (12:17 UTC), sunset 4:32 PM EST (21:32 UTC).
        let t = SunTimes.times(on: date("2026-12-21T17:00:00Z"), latitude: 40.7128, longitude: -74.006, calendar: newYork)!
        #expect(abs(t.rise.timeIntervalSince(date("2026-12-21T12:17:00Z"))) < 300)
        #expect(abs(t.set.timeIntervalSince(date("2026-12-21T21:32:00Z"))) < 300)
    }

    @Test func nightAndDay() {
        #expect(SunTimes.isNight(at: date("2026-06-21T06:00:00Z"), latitude: 40.7128, longitude: -74.006, calendar: newYork))
        #expect(!SunTimes.isNight(at: date("2026-06-21T16:00:00Z"), latitude: 40.7128, longitude: -74.006, calendar: newYork))
        #expect(SunTimes.isNight(at: date("2026-06-22T02:00:00Z"), latitude: 40.7128, longitude: -74.006, calendar: newYork))
    }

    @Test func polarDayHasNoSunset() {
        #expect(SunTimes.times(on: date("2026-06-21T12:00:00Z"), latitude: 78.2, longitude: 15.6) == nil)
    }
}
