import AppKit
import SwiftUI

/// The top of the panel: an S-shaped channel standing on end, warmer at the top. The heat range is
/// a shaded field left of the channel from the bottom up to the heat setpoint, and the cool range
/// a field right of it from the cool setpoint up. The channel bends between the two and the room
/// rides in it. Drag a setpoint's tick, hover near one and scroll, or use the arrow keys.
/// Dark mode glows on black; light mode is pencil on pale paper.
struct ChannelCard: View {
    @Environment(ThermostatStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let t: Thermostat

    /// The setpoint the arrow keys move. In Auto it is the one last touched.
    @State private var editing: Handle = .heat
    @State private var dragging: Handle?
    @State private var hovered: Handle?
    @State private var scrollAccum: CGFloat = 0

    enum Handle { case heat, cool }

    private var scale: TemperatureScale { t.scale }
    private var geo: ChannelGeometry { ChannelGeometry(visible: ChannelGeometry.visible(scale)) }
    private var palette: ChannelPalette { scheme == .dark ? .glow : .pencil }

    private var adjustable: Bool { t.isOnline && !t.ecoOn && t.mode != .off }

    private var handles: [Handle] {
        guard t.isOnline, !t.ecoOn else { return [] }
        switch t.mode {
        case .heat: return [.heat]
        case .cool: return [.cool]
        case .heatCool: return [.heat, .cool]
        case .off: return []
        }
    }

    private var active: Handle { handles.contains(editing) ? editing : (handles.first ?? .heat) }

    private func setpointC(_ h: Handle) -> Double? { h == .heat ? t.heatC : t.coolC }

    /// The setpoints drawn, in display units: Eco's range while Eco is on, else the ones in use.
    private var shown: (heat: Double?, cool: Double?) {
        guard t.isOnline else { return (nil, nil) }
        if t.ecoOn { return (t.ecoHeatC.map(scale.display), t.ecoCoolC.map(scale.display)) }
        let heat = handles.contains(.heat) ? t.heatC.map { scale.snap(scale.display($0)) } : nil
        let cool = handles.contains(.cool) ? t.coolC.map { scale.snap(scale.display($0)) } : nil
        return (heat, cool)
    }

    private var room: Double? { t.isOnline ? t.ambientC.map(scale.display) : nil }

    /// Nest's minimum Auto gap in display degrees.
    private var gap: Double { scale.display(TemperatureScale.rangeGapC) - scale.display(0) }

    var body: some View {
        VStack(spacing: 10) {
            header
            channel
                .frame(width: ChannelGeometry.size.width, height: ChannelGeometry.size.height)
                .frame(maxWidth: .infinity)
            modes
        }
        .padding(14)
        .foregroundStyle(palette.ink)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.ink.opacity(0.12)))
        .opacity(store.isStale ? 0.75 : 1)
        .saturation(store.isStale ? 0.4 : 1)
        .background(keyboard)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            if store.thermostats.count > 1 {
                Menu {
                    ForEach(store.thermostats) { th in
                        Button(th.name) { store.selectedID = th.id }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(t.name.uppercased())
                        Image(systemName: "chevron.down").font(.system(size: 7, weight: .heavy))
                    }
                    .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            } else {
                Text(t.name.uppercased())
            }
            Spacer()
            Text(statusLine)
        }
        .font(.system(size: 11, weight: .medium))
        .tracking(0.6)
        .foregroundStyle(palette.ink.opacity(0.7))
    }

    private var statusLine: String {
        guard t.isOnline else { return "Offline" }
        let status: String
        switch (t.ecoOn, t.hvac, t.mode) {
        case (true, _, _): status = "Eco"
        case (_, .heating, _): status = "Heating"
        case (_, .cooling, _): status = "Cooling"
        case (_, _, .off): status = "Off"
        default: status = "Idle"
        }
        return t.humidity.map { "\(status) · \(Int($0))%" } ?? status
    }

    // MARK: Channel

    private var channel: some View {
        let geo = geo, palette = palette, shown = shown, room = room, scale = scale
        let lit = dragging ?? hovered
        let bend = ChannelGeometry.bend(heat: shown.heat, cool: shown.cool, gap: gap)
        return Canvas { ctx, _ in
            ChannelDrawing(geo: geo, palette: palette, heat: shown.heat, cool: shown.cool, room: room,
                           bend: bend, lit: lit, eco: t.ecoOn, unit: scale).draw(in: &ctx)
        }
        .contentShape(Rectangle())
        .gesture(drag)
        .onContinuousHover { phase in
            guard adjustable else { hovered = nil; return }
            switch phase {
            case .active(let p): hovered = nearest(toY: p.y)
            case .ended: hovered = nil
            }
        }
        .onWheelScroll { delta in
            guard let h = hovered ?? handles.first else { return }
            scrollAccum += delta
            guard abs(scrollAccum) >= 6 else { return }
            editing = h
            step(scrollAccum > 0 ? 1 : -1)
            scrollAccum = 0
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: shown.heat)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: shown.cool)
        .help(adjustable ? "Drag a setpoint up or down, or hover near one and scroll" : "")
        .accessibilityElement()
        .accessibilityLabel("Inside")
        .accessibilityValue(room.map { "\(Int($0.rounded())) degrees" } ?? "Unknown")
        .accessibilityAdjustableAction { direction in step(direction == .increment ? 1 : -1) }
    }

    private func nearest(toY y: CGFloat) -> Handle? {
        let v = geo.value(atY: y)
        return handles.min { a, b in
            abs((position(a) ?? .infinity) - v) < abs((position(b) ?? .infinity) - v)
        }
    }

    private func position(_ h: Handle) -> Double? { setpointC(h).map { scale.snap(scale.display($0)) } }

    /// Dragging moves the setpoint nearest where the drag began to the pointer's height.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { e in
                guard adjustable else { return }
                if dragging == nil {
                    guard let h = nearest(toY: e.startLocation.y) else { return }
                    dragging = h
                    editing = h
                }
                guard let h = dragging else { return }
                let v = limited(scale.snap(geo.value(atY: e.location.y)), for: h)
                if let p = position(h), abs(p - v) < 0.01 { return }
                set(scale.celsius(v), h)
            }
            .onEnded { _ in dragging = nil }
    }

    // MARK: Modes

    private var modes: some View {
        HStack(spacing: 5) {
            ForEach(Self.modeOrder.filter(t.availableModes.contains), id: \.self) { m in
                modeButton(Self.title(m), on: !t.ecoOn && t.mode == m) { store.setMode(m) }
            }
            if t.ecoAvailable {
                Spacer(minLength: 4)
                modeButton("Eco", on: t.ecoOn) { store.setEco(!t.ecoOn) }
            }
        }
        .disabled(!t.isOnline)
    }

    private static let modeOrder: [ThermostatMode] = [.off, .heat, .heatCool, .cool]

    private static func title(_ m: ThermostatMode) -> String {
        switch m {
        case .off: return "Off"
        case .heat: return "Heat"
        case .heatCool: return "Auto"
        case .cool: return "Cool"
        }
    }

    private func modeButton(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .foregroundStyle(on ? palette.background : palette.ink.opacity(0.75))
                .background(on ? palette.ink : .clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.ink.opacity(on ? 0 : 0.45)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Setting

    /// Keeps a setpoint inside the Nest limits. In Auto it pushes the other one, so it stops a gap
    /// short of the far end.
    private func limited(_ value: Double, for h: Handle) -> Double {
        var lo = scale.range.lowerBound, hi = scale.range.upperBound
        if t.mode == .heatCool {
            if h == .heat { hi -= gap } else { lo += gap }
        }
        return min(max(value, lo), hi)
    }

    private var limitsC: ClosedRange<Double> {
        scale.celsius(scale.range.lowerBound)...scale.celsius(scale.range.upperBound)
    }

    /// Moves the setpoint being edited by one step, pushing the other one in Auto.
    private func step(_ direction: Double) {
        guard adjustable, let c = setpointC(active) else { return }
        let v = limited(scale.snap(scale.display(scale.nudged(c, by: direction))), for: active)
        set(scale.celsius(v), active)
    }

    private func set(_ celsius: Double, _ h: Handle) {
        switch (h, t.mode) {
        case (.heat, .heatCool):
            let p = SetpointRules.pushHeat(celsius, cool: t.coolC, limitsC: limitsC)
            store.setTargets(heatC: p.heat, coolC: p.cool == t.coolC ? nil : p.cool)
        case (.cool, .heatCool):
            let p = SetpointRules.pushCool(celsius, heat: t.heatC, limitsC: limitsC)
            store.setTargets(heatC: p.heat == t.heatC ? nil : p.heat, coolC: p.cool)
        case (.heat, _):
            store.setTargets(heatC: celsius, coolC: nil)
        case (.cool, _):
            store.setTargets(heatC: nil, coolC: celsius)
        }
    }

    /// Up and down arrows step the setpoint while the panel is open.
    private var keyboard: some View {
        ZStack {
            Button("") { step(1) }.keyboardShortcut(.upArrow, modifiers: [])
            Button("") { step(-1) }.keyboardShortcut(.downArrow, modifiers: [])
        }
        .opacity(0)
        .allowsHitTesting(false)
        .disabled(!adjustable)
        .accessibilityHidden(true)
    }
}

// MARK: - Geometry

/// Where things sit in the channel, kept separate so it can be tested. Temperature runs up the
/// height. The heat and cool fields share one column; the channel runs right of it on the heat
/// side, left of it on the cool side, and bends across it between the setpoints.
struct ChannelGeometry: Equatable {
    let visible: ClosedRange<Double>

    static let size = CGSize(width: 184, height: 272)
    static let top: CGFloat = 14
    static let bottom: CGFloat = 258
    static let fieldLeft: CGFloat = 68
    static let fieldRight: CGFloat = 120
    static let channelWidth: CGFloat = 24
    static let heatLane: CGFloat = fieldRight + channelWidth / 2
    static let coolLane: CGFloat = fieldLeft - channelWidth / 2
    static let heatLabelX: CGFloat = 22
    static let coolLabelX: CGFloat = 164

    /// The span the channel shows: the range people actually use.
    static func visible(_ scale: TemperatureScale) -> ClosedRange<Double> {
        scale == .fahrenheit ? 60...84 : 16...29
    }

    func y(_ v: Double) -> CGFloat {
        let f = (min(max(v, visible.lowerBound), visible.upperBound) - visible.lowerBound) / (visible.upperBound - visible.lowerBound)
        return Self.bottom - CGFloat(f) * (Self.bottom - Self.top)
    }

    func value(atY y: CGFloat) -> Double {
        let f = Double((Self.bottom - y) / (Self.bottom - Self.top))
        return min(max(visible.lowerBound + f * (visible.upperBound - visible.lowerBound), visible.lowerBound), visible.upperBound)
    }

    /// The span, in degrees, where the channel bends from the heat lane to the cool lane: between
    /// the two setpoints, or just past the one in use. Nil when neither is shown.
    static func bend(heat: Double?, cool: Double?, gap: Double) -> ClosedRange<Double>? {
        switch (heat, cool) {
        case let (h?, c?): return min(h, c)...max(h, c)
        case let (h?, nil): return h...(h + gap)
        case let (nil, c?): return (c - gap)...c
        default: return nil
        }
    }

    /// The channel's center at a height: on the heat lane below the bend, the cool lane above it,
    /// and a mandrel bend between. Without a bend it runs straight up the middle.
    func center(atY y: CGFloat, bend: ClosedRange<Double>?) -> CGFloat {
        tube(bend: bend).center(atY: y)
    }

    /// The channel's shape for a bend.
    func tube(bend: ClosedRange<Double>?) -> ChannelTube {
        guard let bend else { return ChannelTube(straightAt: (Self.heatLane + Self.coolLane) / 2) }
        return ChannelTube(from: Self.heatLane, to: Self.coolLane, low: y(bend.lowerBound), high: y(bend.upperBound))
    }
}

/// A channel of constant width that steps from one lane to another like a mandrel-bent tube: an
/// arc, a straight run, and a matching arc. It fits the bend between two heights when it can and
/// centers on them when they're too close.
struct ChannelTube {
    private var center: [CGPoint] = []
    private var left: [CGPoint] = []
    private var right: [CGPoint] = []

    static let radius: CGFloat = 22
    static let maxAngle: CGFloat = .pi * 80 / 180
    private static let far: CGFloat = 10_000

    init(straightAt x: CGFloat) {
        let half = ChannelGeometry.channelWidth / 2
        for y in [-Self.far, Self.far] {
            center.append(CGPoint(x: x, y: y)); left.append(CGPoint(x: x - half, y: y)); right.append(CGPoint(x: x + half, y: y))
        }
    }

    /// `from` is the lane below the bend, `to` the lane above; `low` and `high` are the bend's ends
    /// in view coordinates (low has the larger y).
    init(from xLow: CGFloat, to xHigh: CGFloat, low: CGFloat, high: CGFloat) {
        let r = Self.radius, half = ChannelGeometry.channelWidth / 2
        let d = abs(xLow - xHigh), dir: CGFloat = xHigh < xLow ? -1 : 1

        // Height of the bend at a given turn angle, with the straight run filling the rest of the step.
        func run(_ a: CGFloat) -> CGFloat { max((d - 2 * r * (1 - cos(a))) / sin(a), 0) }
        func height(_ a: CGFloat) -> CGFloat { 2 * r * sin(a) + run(a) * cos(a) }
        let want = max(low - high, 0)
        var lo: CGFloat = 0.01, hi = Self.maxAngle
        if height(hi) < want {
            for _ in 0..<40 { let m = (lo + hi) / 2; if height(m) > want { lo = m } else { hi = m } }
        }
        let a = hi, s = run(a), h = height(a)
        let y0 = (low + high) / 2 + h / 2

        // Points along the centerline, each with the unit normal toward +x.
        var spine: [(CGPoint, CGVector)] = []
        let steps = 24
        for i in 0...steps {   // first arc, turning off the lower lane
            let t = a * CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: xLow + dir * r * (1 - cos(t)), y: y0 - r * sin(t))
            spine.append((p, CGVector(dx: cos(t), dy: dir * sin(t))))
        }
        let p1 = spine.last!.0
        let p2 = CGPoint(x: p1.x + dir * s * sin(a), y: p1.y - s * cos(a))
        for i in 0...steps {   // second arc, straightening onto the upper lane
            let t = a * CGFloat(steps - i) / CGFloat(steps)
            let p = CGPoint(x: xHigh - dir * r * (1 - cos(t)), y: p2.y - r * (sin(a) - sin(t)))
            spine.append((p, CGVector(dx: cos(t), dy: dir * sin(t))))
        }
        let top = spine.last!.0
        spine.insert((CGPoint(x: xLow, y: Self.far), CGVector(dx: 1, dy: 0)), at: 0)
        spine.append((CGPoint(x: top.x, y: -Self.far), CGVector(dx: 1, dy: 0)))

        // Listed top to bottom so lookups can walk by y.
        for (p, n) in spine.reversed() {
            center.append(p)
            left.append(CGPoint(x: p.x - half * n.dx, y: p.y - half * n.dy))
            right.append(CGPoint(x: p.x + half * n.dx, y: p.y + half * n.dy))
        }
    }

    func center(atY y: CGFloat) -> CGFloat { Self.x(atY: y, on: center) }
    func left(atY y: CGFloat) -> CGFloat { Self.x(atY: y, on: left) }
    func right(atY y: CGFloat) -> CGFloat { Self.x(atY: y, on: right) }

    private static func x(atY y: CGFloat, on line: [CGPoint]) -> CGFloat {
        guard let i = line.firstIndex(where: { $0.y >= y }) else { return line.last!.x }
        guard i > 0 else { return line[0].x }
        let a = line[i - 1], b = line[i]
        let t = b.y - a.y < 0.0001 ? 0 : (y - a.y) / (b.y - a.y)
        return a.x + (b.x - a.x) * t
    }
}

