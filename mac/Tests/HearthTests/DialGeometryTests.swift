import CoreGraphics
import Testing
@testable import Hearth

@Suite("Dial geometry")
struct DialGeometryTests {
    let g = DialGeometry(size: 200, startAngle: 135, sweep: 270, range: 50...90)
    let center = CGPoint(x: 100, y: 100)

    /// A point on a circle around the dial center at the given angle, clockwise from 3 o'clock.
    private func point(_ degrees: Double, radius: Double = 80) -> CGPoint {
        let r = degrees * .pi / 180
        return CGPoint(x: 100 + cos(r) * radius, y: 100 + sin(r) * radius)
    }

    private func near(_ a: Double?, _ b: Double) -> Bool {
        guard let a else { return false }
        return abs(a - b) < 0.0001
    }

    @Test func valueToFraction() {
        #expect(g.fraction(of: 50) == 0)
        #expect(g.fraction(of: 70) == 0.5)
        #expect(g.fraction(of: 90) == 1)
        #expect(g.fraction(of: 30) == 0)
        #expect(g.fraction(of: 120) == 1)
        #expect(g.value(at: 0.25) == 60)
    }

    @Test func fractionToAngle() {
        #expect(g.angle(at: 0) == 135)
        #expect(g.angle(at: 0.5) == 270)
        #expect(g.angle(at: 1) == 405)
    }

    @Test func pointsAlongArc() {
        #expect(near(g.fraction(at: point(135)), 0))      // bottom left, start
        #expect(near(g.fraction(at: point(270)), 0.5))    // top
        #expect(near(g.fraction(at: point(0)), 225.0 / 270))  // 3 o'clock
        #expect(near(g.fraction(at: point(45)), 1))       // bottom right, end
    }

    @Test func deadZoneSnapsToNearestEnd() {
        // The gap at the bottom runs from 45 to 135 degrees; 90 is straight down.
        #expect(near(g.fraction(at: point(60)), 1))
        #expect(near(g.fraction(at: point(120)), 0))
        #expect(near(g.fraction(at: point(89)), 1))
        #expect(near(g.fraction(at: point(91)), 0))
    }

    @Test func centerIsIgnored() {
        #expect(g.fraction(at: center) == nil)
        #expect(g.fraction(at: CGPoint(x: 105, y: 103)) == nil)
        #expect(g.distanceFromCenter(CGPoint(x: 103, y: 104)) == 5)
    }

    @Test func roundTripsThroughAngle() {
        for v in stride(from: 50.0, through: 90.0, by: 5) {
            let f = g.fraction(of: v)
            #expect(near(g.fraction(at: point(g.angle(at: f))), f))
        }
    }
}
