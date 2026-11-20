import Foundation
import Testing
@testable import Hearth

private func device(_ traits: String, name: String = "enterprises/p/devices/d1",
                    type: String = "sdm.devices.types.THERMOSTAT", room: String? = "Hallway") throws -> Thermostat {
    let relations = room.map { #","parentRelations":[{"parent":"x","displayName":"\#($0)"}]"# } ?? ""
    let json = #"{"name":"\#(name)","type":"\#(type)"\#(relations),"traits":{\#(traits)}}"#
    return Thermostat(device: try JSONDecoder().decode(SDMDevice.self, from: Data(json.utf8)))
}

private let fullTraits = """
"sdm.devices.traits.Info":{"customName":"Main Floor"},
"sdm.devices.traits.Humidity":{"ambientHumidityPercent":44},
"sdm.devices.traits.Connectivity":{"status":"ONLINE"},
"sdm.devices.traits.Fan":{"timerMode":"OFF"},
"sdm.devices.traits.ThermostatMode":{"availableModes":["HEAT","COOL","HEATCOOL","OFF"],"mode":"HEAT"},
"sdm.devices.traits.ThermostatEco":{"availableModes":["OFF","MANUAL_ECO"],"mode":"OFF","heatCelsius":15.5,"coolCelsius":26.6},
"sdm.devices.traits.ThermostatHvac":{"status":"HEATING"},
"sdm.devices.traits.Settings":{"temperatureScale":"CELSIUS"},
"sdm.devices.traits.ThermostatTemperatureSetpoint":{"heatCelsius":21.5},
"sdm.devices.traits.Temperature":{"ambientTemperatureCelsius":19.8}
"""

@Suite("SDM parsing")
struct ParsingTests {
    @Test func heatMode() throws {
        let t = try device(fullTraits)
        #expect(t.id == "enterprises/p/devices/d1")
        #expect(t.name == "Main Floor")
        #expect(t.isOnline)
        #expect(t.mode == .heat)
        #expect(t.availableModes == [.heat, .cool, .heatCool, .off])
        #expect(t.hvac == .heating)
        #expect(t.scale == .celsius)
        #expect(t.heatC == 21.5)
        #expect(t.coolC == nil)
        #expect(t.ambientC == 19.8)
        #expect(t.humidity == 44)
        #expect(t.ecoAvailable)
        #expect(!t.ecoOn)
        #expect(t.ecoHeatC == 15.5)
        #expect(t.ecoCoolC == 26.6)
        #expect(t.hasFan)
        #expect(!t.fanRunning)
    }

    @Test func coolMode() throws {
        let t = try device("""
        "sdm.devices.traits.ThermostatMode":{"availableModes":["COOL","OFF"],"mode":"COOL"},
        "sdm.devices.traits.ThermostatHvac":{"status":"COOLING"},
        "sdm.devices.traits.ThermostatTemperatureSetpoint":{"coolCelsius":24}
        """)
        #expect(t.mode == .cool)
        #expect(t.availableModes == [.cool, .off])
        #expect(t.hvac == .cooling)
        #expect(t.coolC == 24)
        #expect(t.heatC == nil)
    }

    @Test func heatCoolMode() throws {
        let t = try device("""
        "sdm.devices.traits.ThermostatMode":{"mode":"HEATCOOL"},
        "sdm.devices.traits.ThermostatTemperatureSetpoint":{"heatCelsius":20,"coolCelsius":24.5}
        """)
        #expect(t.mode == .heatCool)
        #expect(t.heatC == 20)
        #expect(t.coolC == 24.5)
        // No availableModes listed means every mode is offered.
        #expect(t.availableModes == ThermostatMode.allCases)
    }

    @Test func ecoOn() throws {
        let t = try device("""
        "sdm.devices.traits.ThermostatMode":{"mode":"HEAT"},
        "sdm.devices.traits.ThermostatEco":{"availableModes":["OFF","MANUAL_ECO"],"mode":"MANUAL_ECO","heatCelsius":16,"coolCelsius":27}
        """)
        #expect(t.ecoOn)
        #expect(t.ecoHeatC == 16)
        #expect(t.statusText == "Eco")
    }

    @Test func offline() throws {
        let t = try device(#""sdm.devices.traits.Connectivity":{"status":"OFFLINE"}"#)
        #expect(!t.isOnline)
        #expect(t.statusText == "Offline")
        #expect(t.glow == nil)
    }

    @Test func fanTimer() throws {
        let future = ISO8601DateFormatter().string(from: Date().addingTimeInterval(1800))
        let t = try device(#""sdm.devices.traits.Fan":{"timerMode":"ON","timerTimeout":"\#(future)"}"#)
        #expect(t.hasFan)
        #expect(t.fanRunning)
        let until = try #require(t.fanUntil)
        #expect(abs(until.timeIntervalSinceNow - 1800) < 5)

        let past = try device(#""sdm.devices.traits.Fan":{"timerMode":"ON","timerTimeout":"2020-01-01T00:00:00.000Z"}"#)
        #expect(past.fanUntil != nil)
        #expect(!past.fanRunning)
    }

    @Test func missingTraitsUseDefaults() throws {
        let t = try device("", room: nil)
        #expect(t.name == "Thermostat")
        #expect(t.isOnline)
        #expect(t.mode == .off)
        #expect(t.hvac == .off)
        #expect(t.scale == .fahrenheit)
        #expect(t.ambientC == nil)
        #expect(t.humidity == nil)
        #expect(!t.hasFan)
        #expect(!t.ecoAvailable)
    }

    @Test func nameFallsBackToRoom() throws {
        let t = try device(#""sdm.devices.traits.Info":{"customName":"  "}"#, room: "Upstairs")
        #expect(t.name == "Upstairs")
    }

    @Test func deviceListFiltersNonThermostats() throws {
        let json = """
        {"devices":[
          {"name":"a","type":"sdm.devices.types.THERMOSTAT","traits":{}},
          {"name":"b","type":"sdm.devices.types.CAMERA","traits":{}}
        ]}
        """
        let list = try JSONDecoder().decode(SDMDeviceList.self, from: Data(json.utf8))
        let thermostats = (list.devices ?? []).filter { $0.type == "sdm.devices.types.THERMOSTAT" }
        #expect(thermostats.map(\.name) == ["a"])

        let empty = try JSONDecoder().decode(SDMDeviceList.self, from: Data("{}".utf8))
        #expect(empty.devices == nil)
    }

    @Test func samplesParse() {
        #expect(Thermostat.samples.count == 3)
        #expect(Thermostat.samples[0].mode == .heat)
        #expect(Thermostat.samples[1].mode == .heatCool)
        #expect(Thermostat.samples[2].mode == .cool)
    }
}

@Suite("SDM errors")
struct ErrorTests {
    @Test func decodesGoogleMessage() {
        let body = #"{"error":{"code":400,"message":"Command not supported.","status":"FAILED_PRECONDITION"}}"#
        let e = SDMError(status: 400, data: Data(body.utf8))
        #expect(e.message == "Command not supported.")
        #expect(e.errorDescription == "Command not supported.")
        #expect(!e.isServerError)
        #expect(!e.isRateLimited)
    }

    @Test func fallsBackToStatusText() {
        let e = SDMError(status: 503, data: Data("not json".utf8))
        #expect(e.message == HTTPURLResponse.localizedString(forStatusCode: 503))
        #expect(e.isServerError)
    }

    @Test func rateLimitAndAuthWording() {
        let limited = SDMError(status: 429, data: Data())
        #expect(limited.isRateLimited)
        #expect(limited.errorDescription?.contains("rate limiting") == true)

        let denied = SDMError(status: 403, data: Data(#"{"error":{"message":"Permission denied."}}"#.utf8))
        #expect(denied.errorDescription == "Google rejected the request: Permission denied.")
    }
}
