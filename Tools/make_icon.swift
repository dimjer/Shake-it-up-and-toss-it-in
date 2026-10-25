// Renders the Toss app icon into an .iconset folder: swift Tools/make_icon.swift <out.iconset>
// Three pixel kittens in an oval wicker basket seen from above, on a soft pink squircle.
import AppKit

func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

// Same top-down sprite as the app (Sources/main.swift, `Kitten.sprite`).
let kitten = [
    "...O.....O....",
    "..OBO...OBO...",
    "..OBBOOOBBO...",
    ".OBBBBBBBBBO..",
    ".OBBEBBBEBBO..",
    ".OBBBBNBBBBO..",
    "..OBBBBBBBO...",
    "..OSBBBBBSO...",
    ".OBBBBBBBBBO..",
    "OBBBBBBBBBBBO.",
    "OBBBBBBBBBBBO.",
    "OBBBBBBBBBBBO.",
    ".OBBBBBBBBBO..",
    "..OBBBBBBBOOO.",
    "...OOOOOOOBBBO",
    "..........OOO.",
].map(Array.init)

/// Draws pixels on a 64×64 grid (top-left origin) scaled to the icon size.
func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let u = s / 64
    func dot(_ x: Int, _ y: Int, _ c: NSColor) {
        c.setFill()
        NSRect(x: CGFloat(x) * u, y: s - CGFloat(y + 1) * u, width: u, height: u).fill()
    }

    // Background squircle
    let inset = s * 100 / 1024
    let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset),
                          xRadius: s * 185 / 1024, yRadius: s * 185 / 1024)
    NSGradient(colors: [rgb(0xFFE3EC), rgb(0xF7B9CC)])!.draw(in: bg, angle: -90)

    // Oval basket from above (same shape as `Basket` in the app, smaller): rim, cushion, front wall.
    let c = (x: 32.0, y: 29.0), outer = (rx: 27.0, ry: 20.0), inner = (rx: 23.0, ry: 16.0), wall = 4.0
    func norm(_ x: Int, _ y: Int, _ r: (rx: Double, ry: Double)) -> Double {
        let dx = (Double(x) + 0.5 - c.x) / r.rx, dy = (Double(y) + 0.5 - c.y) / r.ry
        return dx * dx + dy * dy
    }
    func inShape(_ x: Int, _ y: Int) -> Bool {
        if norm(x, y, outer) <= 1 { return true }
        let dx = (Double(x) + 0.5 - c.x) / outer.rx
        guard abs(dx) <= 1, Double(y) + 0.5 > c.y else { return false }
        return Double(y) + 0.5 - c.y <= outer.ry * (1 - dx * dx).squareRoot() + wall
    }
    for y in 0..<64 {
        for x in 0..<64 where inShape(x, y) {
            let edge = !inShape(x - 1, y) || !inShape(x + 1, y) || !inShape(x, y - 1) || !inShape(x, y + 1)
            let o = norm(x, y, outer), i = norm(x, y, inner)
            let a = atan2((Double(y) + 0.5 - c.y) / outer.ry, (Double(x) + 0.5 - c.x) / outer.rx)
            let col: UInt32 = edge ? 0x5A3A22
                : o > 1 ? ((x / 2 + y % 2) % 2 == 0 ? 0xB97D3F : 0x9A6532)
                : i > 1 ? (i <= 1.12 ? 0x5A3A22 : Int((a + .pi) / (2 * .pi) * 40) % 2 == 0 ? 0xE7B977 : 0xC98F4E)
                : i > 0.8 ? 0xDFA0B2 : 0xF6C9D3
            dot(x, y, rgb(col))
        }
    }

    // Kittens on the cushion: ginger, tuxedo, grey tabby
    let coats: [(body: UInt32, paws: UInt32, eye: UInt32)] = [(0xF2A65A, 0xFFE3C2, 0x6FBF5F),
                                                              (0x34313A, 0xF5F1EA, 0xF2D45C),
                                                              (0x9CA3AD, 0xDADEE3, 0xF2C14E)]
    let spots = [(x: 13, y: 15), (x: 26, y: 23), (x: 39, y: 15)]
    for (coat, at) in zip(coats, spots) {
        for (y, row) in kitten.enumerated() {
            for (x, ch) in row.enumerated() {
                let col: UInt32
                switch ch {
                case "O": col = 0x2B1C19
                case "E": col = coat.eye
                case "N": col = 0xFF8FA3
                case "S": col = coat.paws
                case "B": col = coat.body
                default: continue
                }
                dot(at.x + x, at.y + y, rgb(col))
            }
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