// MARK: - Look

struct ChannelPalette {
    let background: Color
    let ink: Color
    let heat: Color
    let cool: Color
    /// Field opacity at the far end, and where it meets the setpoint.
    let fieldFull: Double
    let fieldEdge: Double
    let stripe: Color
    /// The column between the setpoints, where neither heat nor cool runs.
    let rest: Color
    let glow: Bool
    let room: Color
    let roomText: Color
    let tick: Color?

    /// Dark mode: glowing fields on black.
    static let glow = ChannelPalette(
        background: Color(red: 0.04, green: 0.043, blue: 0.05), ink: Color(red: 0.91, green: 0.925, blue: 0.94),
        heat: Color(red: 1, green: 0.416, blue: 0.173), cool: Color(red: 0.24, green: 0.576, blue: 1),
        fieldFull: 0.9, fieldEdge: 0.7, stripe: .black.opacity(0.35), rest: .white.opacity(0.08),
        glow: true, room: .white, roomText: Color(red: 0.04, green: 0.043, blue: 0.05), tick: nil)

    /// Light mode: soft color fields on pale paper.
    static let pencil = ChannelPalette(
        background: Color(red: 0.933, green: 0.94, blue: 0.933), ink: Color(red: 0.137, green: 0.145, blue: 0.137),
        heat: Color(red: 0.878, green: 0.384, blue: 0.165), cool: Color(red: 0.184, green: 0.498, blue: 0.839),
        fieldFull: 0.55, fieldEdge: 0.42, stripe: Color(red: 0.933, green: 0.94, blue: 0.933).opacity(0.6),
        rest: Color(red: 0.137, green: 0.145, blue: 0.137).opacity(0.07),
        glow: true,
        room: Color(red: 0.933, green: 0.94, blue: 0.933), roomText: Color(red: 0.137, green: 0.145, blue: 0.137),
        tick: Color(red: 0.137, green: 0.145, blue: 0.137))
}

