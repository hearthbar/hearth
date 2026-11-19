import SwiftUI

/// A Nest-style dial: tick ring over a dark face that glows while heating or cooling.
/// Drag a handle, scroll, or use the arrow keys to change the setpoint.
struct DialView: View {
    @Environment(ThermostatStore.self) private var store
    let t: Thermostat

    private let size: CGFloat = 236
    private let startAngle = 135.0   // degrees, clockwise from 3 o'clock
    private let sweep = 270.0
    private let tickCount = 120

    @State private var dragging: Handle?
    @State private var scrollAccum: CGFloat = 0

    enum Handle { case heat, cool }

    private var scale: TemperatureScale { t.scale }
    private var range: ClosedRange<Double> { scale.range }
    private var adjustable: Bool { t.isOnline && !t.ecoOn && t.mode != .off }

    var body: some View {
        ZStack {
            face
            ticks
            handles
            center
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(drag)
        .onScrollWheel { delta in
            guard adjustable else { return }
            scrollAccum += delta
            if abs(scrollAccum) >= 6 {
                store.nudge(scrollAccum > 0 ? 1 : -1)
                scrollAccum = 0
            }
        }
        .animation(.easeInOut(duration: 0.6), value: t.hvac)
        .animation(.easeInOut(duration: 0.3), value: t.mode)
        .help(adjustable ? "Drag a handle or scroll to change the temperature" : t.statusText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(t.name) thermostat, \(accessibilityMode)")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            guard adjustable else { return }
            switch direction {
            case .increment: store.nudge(1)
            case .decrement: store.nudge(-1)
            @unknown default: break
            }
        }
    }

    // MARK: Accessibility

    private var accessibilityMode: String {
        if !t.isOnline { return "offline" }
        if t.ecoOn { return "Eco mode" }
        return "\(t.mode.title) mode"
    }

    private var accessibilityValue: String {
        func spoken(_ c: Double?) -> String { "\(scale.format(c).dropLast()) degrees" }
        var parts: [String] = []
        if t.isOnline && !t.ecoOn {
            switch t.mode {
            case .heat: parts.append("Heat set to \(spoken(t.heatC))")
            case .cool: parts.append("Cool set to \(spoken(t.coolC))")
            case .heatCool: parts.append("Heat set to \(spoken(t.heatC)), cool set to \(spoken(t.coolC))")
            case .off: parts.append("Off")
            }
        } else if t.ecoOn {
            parts.append("Eco")
        }
        if t.ambientC != nil { parts.append("inside \(scale.format(t.ambientC).dropLast())") }
        switch t.hvac {
        case .heating: parts.append("heating")
        case .cooling: parts.append("cooling")
        case .off: break
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Layers

    private var face: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Theme.faceEdge, Theme.face],
                    center: .init(x: 0.5, y: 0.35), startRadius: 4, endRadius: size * 0.6))
            if let glow = t.glow {
                Circle()
                    .fill(RadialGradient(
                        colors: [glow.opacity(0.95), glow.opacity(0.55), glow.opacity(0.15)],
                        center: .init(x: 0.5, y: 0.4), startRadius: 0, endRadius: size * 0.62))
                    .transition(.opacity)
            }
            Circle()
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
        }
        .shadow(color: (t.glow ?? .black).opacity(t.glow == nil ? 0.35 : 0.5), radius: 18, y: 6)
    }

    private var ticks: some View {
        let heatF = t.heatC.map { fraction(scale.display($0)) }
        let coolF = t.coolC.map { fraction(scale.display($0)) }
        let ambientF = t.ambientC.map { fraction(scale.display($0)) }
        let mode = t.mode
        let active = adjustable
        let glowing = t.glow != nil
        let count = tickCount

        return Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let outer = sz.width / 2 - 12
            for i in 0...count {
                let f = Double(i) / Double(count)
                var len: CGFloat = 12
                var width: CGFloat = 1.6
                var color = Color.white.opacity(glowing ? 0.35 : 0.18)

                if active {
                    var lo: Double?, hi: Double?
                    switch mode {
                    case .heat: if let h = heatF, let a = ambientF { lo = min(h, a); hi = max(h, a) }
                    case .cool: if let cl = coolF, let a = ambientF { lo = min(cl, a); hi = max(cl, a) }
                    case .heatCool: lo = heatF; hi = coolF
                    case .off: break
                    }
                    if let lo, let hi, f >= lo, f <= hi {
                        color = .white.opacity(0.9)
                    }
                }
                if let a = ambientF, abs(f - a) < 0.5 / Double(count) {
                    len = 20; width = 2.6; color = .white
                }

                let angle = Angle.degrees(startAngle + sweep * f).radians
                let p1 = CGPoint(x: c.x + cos(angle) * outer, y: c.y + sin(angle) * outer)
                let p2 = CGPoint(x: c.x + cos(angle) * (outer - len), y: c.y + sin(angle) * (outer - len))
                var path = Path()
                path.move(to: p1)
                path.addLine(to: p2)
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var handles: some View {
        if adjustable {
            if t.mode != .cool, let h = t.heatC { knob(at: scale.display(h), color: Theme.heat, active: dragging == .heat) }
            if t.mode != .heat, let c = t.coolC { knob(at: scale.display(c), color: Theme.cool, active: dragging == .cool) }
        }
    }

    private func knob(at value: Double, color: Color, active: Bool) -> some View {
        let r = size / 2 - 18
        let a = Angle.degrees(geometry.angle(at: fraction(value))).radians
        return Circle()
            .fill(.white)
            .overlay(Circle().fill(color).padding(4))
            .frame(width: active ? 22 : 18, height: active ? 22 : 18)
            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
            .offset(x: cos(a) * r, y: sin(a) * r)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: active)
    }

    private var center: some View {
        VStack(spacing: 2) {
            Text(t.statusText.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.75))

            targetText
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.snappy, value: t.heatC)
                .animation(.snappy, value: t.coolC)

            if let a = t.ambientC {
                Label("Inside \(scale.format(a))", systemImage: "house.fill")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .labelStyle(.titleAndIcon)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var targetText: some View {
        let big = Font.system(size: 64, weight: .light, design: .rounded)
        if !t.isOnline {
            Image(systemName: "wifi.slash").font(.system(size: 44, weight: .light))
        } else if t.ecoOn {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill").foregroundStyle(Theme.eco)
                Text(rangeText(t.ecoHeatC, t.ecoCoolC))
            }
            .font(.system(size: 34, weight: .light, design: .rounded))
        } else {
            switch t.mode {
            case .off:
                Text("Off").font(.system(size: 52, weight: .light, design: .rounded))
            case .heat:
                Text(scale.format(t.heatC).dropLast()).font(big)
            case .cool:
                Text(scale.format(t.coolC).dropLast()).font(big)
            case .heatCool:
                HStack(spacing: 8) {
                    Text(scale.format(t.heatC).dropLast()).foregroundStyle(Theme.heatLight)
                    Text("·").foregroundStyle(.white.opacity(0.5))
                    Text(scale.format(t.coolC).dropLast()).foregroundStyle(Theme.coolLight)
                }
                .font(.system(size: 46, weight: .light, design: .rounded))
            }
        }
    }

    private func rangeText(_ lo: Double?, _ hi: Double?) -> String {
        switch (lo, hi) {
        case let (l?, h?): return "\(scale.format(l)) - \(scale.format(h))"
        case let (l?, nil): return scale.format(l)
        case let (nil, h?): return scale.format(h)
        default: return "Eco"
        }
    }

    // MARK: Interaction

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                guard adjustable, let f = fraction(at: g.location) else { return }
                let value = scale.snap(geometry.value(at: f))

                if dragging == nil {
                    dragging = nearestHandle(to: value)
                    // Ignore taps that start in the middle of the dial.
                    if distanceFromCenter(g.startLocation) < size * 0.3 { dragging = nil; return }
                }
                apply(value, to: dragging)
            }
            .onEnded { _ in dragging = nil }
    }

    private func nearestHandle(to value: Double) -> Handle? {
        switch t.mode {
        case .heat: return .heat
        case .cool: return .cool
        case .heatCool:
            guard let h = t.heatC.map(scale.display), let c = t.coolC.map(scale.display) else { return nil }
            return abs(value - h) <= abs(value - c) ? .heat : .cool
        case .off: return nil
        }
    }

    private func apply(_ value: Double, to handle: Handle?) {
        guard let handle else { return }
        let celsius = scale.celsius(value)
        switch (handle, t.mode) {
        case (.heat, .heatCool):
            store.setTargets(heatC: SetpointRules.heat(celsius, cool: t.coolC), coolC: nil)
        case (.cool, .heatCool):
            store.setTargets(heatC: nil, coolC: SetpointRules.cool(celsius, heat: t.heatC))
        case (.heat, _):
            store.setTargets(heatC: celsius, coolC: nil)
        case (.cool, _):
            store.setTargets(heatC: nil, coolC: celsius)
        }
    }

    // MARK: Geometry

    private var geometry: DialGeometry { DialGeometry(size: size, startAngle: startAngle, sweep: sweep, range: range) }

    private func fraction(_ value: Double) -> Double { geometry.fraction(of: value) }

    private func distanceFromCenter(_ p: CGPoint) -> CGFloat { geometry.distanceFromCenter(p) }

    private func fraction(at p: CGPoint) -> Double? { geometry.fraction(at: p) }
}

