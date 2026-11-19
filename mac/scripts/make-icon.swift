#!/usr/bin/env swift
// Draws the Hearth app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift (run from the repo root)

import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
let fm = FileManager.default
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
try fm.createDirectory(at: resources, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: a
    )
}

func drawIcon(size: Int) -> CGImage {
    let s = CGFloat(size)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.scaleBy(x: s / 1024, y: s / 1024)

    // Background squircle, inset per macOS icon grid (824pt body in 1024 canvas).
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0x1C1F26))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let bg = CGGradient(colorsSpace: cs, colors: [color(0x2E333D), color(0x14161B)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    let center = CGPoint(x: 512, y: 512)
    let ringRadius: CGFloat = 272
    let ringWidth: CGFloat = 54

    // Faint track ring.
    ctx.setLineCap(.round)
    ctx.setLineWidth(ringWidth)
    ctx.setStrokeColor(color(0xFFFFFF, 0.07))
    ctx.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Gradient arc: cool blue on the left, warm orange on the right, open at the bottom.
    let gap: CGFloat = .pi / 2.6
    let start = -.pi / 2 - gap / 2          // bottom-left, going clockwise over the top
    let end = -.pi / 2 + gap / 2            // bottom-right
    let arc = CGMutablePath()
    arc.addArc(center: center, radius: ringRadius, startAngle: start, endAngle: end, clockwise: true)
    let stroked = arc.copy(strokingWithWidth: ringWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)

    ctx.saveGState()
    ctx.addPath(stroked)
    ctx.clip()
    let ring = CGGradient(
        colorsSpace: cs,
        colors: [color(0x3FA9FF), color(0x7C7CF5), color(0xFF6A3D), color(0xFFB13B)] as CFArray,
        locations: [0, 0.42, 0.78, 1]
    )!
    ctx.drawLinearGradient(ring, start: CGPoint(x: 240, y: 512), end: CGPoint(x: 784, y: 512), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // Soft glow under the warm end.
    ctx.saveGState()
    ctx.addPath(stroked)
    ctx.clip()
    let glow = CGGradient(colorsSpace: cs, colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 802), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 802), endRadius: 260, options: [])
    ctx.restoreGState()

    // Dark face.
    let faceRadius: CGFloat = 208
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x000000, 0.55))
    ctx.addEllipse(in: CGRect(x: center.x - faceRadius, y: center.y - faceRadius, width: faceRadius * 2, height: faceRadius * 2))
    ctx.setFillColor(color(0x101217))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: center.x - faceRadius, y: center.y - faceRadius, width: faceRadius * 2, height: faceRadius * 2))
    ctx.clip()
    let face = CGGradient(colorsSpace: cs, colors: [color(0x2A2E37), color(0x0E1014)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(face, start: CGPoint(x: 512, y: 734), end: CGPoint(x: 512, y: 290), options: [])
    ctx.restoreGState()

    // Subtle rim highlight on the face.
    ctx.setLineWidth(3)
    ctx.setStrokeColor(color(0xFFFFFF, 0.10))
    ctx.addEllipse(in: CGRect(x: center.x - faceRadius + 1.5, y: center.y - faceRadius + 1.5,
                              width: faceRadius * 2 - 3, height: faceRadius * 2 - 3))
    ctx.strokePath()

    // Setpoint knob on the ring at the warm side.
    let knobAngle: CGFloat = .pi / 5
    let knob = CGPoint(x: center.x + cos(knobAngle) * ringRadius, y: center.y + sin(knobAngle) * ringRadius)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: color(0x000000, 0.45))
    ctx.addEllipse(in: CGRect(x: knob.x - 40, y: knob.y - 40, width: 80, height: 80))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    // Center temperature, drawn with AppKit text.
    let gctx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx
    let font = NSFont.systemFont(ofSize: 196, weight: .light)
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .paragraphStyle: para,
        .kern: -6,
    ]
    let text = NSAttributedString(string: "72", attributes: attrs)
    let textSize = text.size()
    text.draw(in: CGRect(x: 512 - 220, y: 512 - textSize.height / 2 + 4, width: 440, height: textSize.height))
    NSGraphicsContext.restoreGraphicsState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1)
    }
    try data.write(to: url)
}

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    try writePNG(drawIcon(size: px), to: iconset.appendingPathComponent("\(name).png"))
}
try writePNG(drawIcon(size: 1024), to: root.appendingPathComponent("build/AppIcon-preview.png"))

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try p.run()
p.waitUntilExit()
guard p.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote Resources/AppIcon.icns")
