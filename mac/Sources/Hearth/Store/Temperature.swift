import Foundation

/// Display helpers. SDM always speaks Celsius; we show whatever the thermostat is set to.
extension TemperatureScale {
    var step: Double { self == .fahrenheit ? 1 : 0.5 }
    var symbol: String { self == .fahrenheit ? "°F" : "°C" }

    /// Nest setpoint limits, in display units.
    var range: ClosedRange<Double> { self == .fahrenheit ? 50...90 : 9...32 }

    /// Minimum gap Nest enforces between heat and cool in Auto mode, in Celsius.
    static let rangeGapC = 1.5

    func display(_ celsius: Double) -> Double {
        self == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
    }

    func celsius(_ display: Double) -> Double {
        self == .fahrenheit ? (display - 32) * 5 / 9 : display
    }

    /// Rounds a display value to the scale's step.
    func snap(_ display: Double) -> Double {
        (display / step).rounded() * step
    }

    func format(_ celsius: Double?, unit: Bool = false) -> String {
        guard let celsius else { return "--" }
        let v = snap(display(celsius))
        let text = self == .fahrenheit || v.rounded() == v
            ? String(format: "%.0f", v)
            : String(format: "%.1f", v)
        return text + (unit ? symbol : "°")
    }

    /// Moves a Celsius setpoint by one display step, staying inside the Nest limits.
    func nudged(_ celsius: Double, by direction: Double) -> Double {
        let d = snap(display(celsius)) + direction * step
        return self.celsius(min(max(d, range.lowerBound), range.upperBound))
    }
}

/// Keeps Auto mode setpoints at least `TemperatureScale.rangeGapC` apart, as Nest requires.
enum SetpointRules {
    static func heat(_ proposedC: Double, cool coolC: Double?) -> Double {
        guard let coolC else { return proposedC }
        return min(proposedC, coolC - TemperatureScale.rangeGapC)
    }

    static func cool(_ proposedC: Double, heat heatC: Double?) -> Double {
        guard let heatC else { return proposedC }
        return max(proposedC, heatC + TemperatureScale.rangeGapC)
    }

    /// Moves the heat point to `proposedC`, pushing the cool point up when they get closer than
    /// the minimum gap. Stays inside `limitsC`, so near the top the heat point stops instead.
    static func pushHeat(_ proposedC: Double, cool coolC: Double?, limitsC: ClosedRange<Double>) -> (heat: Double, cool: Double?) {
        let gap = TemperatureScale.rangeGapC
        let heat = min(max(proposedC, limitsC.lowerBound), limitsC.upperBound - gap)
        guard let coolC else { return (heat, nil) }
        return (heat, max(coolC, heat + gap))
    }

    /// Moves both points by `deltaC`, keeping their distance, as far as `limitsC` allows.
    static func shift(heat heatC: Double, cool coolC: Double, by deltaC: Double,
                      limitsC: ClosedRange<Double>) -> (heat: Double, cool: Double) {
        let d = max(min(deltaC, limitsC.upperBound - coolC), limitsC.lowerBound - heatC)
        return (heatC + d, coolC + d)
    }

    /// Moves the cool point to `proposedC`, pushing the heat point down when they get closer than
    /// the minimum gap. Stays inside `limitsC`, so near the bottom the cool point stops instead.
    static func pushCool(_ proposedC: Double, heat heatC: Double?, limitsC: ClosedRange<Double>) -> (heat: Double?, cool: Double) {
        let gap = TemperatureScale.rangeGapC
        let cool = max(min(proposedC, limitsC.upperBound), limitsC.lowerBound + gap)
        guard let heatC else { return (nil, cool) }
        return (min(heatC, cool - gap), cool)
    }
}