/// Pure arc math for the dial, kept separate so it can be tested.
struct DialGeometry {
    let size: CGFloat
    let startAngle: Double   // degrees, clockwise from 3 o'clock
    let sweep: Double
    let range: ClosedRange<Double>

    /// Position of a value along the arc, 0...1, clamped.
    func fraction(of value: Double) -> Double {
        min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    func value(at fraction: Double) -> Double {
        range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }

    /// Angle in degrees for a position along the arc.
    func angle(at fraction: Double) -> Double {
        startAngle + sweep * fraction
    }

    func distanceFromCenter(_ p: CGPoint) -> CGFloat {
        hypot(p.x - size / 2, p.y - size / 2)
    }

    /// Maps a point to a 0...1 position along the arc. Points in the dead zone at the bottom
    /// snap to whichever end is closer. Returns nil right at the center.
    func fraction(at p: CGPoint) -> Double? {
        let dx = p.x - size / 2, dy = p.y - size / 2
        guard hypot(dx, dy) > 10 else { return nil }
        var deg = atan2(dy, dx) * 180 / .pi
        if deg < 0 { deg += 360 }
        var rel = deg - startAngle
        if rel < 0 { rel += 360 }
        if rel > sweep { rel = rel > sweep + (360 - sweep) / 2 ? 0 : sweep }
        return rel / sweep
    }
}

// MARK: - Scroll wheel support

private struct ScrollWheelModifier: ViewModifier {
    let action: (CGFloat) -> Void
    @State private var monitor: Any?
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering = $0 }
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    if hovering { action(event.scrollingDeltaY); return nil }
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

extension View {
    func onScrollWheel(_ action: @escaping (CGFloat) -> Void) -> some View {
        modifier(ScrollWheelModifier(action: action))
    }
}
