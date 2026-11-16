// Generates the app icon programmatically.
//
//   swift scripts/make-icon.swift Support/AppIcon.icns [preview.png]
//
// Draws every size natively (not by downscaling) on Apple's macOS icon grid:
// an 824×824 rounded square ("squircle") centred in a 1024×1024 canvas, with a
// soft drop shadow. Motif: a calm charcoal tile with an amber speed gauge.
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: make-icon.swift <out.icns> [preview.png]\n".data(using: .utf8)!)
    exit(2)
}
let outICNS = URL(fileURLWithPath: args[1])
let previewPNG = args.count >= 3 ? URL(fileURLWithPath: args[2]) : nil

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

/// Apple-style continuous-corner rounded rect (approximation of the squircle).
func squircle(_ r: CGRect, radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let k: CGFloat = 1.18 // a little longer than a circular corner: smoother, squircle-like shoulder
    let c = min(radius * k, min(r.width, r.height) / 2)
    let (minX, minY, maxX, maxY) = (r.minX, r.minY, r.maxX, r.maxY)
    p.move(to: CGPoint(x: minX + c, y: minY))
    p.addLine(to: CGPoint(x: maxX - c, y: minY))
    p.addCurve(to: CGPoint(x: maxX, y: minY + c), control1: CGPoint(x: maxX - c * 0.42, y: minY), control2: CGPoint(x: maxX, y: minY + c * 0.42))
    p.addLine(to: CGPoint(x: maxX, y: maxY - c))
    p.addCurve(to: CGPoint(x: maxX - c, y: maxY), control1: CGPoint(x: maxX, y: maxY - c * 0.42), control2: CGPoint(x: maxX - c * 0.42, y: maxY))
    p.addLine(to: CGPoint(x: minX + c, y: maxY))
    p.addCurve(to: CGPoint(x: minX, y: maxY - c), control1: CGPoint(x: minX + c * 0.42, y: maxY), control2: CGPoint(x: minX, y: maxY - c * 0.42))
    p.addLine(to: CGPoint(x: minX, y: minY + c))
    p.addCurve(to: CGPoint(x: minX + c, y: minY), control1: CGPoint(x: minX, y: minY + c * 0.42), control2: CGPoint(x: minX + c * 0.42, y: minY))
    p.closeSubpath()
    return p
}

func point(_ c: CGPoint, _ r: CGFloat, _ deg: CGFloat) -> CGPoint {
    let a = deg * .pi / 180
    return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
}

/// Draws the icon into a square bitmap of `px` pixels. All geometry is in 1024-unit space.
func render(px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    let g = ctx.cgContext
    let s = CGFloat(px) / 1024
    g.scaleBy(x: s, y: s)
    g.setShouldAntialias(true)
    g.interpolationQuality = .high

    let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tile = squircle(tileRect, radius: 185)
    let small = px <= 32

    // Shadow (part of the macOS grid; lighter at tiny sizes so it doesn't smudge).
    g.saveGState()
    g.setShadow(offset: CGSize(width: 0, height: -12), blur: small ? 10 : 28, color: rgb(0x000000, small ? 0.22 : 0.32))
    g.addPath(tile)
    g.setFillColor(rgb(0x202124))
    g.fillPath()
    g.restoreGState()

    // Background: quiet charcoal gradient.
    g.saveGState()
    g.addPath(tile)
    g.clip()
    let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                        colors: [rgb(0x34353A), rgb(0x1D1E21)] as CFArray, locations: [0, 1])!
    g.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Soft top sheen.
    let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [rgb(0xFFFFFF, 0.07), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    g.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 600), options: [])
    g.restoreGState()

    // Hairline edge highlight.
    if !small {
        g.saveGState()
        g.addPath(squircle(tileRect.insetBy(dx: 1.5, dy: 1.5), radius: 183.5))
        g.setStrokeColor(rgb(0xFFFFFF, 0.10))
        g.setLineWidth(3)
        g.strokePath()
        g.restoreGState()
    }

    // Gauge.
    let showText = px >= 128
    let center = CGPoint(x: 512, y: showText ? 540 : 480)
    let radius: CGFloat = showText ? 232 : 262
    let width: CGFloat = small ? 92 : 62
    let start: CGFloat = 210, end: CGFloat = -30, value: CGFloat = 0.68
    let needleAngle = start - (start - end) * value

    g.setLineCap(.round)
    g.setLineWidth(width)
    // Track
    g.addArc(center: center, radius: radius, startAngle: start * .pi / 180, endAngle: end * .pi / 180, clockwise: true)
    g.setStrokeColor(rgb(0xFFFFFF, 0.10))
    g.strokePath()
    // Progress, amber gradient along the arc
    g.saveGState()
    g.addArc(center: center, radius: radius, startAngle: start * .pi / 180, endAngle: needleAngle * .pi / 180, clockwise: true)
    g.replacePathWithStrokedPath()
    g.clip()
    let amber = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [rgb(0xD98A2B), rgb(0xF6C56E)] as CFArray, locations: [0, 1])!
    g.drawLinearGradient(amber, start: CGPoint(x: center.x - radius, y: center.y - radius / 2),
                         end: CGPoint(x: center.x + radius, y: center.y + radius),
                         options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    g.restoreGState()

    // Tick dots inside the arc.
    if !small {
        for i in 0...4 {
            let a = start - (start - end) * CGFloat(i) / 4
            let p = point(center, radius - width / 2 - 46, a)
            g.setFillColor(rgb(0xFFFFFF, 0.22))
            g.fillEllipse(in: CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22))
        }
    }

    // Needle + hub.
    let tip = point(center, radius - (small ? 40 : 62), needleAngle)
    g.setLineWidth(small ? 44 : 28)
    g.setStrokeColor(rgb(0xEFE9DD))
    g.move(to: center)
    g.addLine(to: tip)
    g.strokePath()
    let hubR: CGFloat = small ? 58 : 44
    g.setFillColor(rgb(0xEFE9DD))
    g.fillEllipse(in: CGRect(x: center.x - hubR, y: center.y - hubR, width: 2 * hubR, height: 2 * hubR))
    if !small {
        g.setFillColor(rgb(0x26272B))
        g.fillEllipse(in: CGRect(x: center.x - 15, y: center.y - 15, width: 30, height: 30))
    }

    // Wordmark.
    if showText {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let font = NSFont.monospacedSystemFont(ofSize: 112, weight: .regular)
        let text = NSAttributedString(string: "wpm", attributes: [
            .font: font, .foregroundColor: NSColor(cgColor: rgb(0xF2B95E, 0.92))!, .kern: 4,
        ])
        let sz = text.size()
        text.draw(at: CGPoint(x: 512 - sz.width / 2, y: 196))
        NSGraphicsContext.restoreGraphicsState()
    }

    ctx.flushGraphics()
    return rep
}

// Build the .iconset and convert with iconutil.
let fm = FileManager.default
let work = fm.temporaryDirectory.appendingPathComponent("wpm-icon-\(getpid())")
let iconset = work.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: work)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: work) }

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try render(px: px).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
if let previewPNG {
    try render(px: 1024).representation(using: .png, properties: [:])!.write(to: previewPNG)
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", outICNS.path]
try p.run()
p.waitUntilExit()
guard p.terminationStatus == 0 else { exit(p.terminationStatus) }
print("Wrote \(outICNS.path)")
