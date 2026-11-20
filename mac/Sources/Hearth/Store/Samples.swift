import Foundation

extension Thermostat {
    static let samples: [Thermostat] = {
        func make(_ json: String) -> Thermostat {
            Thermostat(device: try! JSONDecoder().decode(SDMDevice.self, from: Data(json.utf8)))
        }
        return [
            make("""
            {"name":"enterprises/demo/devices/hallway","type":"sdm.devices.types.THERMOSTAT",
             "parentRelations":[{"parent":"x","displayName":"Hallway"}],
             "traits":{
              "sdm.devices.traits.Info":{"customName":""},
              "sdm.devices.traits.Humidity":{"ambientHumidityPercent":41},
              "sdm.devices.traits.Connectivity":{"status":"ONLINE"},
              "sdm.devices.traits.Fan":{"timerMode":"OFF"},
              "sdm.devices.traits.ThermostatMode":{"availableModes":["HEAT","COOL","HEATCOOL","OFF"],"mode":"HEAT"},
              "sdm.devices.traits.ThermostatEco":{"availableModes":["OFF","MANUAL_ECO"],"mode":"OFF","heatCelsius":15.5,"coolCelsius":26.6},
              "sdm.devices.traits.ThermostatHvac":{"status":"HEATING"},
              "sdm.devices.traits.Settings":{"temperatureScale":"FAHRENHEIT"},
              "sdm.devices.traits.ThermostatTemperatureSetpoint":{"heatCelsius":22.2},
              "sdm.devices.traits.Temperature":{"ambientTemperatureCelsius":20.1}}}
            """),
            make("""
            {"name":"enterprises/demo/devices/upstairs","type":"sdm.devices.types.THERMOSTAT",
             "parentRelations":[{"parent":"x","displayName":"Upstairs"}],
             "traits":{
              "sdm.devices.traits.Humidity":{"ambientHumidityPercent":47},
              "sdm.devices.traits.Connectivity":{"status":"ONLINE"},
              "sdm.devices.traits.Fan":{"timerMode":"OFF"},
              "sdm.devices.traits.ThermostatMode":{"availableModes":["HEAT","COOL","HEATCOOL","OFF"],"mode":"HEATCOOL"},
              "sdm.devices.traits.ThermostatEco":{"availableModes":["OFF","MANUAL_ECO"],"mode":"OFF","heatCelsius":15.5,"coolCelsius":26.6},
              "sdm.devices.traits.ThermostatHvac":{"status":"OFF"},
              "sdm.devices.traits.Settings":{"temperatureScale":"FAHRENHEIT"},
              "sdm.devices.traits.ThermostatTemperatureSetpoint":{"heatCelsius":20.0,"coolCelsius":24.4},
              "sdm.devices.traits.Temperature":{"ambientTemperatureCelsius":22.0}}}
            """),
            make("""
            {"name":"enterprises/demo/devices/bedroom","type":"sdm.devices.types.THERMOSTAT",
             "parentRelations":[{"parent":"x","displayName":"Bedroom"}],
             "traits":{
              "sdm.devices.traits.Humidity":{"ambientHumidityPercent":52},
              "sdm.devices.traits.Connectivity":{"status":"ONLINE"},
              "sdm.devices.traits.Fan":{"timerMode":"OFF"},
              "sdm.devices.traits.ThermostatMode":{"availableModes":["HEAT","COOL","HEATCOOL","OFF"],"mode":"COOL"},
              "sdm.devices.traits.ThermostatEco":{"availableModes":["OFF","MANUAL_ECO"],"mode":"OFF","heatCelsius":15.5,"coolCelsius":26.6},
              "sdm.devices.traits.ThermostatHvac":{"status":"COOLING"},
              "sdm.devices.traits.Settings":{"temperatureScale":"FAHRENHEIT"},
              "sdm.devices.traits.ThermostatTemperatureSetpoint":{"coolCelsius":23.3},
              "sdm.devices.traits.Temperature":{"ambientTemperatureCelsius":25.0}}}
            """),
        ]
    }()
}
