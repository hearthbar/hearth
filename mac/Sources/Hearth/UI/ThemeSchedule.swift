import CoreLocation
import SwiftUI

/// How the panel picks light or dark: always day, always night, or by sunrise and sunset at a ZIP code.
enum ThemeMode: String, CaseIterable, Identifiable {
    case day, night, auto
    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Day"
        case .night: return "Night"
        case .auto: return "Sunrise and sunset"
        }
    }

    var symbol: String {
        switch self {
        case .day: return "sun.max.fill"
        case .night: return "moon.fill"
        case .auto: return "sunrise.fill"
        }
    }
}

/// Sunrise and sunset from the NOAA approximation, kept pure so it can be tested. Good to a few minutes.
enum SunTimes {
    /// Sunrise and sunset on the given day at a place, or nil when the sun doesn't rise or set that day.
    static func times(on date: Date, latitude: Double, longitude: Double, calendar: Calendar = .current) -> (rise: Date, set: Date)? {
        guard let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) else { return nil }
        let n = Double(dayOfYear), lngHour = longitude / 15

        // Hours after midnight UTC on this date that the sun crosses the horizon.
        func crossing(rising: Bool) -> Double? {
            let t = n + ((rising ? 6 : 18) - lngHour) / 24
            let m = 0.9856 * t - 3.289
            let l = wrap(m + 1.916 * sin(rad(m)) + 0.020 * sin(rad(2 * m)) + 282.634, 360)
            var ra = wrap(deg(atan(0.91764 * tan(rad(l)))), 360)
            ra = (ra + floor(l / 90) * 90 - floor(ra / 90) * 90) / 15
            let sinDec = 0.39782 * sin(rad(l)), cosDec = cos(asin(sinDec))
            let cosH = (cos(rad(90.833)) - sinDec * sin(rad(latitude))) / (cosDec * cos(rad(latitude)))
            guard (-1...1).contains(cosH) else { return nil }
            let h = (rising ? 360 - deg(acos(cosH)) : deg(acos(cosH))) / 15
            return wrap(h + ra - 0.06571 * t - 6.622 - lngHour, 24)
        }

        guard let riseUT = crossing(rising: true), var setUT = crossing(rising: false) else { return nil }
        if setUT <= riseUT { setUT += 24 }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let ymd = calendar.dateComponents([.year, .month, .day], from: date)
        guard let midnight = utc.date(from: ymd) else { return nil }
        return (midnight.addingTimeInterval(riseUT * 3600), midnight.addingTimeInterval(setUT * 3600))
    }

    /// Whether it's dark out at a place right now. False when the sun stays up or down all day.
    static func isNight(at now: Date, latitude: Double, longitude: Double, calendar: Calendar = .current) -> Bool {
        guard let t = times(on: now, latitude: latitude, longitude: longitude, calendar: calendar) else { return false }
        return now < t.rise || now >= t.set
    }

    private static func rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func deg(_ r: Double) -> Double { r * 180 / .pi }
    private static func wrap(_ v: Double, _ m: Double) -> Double { let r = v.truncatingRemainder(dividingBy: m); return r < 0 ? r + m : r }
}

/// The saved theme choice and the place used for sunrise and sunset.
struct ThemeSettings: DynamicProperty {
    @AppStorage("themeMode") var modeRaw = ThemeMode.auto.rawValue
    @AppStorage("themeZip") var zip = ""
    @AppStorage("themeLatitude") var latitude = 0.0
    @AppStorage("themeLongitude") var longitude = 0.0

    var mode: ThemeMode { ThemeMode(rawValue: modeRaw) ?? .auto }
    var hasPlace: Bool { !zip.isEmpty }

    /// The scheme to show now. Auto without a ZIP yet follows the system.
    func scheme(at now: Date) -> ColorScheme? {
        switch mode {
        case .day: return .light
        case .night: return .dark
        case .auto:
            guard hasPlace else { return nil }
            return SunTimes.isNight(at: now, latitude: latitude, longitude: longitude) ? .dark : .light
        }
    }
}

/// Day, Night and Auto as a small three-way switch.
struct ThemeSwitch: View {
    @Binding var mode: String

    var body: some View {
        Picker("Theme", selection: $mode) {
            ForEach(ThemeMode.allCases) { m in
                Image(systemName: m.symbol).help(m.title).tag(m.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .help("Theme: day, night, or switch at sunrise and sunset")
    }
}

/// Asks for a ZIP code and finds where it is, for the sunrise and sunset switch.
struct ZipPrompt: View {
    @Binding var zip: String
    @Binding var latitude: Double
    @Binding var longitude: Double
    var onDone: () -> Void

    @State private var entry = ""
    @State private var finding = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Enter your ZIP code to switch between day and night at sunrise and sunset.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                TextField("ZIP code", text: $entry)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .onSubmit(find)
                Button(finding ? "Finding…" : "Set", action: find)
                    .disabled(finding || entry.trimmingCharacters(in: .whitespaces).count < 5)
                if failed {
                    Text("No match. Check the ZIP code.").font(.caption).foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear { entry = zip }
    }

    private func find() {
        let code = entry.trimmingCharacters(in: .whitespaces)
        guard code.count >= 5 else { return }
        finding = true
        failed = false
        Task { @MainActor in
            defer { finding = false }
            let place = try? await CLGeocoder().geocodeAddressString("\(code), United States").first?.location?.coordinate
            guard let place else { failed = true; return }
            latitude = place.latitude
            longitude = place.longitude
            zip = code
            onDone()
        }
    }
}
