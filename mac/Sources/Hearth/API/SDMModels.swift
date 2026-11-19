import Foundation

// MARK: - Raw SDM payloads

struct SDMDeviceList: Decodable {
    let devices: [SDMDevice]?
}

struct SDMDevice: Decodable {
    let name: String
    let type: String
    let traits: SDMTraits
    let parentRelations: [ParentRelation]?

    struct ParentRelation: Decodable {
        let parent: String
        let displayName: String?
    }
}

struct SDMTraits: Decodable {
    var info: Info?
    var humidity: Humidity?
    var connectivity: Connectivity?
    var fan: Fan?
    var mode: Mode?
    var eco: Eco?
    var hvac: Hvac?
    var settings: Settings?
    var setpoint: Setpoint?
    var temperature: Temperature?

    enum CodingKeys: String, CodingKey {
        case info = "sdm.devices.traits.Info"
        case humidity = "sdm.devices.traits.Humidity"
        case connectivity = "sdm.devices.traits.Connectivity"
        case fan = "sdm.devices.traits.Fan"
        case mode = "sdm.devices.traits.ThermostatMode"
        case eco = "sdm.devices.traits.ThermostatEco"
        case hvac = "sdm.devices.traits.ThermostatHvac"
        case settings = "sdm.devices.traits.Settings"
        case setpoint = "sdm.devices.traits.ThermostatTemperatureSetpoint"
        case temperature = "sdm.devices.traits.Temperature"
    }

    struct Info: Decodable { let customName: String? }
    struct Humidity: Decodable { let ambientHumidityPercent: Double? }
    struct Connectivity: Decodable { let status: String? }
    struct Fan: Decodable { let timerMode: String?; let timerTimeout: String? }
    struct Mode: Decodable { let availableModes: [String]?; let mode: String? }
    struct Eco: Decodable {
        let availableModes: [String]?
        let mode: String?
        let heatCelsius: Double?
        let coolCelsius: Double?
    }
    struct Hvac: Decodable { let status: String? }
    struct Settings: Decodable { let temperatureScale: String? }
    struct Setpoint: Decodable { let heatCelsius: Double?; let coolCelsius: Double? }
    struct Temperature: Decodable { let ambientTemperatureCelsius: Double? }
}

// MARK: - App model

enum ThermostatMode: String, CaseIterable, Identifiable {
    case heat = "HEAT"
    case cool = "COOL"
    case heatCool = "HEATCOOL"
    case off = "OFF"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heat: return "Heat"
        case .cool: return "Cool"
        case .heatCool: return "Auto"
        case .off: return "Off"
        }
    }

    var symbol: String {
        switch self {
        case .heat: return "flame.fill"
        case .cool: return "snowflake"
        case .heatCool: return "arrow.up.arrow.down"
        case .off: return "power"
        }
    }
}

enum HvacStatus: String {
    case heating = "HEATING"
    case cooling = "COOLING"
    case off = "OFF"
}

enum TemperatureScale: String {
    case celsius = "CELSIUS"
    case fahrenheit = "FAHRENHEIT"
}

struct Thermostat: Identifiable, Equatable {
    let id: String              // full resource name: enterprises/.../devices/...
    var name: String
    var isOnline: Bool
    var ambientC: Double?
    var humidity: Double?
    var mode: ThermostatMode
    var availableModes: [ThermostatMode]
    var ecoOn: Bool
    var ecoAvailable: Bool
    var ecoHeatC: Double?
    var ecoCoolC: Double?
    var hvac: HvacStatus
    var scale: TemperatureScale
    var heatC: Double?
    var coolC: Double?
    var hasFan: Bool
    var fanUntil: Date?

    var fanRunning: Bool {
        guard let fanUntil else { return false }
        return fanUntil > Date()
    }

    init(device: SDMDevice) {
        let t = device.traits
        id = device.name
        let custom = t.info?.customName?.trimmingCharacters(in: .whitespaces) ?? ""
        let room = device.parentRelations?.first?.displayName ?? ""
        name = !custom.isEmpty ? custom : (!room.isEmpty ? room : "Thermostat")
        isOnline = (t.connectivity?.status ?? "ONLINE") == "ONLINE"
        ambientC = t.temperature?.ambientTemperatureCelsius
        humidity = t.humidity?.ambientHumidityPercent
        mode = ThermostatMode(rawValue: t.mode?.mode ?? "OFF") ?? .off
        let modes = (t.mode?.availableModes ?? []).compactMap(ThermostatMode.init(rawValue:))
        availableModes = ThermostatMode.allCases.filter { modes.isEmpty || modes.contains($0) }
        ecoOn = t.eco?.mode == "MANUAL_ECO"
        ecoAvailable = t.eco?.availableModes?.contains("MANUAL_ECO") ?? false
        ecoHeatC = t.eco?.heatCelsius
        ecoCoolC = t.eco?.coolCelsius
        hvac = HvacStatus(rawValue: t.hvac?.status ?? "OFF") ?? .off
        scale = TemperatureScale(rawValue: t.settings?.temperatureScale ?? "") ?? .fahrenheit
        heatC = t.setpoint?.heatCelsius
        coolC = t.setpoint?.coolCelsius
        hasFan = t.fan != nil
        if t.fan?.timerMode == "ON", let ts = t.fan?.timerTimeout {
            fanUntil = ISO8601DateFormatter.sdm.date(from: ts) ?? ISO8601DateFormatter().date(from: ts)
        } else {
            fanUntil = nil
        }
    }
}

extension ISO8601DateFormatter {
    static let sdm: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