/// Draws one frame of the channel.
private struct ChannelDrawing {
    let geo: ChannelGeometry
    let palette: ChannelPalette
    let heat: Double?
    let cool: Double?
    let room: Double?
    let bend: ClosedRange<Double>?
    let lit: ChannelCard.Handle?
    let eco: Bool
    let unit: TemperatureScale

    private typealias G = ChannelGeometry
    /// How far the glow spreads past a field's edge.
    private static let glowRadius: CGFloat = 6

    func draw(in ctx: inout GraphicsContext) {
        let ys = stride(from: G.top - 8, through: G.bottom + 8, by: 2).map { $0 }
        let tube = geo.tube(bend: bend)
        let top = G.top - 8, bottom = G.bottom + 8

        // One column of color with the channel cut out of it as negative space.
        var cut = Path()
        cut.move(to: CGPoint(x: tube.left(atY: ys[0]), y: ys[0]))
        for y in ys.dropFirst() { cut.addLine(to: CGPoint(x: tube.left(atY: y), y: y)) }
        for y in ys.reversed() { cut.addLine(to: CGPoint(x: tube.right(atY: y), y: y)) }
        cut.closeSubpath()
        let open = Path(CGRect(x: G.fieldLeft, y: top, width: G.fieldRight - G.fieldLeft, height: bottom - top)).subtracting(cut)
        func band(_ from: CGFloat, _ to: CGFloat) -> Path {
            open.intersection(Path(CGRect(x: 0, y: from, width: G.size.width, height: max(to - from, 0))))
        }

        // Heat fills from the bottom up to its setpoint, cool from the top down to its own; the
        // span between them stays a quiet neutral so the channel's bend still shows.
        let heatY = heat.map(geo.y) ?? bottom, coolY = cool.map(geo.y) ?? top
        ctx.fill(band(coolY, heatY), with: .color(palette.rest))
        if heat != nil { fill(&ctx, band(heatY, bottom), color: palette.heat, far: bottom, near: heatY) }
        if cool != nil { fill(&ctx, band(top, coolY), color: palette.cool, far: top, near: coolY) }

        // A faint stripe per step keeps a sense of degrees inside the column.
        var stripes = Path()
        for v in stride(from: geo.visible.lowerBound, through: geo.visible.upperBound, by: unit.step) {
            stripes.move(to: CGPoint(x: G.fieldLeft, y: geo.y(v))); stripes.addLine(to: CGPoint(x: G.fieldRight, y: geo.y(v)))
        }
        ctx.drawLayer { layer in
            layer.clip(to: open)
            layer.stroke(stripes, with: .color(palette.stripe), lineWidth: 1)
        }

        // Setpoints: heat reaches left from its lane to a number past the column, cool reaches right.
        if let heat { tick(&ctx, value: heat, from: G.heatLane, to: G.heatLabelX + 18, labelX: G.heatLabelX, color: palette.heat, handle: .heat) }
        if let cool { tick(&ctx, value: cool, from: G.coolLane, to: G.coolLabelX - 18, labelX: G.coolLabelX, color: palette.cool, handle: .cool) }

        // The room rides in the channel.
        if let room {
            let y = geo.y(room), c = tube.center(atY: y)
            let r: CGFloat = 14
            let circle = Path(ellipseIn: CGRect(x: c - r, y: y - r, width: 2 * r, height: 2 * r))
            ctx.fill(circle, with: .color(palette.room))
            ctx.stroke(circle, with: .color(palette.ink), lineWidth: 1.6)
            ctx.draw(Text("\(Int(room.rounded()))").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.roomText),
                     at: CGPoint(x: c, y: y))
        }
    }

    /// Fills a field, deepest at the channel's far end, with a glow around it.
    private func fill(_ ctx: inout GraphicsContext, _ field: Path, color: Color, far: CGFloat, near: CGFloat) {
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [color.opacity(palette.fieldFull), color.opacity(palette.fieldEdge)]),
            startPoint: CGPoint(x: 0, y: far), endPoint: CGPoint(x: 0, y: near))
        if palette.glow {
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: Self.glowRadius))
                layer.fill(field, with: .color(color.opacity(palette.fieldFull)))
            }
        }
        ctx.fill(field, with: shading)
    }

    private func tick(_ ctx: inout GraphicsContext, value: Double, from: CGFloat, to: CGFloat, labelX: CGFloat,
                      color: Color, handle: ChannelCard.Handle) {
        let y = geo.y(value)
        var p = Path()
        p.move(to: CGPoint(x: from, y: y))
        p.addLine(to: CGPoint(x: to, y: y))
        let stroke = eco ? Theme.eco : (palette.tick ?? color)
        ctx.stroke(p, with: .color(stroke), style: StrokeStyle(lineWidth: lit == handle ? 3 : 2, lineCap: .round))
        let label = Text(unit.format(unit.celsius(value)))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(eco ? Theme.eco : color)
        ctx.draw(label, at: CGPoint(x: labelX, y: y))
    }
}

// MARK: - Scroll wheel support

private struct ScrollWheelModifier: ViewModifier {
    /// Follow the fingers, right or up raising, and skip momentum so a flick can't run away.
    var followFingers = false
    let action: (CGFloat) -> Void
    @State private var monitor: Any?
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering = $0 }
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    guard hovering else { return event }
                    if followFingers {
                        guard event.momentumPhase.isEmpty else { return nil }
                        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
                        action((event.scrollingDeltaX - event.scrollingDeltaY) * sign)
                        return nil
                    }
                    let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                        ? -event.scrollingDeltaX : event.scrollingDeltaY
                    action(delta)
                    return nil
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

    /// Scrolling that follows the fingers: up or right raises, without momentum.
    func onWheelScroll(_ action: @escaping (CGFloat) -> Void) -> some View {
        modifier(ScrollWheelModifier(followFingers: true, action: action))
    }
}
