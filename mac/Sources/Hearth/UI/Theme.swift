import SwiftUI

enum Theme {
    static let heat = Color(red: 1.00, green: 0.45, blue: 0.16)
    static let heatDeep = Color(red: 0.86, green: 0.22, blue: 0.10)
    static let cool = Color(red: 0.20, green: 0.60, blue: 1.00)
    static let coolDeep = Color(red: 0.10, green: 0.32, blue: 0.86)
    static let heatLight = Color(red: 1.00, green: 0.68, blue: 0.48)
    static let coolLight = Color(red: 0.55, green: 0.78, blue: 1.00)
    static let eco = Color(red: 0.30, green: 0.80, blue: 0.45)
    static let face = Color(red: 0.11, green: 0.12, blue: 0.14)
    static let faceEdge = Color(red: 0.20, green: 0.21, blue: 0.24)

    static func accent(for mode: ThermostatMode) -> Color {
        switch mode {
        case .heat: return heat
        case .cool: return cool
        case .heatCool: return Color(red: 0.65, green: 0.45, blue: 0.95)
        case .off: return .secondary
        }
    }
}

extension Thermostat {
    /// The color the dial face glows with.
    var glow: Color? {
        guard isOnline else { return nil }
        switch hvac {
        case .heating: return Theme.heat
        case .cooling: return Theme.cool
        case .off: return nil
        }
    }

    var statusText: String {
        if !isOnline { return "Offline" }
        if ecoOn { return "Eco" }
        switch (hvac, mode) {
        case (.heating, _): return "Heating"
        case (.cooling, _): return "Cooling"
        case (_, .off): return "Off"
        case (_, .heat): return "Heat set to"
        case (_, .cool): return "Cool set to"
        case (_, .heatCool): return "Heat · Cool"
        }
    }
}
