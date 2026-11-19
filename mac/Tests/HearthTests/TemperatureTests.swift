import Foundation
import Testing
@testable import Hearth

@Suite("Temperature")
struct TemperatureTests {
    let f = TemperatureScale.fahrenheit
    let c = TemperatureScale.celsius

    @Test(arguments: [(0.0, 32.0), (100.0, 212.0), (-40.0, -40.0), (22.2, 71.96)])
    func celsiusToFahrenheit(celsius: Double, fahrenheit: Double) {
        #expect(abs(f.display(celsius) - fahrenheit) < 0.001)
        #expect(abs(f.celsius(fahrenheit) - celsius) < 0.001)
    }

    @Test func celsiusScaleIsIdentity() {
        #expect(c.display(21.3) == 21.3)
        #expect(c.celsius(21.3) == 21.3)
    }

    @Test func snapping() {
        #expect(f.snap(71.6) == 72)
        #expect(f.snap(71.4) == 71)
        #expect(c.snap(21.3) == 21.5)
        #expect(c.snap(21.2) == 21.0)
    }

    @Test func formatting() {
        #expect(f.format(22.2) == "72°")
        #expect(f.format(22.2, unit: true) == "72°F")
        #expect(c.format(21.0) == "21°")
        #expect(c.format(21.3) == "21.5°")
        #expect(c.format(21.3, unit: true) == "21.5°C")
        #expect(f.format(nil) == "--")
    }

    @Test func steps() {
        #expect(f.step == 1)
        #expect(c.step == 0.5)
    }

    @Test func nudgeMovesOneStep() {
        let up = f.nudged(f.celsius(70), by: 1)
        #expect(abs(f.display(up) - 71) < 0.001)
        let down = c.nudged(21.0, by: -1)
        #expect(down == 20.5)
    }

    @Test func nudgeClampsToRange() {
        #expect(abs(f.display(f.nudged(f.celsius(90), by: 1)) - 90) < 0.001)
        #expect(abs(f.display(f.nudged(f.celsius(50), by: -1)) - 50) < 0.001)
        #expect(c.nudged(32, by: 1) == 32)
        #expect(c.nudged(9, by: -1) == 9)
    }

    @Test func autoModeGap() {
        // Heat can't come within 1.5 C of cool, and cool can't come within 1.5 C of heat.
        #expect(SetpointRules.heat(23.5, cool: 24) == 22.5)
        #expect(SetpointRules.heat(20, cool: 24) == 20)
        #expect(SetpointRules.cool(20.5, heat: 20) == 21.5)
        #expect(SetpointRules.cool(25, heat: 20) == 25)
        #expect(SetpointRules.heat(30, cool: nil) == 30)
        #expect(SetpointRules.cool(10, heat: nil) == 10)
    }
}
