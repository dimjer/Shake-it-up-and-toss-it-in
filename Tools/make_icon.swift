// Renders the Toss app icon into an .iconset folder: swift Tools/make_icon.swift <out.iconset>
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let u = s / 1024 // design on a 1024 grid
    let c = NSPoint(x: 512 * u, y: 512 * u)
    let hot = NSColor(srgbRed: 1.0, green: 0.62, blue: 0.22, alpha: 1)
    let amber = NSColor(srgbRed: 1.0, green: 0.82, blue: 0.45, alpha: 1)

    // Background squircle: deep space + soft shadow
    let inset = 100 * u
    let bgRect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: bgRect, xRadius: 185 * u, yRadius: 185 * u)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * u)
    shadow.shadowBlurRadius = 24 * u
    shadow.set()
    NSColor.black.setFill(); bg.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    bg.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.16, green: 0.08, blue: 0.30, alpha: 1),
                        NSColor(srgbRed: 0.03, green: 0.02, blue: 0.08, alpha: 1)])!
        .draw(in: bg, relativeCenterPosition: .zero)

    // A few stars
    var seed: UInt64 = 7
    func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
    for _ in 0..<40 {
        let p = NSPoint(x: (110 + rnd() * 804) * u, y: (110 + rnd() * 804) * u)
        if hypot(p.x - c.x, p.y - c.y) < 330 * u { continue }
        let r = (2 + rnd() * 5) * u
        NSColor.white.withAlphaComponent(0.3 + rnd() * 0.5).setFill()
        NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)).fill()
    }

    // Outer glow
    NSGradient(colors: [hot.withAlphaComponent(0.55), hot.withAlphaComponent(0.0)])!
        .draw(fromCenter: c, radius: 150 * u, toCenter: c, radius: 400 * u, options: [])

    // Tilted accretion disk (back half is hidden behind the hole, front half drawn after)
    func disk(front: Bool) {
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(rect: front ? NSRect(x: 0, y: 0, width: s, height: c.y)
                                            : NSRect(x: 0, y: c.y, width: s, height: s - c.y))
        clip.addClip()
        let t = NSAffineTransform()
        t.translateX(by: c.x, yBy: c.y)
        t.rotate(byDegrees: -12)
        t.concat()
        for (w, a) in [(70.0, 0.35), (40.0, 0.7), (16.0, 1.0)] as [(CGFloat, CGFloat)] {
            let ring = NSBezierPath(ovalIn: NSRect(x: -340 * u, y: -95 * u, width: 680 * u, height: 190 * u))
            ring.lineWidth = w * u
            (w < 20 ? amber : hot).withAlphaComponent(a).setStroke()
            ring.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    disk(front: false)

    // Lensed back of the disk: a glowing halo hugging the hole
    let R = 190 * u
    for (dr, w, a) in [(70.0, 90.0, 0.25), (48.0, 50.0, 0.55), (34.0, 22.0, 0.9)] as [(CGFloat, CGFloat, CGFloat)] {
        let halo = NSBezierPath(ovalIn: NSRect(x: c.x - R - dr * u, y: c.y - R - dr * u,
                                               width: 2 * (R + dr * u), height: 2 * (R + dr * u)))
        halo.lineWidth = w * u
        (w < 30 ? amber : hot).withAlphaComponent(a).setStroke()
        halo.stroke()
    }

    // Photon ring + event horizon
    let photon = NSBezierPath(ovalIn: NSRect(x: c.x - R - 14 * u, y: c.y - R - 14 * u, width: 2 * (R + 14 * u), height: 2 * (R + 14 * u)))
    photon.lineWidth = 22 * u
    amber.setStroke(); photon.stroke()
    NSColor.black.setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R)).fill()

    disk(front: true)

    // Down arrow inside the hole
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 512 * u, y: 395 * u))          // tip
    arrow.line(to: NSPoint(x: 420 * u, y: 495 * u))
    arrow.line(to: NSPoint(x: 476 * u, y: 495 * u))
    arrow.line(to: NSPoint(x: 476 * u, y: 625 * u))
    arrow.line(to: NSPoint(x: 548 * u, y: 625 * u))
    arrow.line(to: NSPoint(x: 548 * u, y: 495 * u))
    arrow.line(to: NSPoint(x: 604 * u, y: 495 * u))
    arrow.close()
    arrow.lineJoinStyle = .round
    arrow.lineWidth = 14 * u
    let glow = NSShadow()
    glow.shadowColor = hot
    glow.shadowOffset = .zero
    glow.shadowBlurRadius = 30 * u
    glow.set()
    amber.setStroke(); amber.setFill()
    arrow.stroke(); arrow.fill()

    NSGraphicsContext.restoreGraphicsState() // bg clip
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
