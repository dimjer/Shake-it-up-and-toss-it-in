// Style "Kittens": a wicker basket seen from above; every file becomes a pixel kitten
// (coat = file type). Up to four sit in the basket, the rest gather around it.

import Cocoa

// MARK: - Pixel art: kittens and the basket, seen from above

/// Every kind of file gets its own kitten coat.
struct Coat {
    var name: String
    var body: NSColor
    var paws: NSColor
    var eye: NSColor
    var outline = rgb(0x2B1C19)
    var stripes: NSColor? = nil
    var points: NSColor? = nil      // siamese: ears, mask and tail
    var patches: [NSColor] = []     // calico: [ginger, black]

    static let ginger    = Coat(name: "ginger tabby · image", body: rgb(0xF2A65A), paws: rgb(0xFFE3C2), eye: rgb(0x6FBF5F), stripes: rgb(0xD0702A))
    static let tuxedo    = Coat(name: "tuxedo · PDF", body: rgb(0x34313A), paws: rgb(0xF5F1EA), eye: rgb(0xF2D45C), outline: rgb(0x121015))
    static let snowy     = Coat(name: "snow white · text", body: rgb(0xF7F4EE), paws: rgb(0xFBE4EA), eye: rgb(0x5FA8E0), outline: rgb(0x5E514B))
    static let greyTabby = Coat(name: "grey tabby · code", body: rgb(0x9CA3AD), paws: rgb(0xDADEE3), eye: rgb(0xF2C14E), stripes: rgb(0x5D646E))
    static let siamese   = Coat(name: "siamese · video", body: rgb(0xF3E3C7), paws: rgb(0xFBF2E2), eye: rgb(0x4F9FE6), points: rgb(0x6B4A3A))
    static let calico    = Coat(name: "calico · music", body: rgb(0xFBF7F0), paws: rgb(0xFFFFFF), eye: rgb(0x6FBF5F), patches: [rgb(0xE8913A), rgb(0x3A3437)])
    static let chocolate = Coat(name: "chocolate · archive", body: rgb(0x8A5A3C), paws: rgb(0xC9A07E), eye: rgb(0xF2C14E), stripes: rgb(0x6A4129))
    static let blue      = Coat(name: "russian blue · folder", body: rgb(0x7F8FA6), paws: rgb(0xAAB7C9), eye: rgb(0x63C463))
    static let pink      = Coat(name: "pink · design", body: rgb(0xF4A7C0), paws: rgb(0xFFE0EA), eye: rgb(0x9B7BE0))
    static let cream     = Coat(name: "cream · other", body: rgb(0xE9D3A8), paws: rgb(0xF8EBD2), eye: rgb(0x6FBF5F))

    static func forFile(_ url: URL) -> Coat {
        let ext = url.pathExtension.lowercased()
        var isDir: ObjCBool = false
        if ext.isEmpty, FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return blue
        }
        switch ext {
        case "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tif", "tiff", "bmp", "svg", "ico", "avif", "raw":
            return ginger
        case "pdf":
            return tuxedo
        case "txt", "md", "markdown", "rtf", "doc", "docx", "pages", "odt", "csv", "xls", "xlsx", "numbers", "key", "ppt", "pptx":
            return snowy
        case "swift", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "c", "h", "cpp", "m", "java", "kt", "json",
             "yaml", "yml", "toml", "xml", "html", "css", "scss", "sh", "zsh", "sql", "php", "log":
            return greyTabby
        case "mov", "mp4", "m4v", "avi", "mkv", "webm":
            return siamese
        case "mp3", "wav", "m4a", "aiff", "aif", "flac", "ogg", "aac":
            return calico
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "dmg", "pkg":
            return chocolate
        case "fig", "sketch", "psd", "ai", "xd", "indd", "afdesign", "eps":
            return pink
        default:
            return cream
        }
    }

    private static let nose = rgb(0xFF8FA3)

    func color(_ ch: Character, _ x: Int, _ y: Int, blink: Bool) -> NSColor? {
        switch ch {
        case "O": return outline
        case "E": return blink ? outline : eye
        case "N": return Self.nose
        case "S": return paws
        case "B":
            if let p = points, y <= 2 || y >= 13 || (y == 5 && (3...9).contains(x)) || (y == 4 && x == 6) { return p }
            if patches.count == 2 {
                if (x <= 5 && (8...12).contains(y)) || (x <= 4 && y <= 2) { return patches[0] }
                if (x >= 8 && (9...11).contains(y)) || y >= 14 { return patches[1] }
            }
            if let s = stripes, (y == 3 && (x == 5 || x == 7)) || ((y == 9 || y == 11) && (3...9).contains(x)) || (y == 14 && x == 11) {
                return s
            }
            return body
        default: return nil
        }
    }
}

enum Kitten {
    /// Top-down: head with ears up top, back below, tail curling off to the right.
    static let sprite = [
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
    static let cols = 14, rows = 16

    private static var images: [String: NSImage] = [:]
    private static var shadowed: [String: CGImage] = [:]

    /// Crisp at any scale: every sprite pixel is drawn as a `px`-point square. Cached per coat and size.
    static func image(_ coat: Coat, px: CGFloat, blink: Bool = false) -> NSImage {
        let key = "\(coat.name)|\(px)|\(blink)"
        if let img = images[key] { return img }
        let img = NSImage(size: NSSize(width: CGFloat(cols) * px, height: CGFloat(rows) * px), flipped: true) { _ in
            for (y, row) in sprite.enumerated() {
                for (x, ch) in row.enumerated() {
                    guard let c = coat.color(ch, x, y, blink: blink) else { continue }
                    c.setFill()
                    NSRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px).fill()
                }
            }
            return true
        }
        images[key] = img
        return img
    }

    /// Room around a shadowed sprite for the soft drop shadow.
    static let shadowMargin: CGFloat = 4

    /// The sprite with its drop shadow baked in, so hopping kittens don't make
    /// Core Animation re-render a live layer shadow every frame.
    static func shadowedImage(_ coat: Coat, px: CGFloat, blink: Bool = false) -> CGImage? {
        let key = "\(coat.name)|\(px)|\(blink)"
        if let cg = shadowed[key] { return cg }
        let sprite = image(coat, px: px, blink: blink)
        let m = shadowMargin
        let size = NSSize(width: sprite.size.width + 2 * m, height: sprite.size.height + 2 * m)
        let cg = NSImage(size: size, flipped: false) { _ in
            let sh = NSShadow()
            sh.shadowColor = NSColor.black.withAlphaComponent(0.3)
            sh.shadowBlurRadius = 3
            sh.shadowOffset = NSSize(width: 1, height: -2)
            sh.set()
            sprite.draw(in: NSRect(origin: NSPoint(x: m, y: m), size: sprite.size))
            return true
        }.cg
        shadowed[key] = cg
        return cg
    }
}

/// An oval wicker basket seen from above: braided rim, cushion inside, a strip of front wall below.
enum Basket {
    static let cols = 76, rows = 63
    static let center = (x: 38.0, y: 28.0)
    static let outer = (rx: 38.0, ry: 28.0)
    static let inner = (rx: 33.0, ry: 23.0)    // cushion
    static let wall = 6.0                       // rows of front wall visible under the rim
    /// The free cushion area kittens sit on (a bit inside the cushion edge).
    static let seat = (rx: 31.0, ry: 21.0)

    private static func norm(_ x: Int, _ y: Int, _ r: (rx: Double, ry: Double)) -> Double {
        let dx = (Double(x) + 0.5 - center.x) / r.rx, dy = (Double(y) + 0.5 - center.y) / r.ry
        return dx * dx + dy * dy
    }

    private static func inShape(_ x: Int, _ y: Int) -> Bool {
        guard x >= 0, x < cols, y >= 0, y < rows else { return false }
        if norm(x, y, outer) <= 1 { return true }
        // Front wall: the rim's lower edge pushed down by `wall` rows.
        let dx = (Double(x) + 0.5 - center.x) / outer.rx
        guard abs(dx) <= 1, Double(y) + 0.5 > center.y else { return false }
        return Double(y) + 0.5 - center.y <= outer.ry * (1 - dx * dx).squareRoot() + wall
    }

    static func contains(gridX x: Int, gridY y: Int) -> Bool { inShape(x, y) }

    static func image(px: CGFloat) -> NSImage {
        let outline = rgb(0x5A3A22)
        let rimA = rgb(0xE7B977), rimB = rgb(0xC98F4E)
        let wallA = rgb(0xB97D3F), wallB = rgb(0x9A6532)
        let cushion = rgb(0xF6C9D3), cushionDot = rgb(0xEBAFBF), cushionShade = rgb(0xDFA0B2)
        return NSImage(size: NSSize(width: CGFloat(cols) * px, height: CGFloat(rows) * px), flipped: true) { _ in
            for y in 0..<rows {
                for x in 0..<cols where inShape(x, y) {
                    let edge = !inShape(x - 1, y) || !inShape(x + 1, y) || !inShape(x, y - 1) || !inShape(x, y + 1)
                    let o = norm(x, y, outer), i = norm(x, y, inner)
                    let c: NSColor
                    if edge {
                        c = outline
                    } else if o > 1 {
                        c = (x / 2 + (y % 2)) % 2 == 0 ? wallA : wallB          // woven front wall
                    } else if i > 1 {
                        // Braided rim: alternating segments around the oval, outlined on the inside.
                        if i <= 1.09 { c = outline }
                        else {
                            let a = atan2((Double(y) + 0.5 - center.y) / outer.ry, (Double(x) + 0.5 - center.x) / outer.rx)
                            c = Int((a + .pi) / (2 * .pi) * 56) % 2 == 0 ? rimA : rimB
                        }
                    } else if i > 0.82 {
                        c = cushionShade                                        // shadow under the rim
                    } else {
                        c = x % 6 == 0 && y % 4 == 0 ? cushionDot : cushion     // quilted cushion
                    }
                    c.setFill()
                    NSRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px).fill()
                }
            }
            return true
        }
    }
}

// MARK: - Kittens (one per file) and the basket (drag it to take everyone)

/// A file as a pixel kitten: coat by file type, name below.
final class KittenTile: FileDragSource {
    static let labelH: CGFloat = 14
    let spriteH: CGFloat
    private let art = CALayer()

    init(url: URL, px: CGFloat, width: CGFloat) {
        let coat = Coat.forFile(url)
        let img = Kitten.image(coat, px: px)
        spriteH = img.size.height
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: spriteH + Self.labelH))
        urls = [url]
        dragImage = img
        toolTip = "\(url.lastPathComponent)\n\(coat.name)"
        wantsLayer = true

        let m = Kitten.shadowMargin
        art.frame = CGRect(x: (width - img.size.width) / 2, y: Self.labelH, width: img.size.width, height: spriteH)
            .insetBy(dx: -m, dy: -m)
        art.contents = Kitten.shadowedImage(coat, px: px)
        art.magnificationFilter = .nearest
        layer?.addSublayer(art)

        let name = NSTextField(labelWithString: url.lastPathComponent)
        name.font = .monospacedSystemFont(ofSize: 8.5, weight: .medium)
        name.textColor = rgb(0xFFF3DC)
        name.alignment = .center
        name.lineBreakMode = .byTruncatingMiddle
        name.cell?.truncatesLastVisibleLine = true
        // Dark pill behind the name so it reads on the cushion.
        let textW = min(width, ceil(name.intrinsicContentSize.width) + 8)
        name.frame = NSRect(x: (width - textW) / 2, y: 0, width: textW, height: Self.labelH - 1)
        name.wantsLayer = true
        name.layer?.backgroundColor = rgb(0x3A2618, 0.85).cgColor
        name.layer?.cornerRadius = (Self.labelH - 1) / 2
        addSubview(name)

        idle(coat: coat, px: px)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Each kitten breathes, hops and blinks on its own rhythm.
    private func idle(coat: Coat, px: CGFloat) {
        let now = CACurrentMediaTime()
        let hop = CAKeyframeAnimation(keyPath: "transform.translation.y")
        hop.values = [0, 0, px, 0, 0]
        hop.keyTimes = [0, 0.75, 0.82, 0.9, 1]
        hop.duration = .random(in: 2.2...3.8)
        hop.repeatCount = .infinity
        hop.beginTime = now + .random(in: 0...2)
        art.add(hop, forKey: "hop")

        guard let open = Kitten.shadowedImage(coat, px: px),
              let shut = Kitten.shadowedImage(coat, px: px, blink: true) else { return }
        let blink = CAKeyframeAnimation(keyPath: "contents")
        blink.values = [open, shut, open]
        blink.keyTimes = [0, 0.94, 0.97]
        blink.calculationMode = .discrete
        blink.duration = .random(in: 3...5.5)
        blink.repeatCount = .infinity
        blink.beginTime = now + .random(in: 0...3)
        art.add(blink, forKey: "blink")
    }
}

/// The basket: drag from it (anywhere not covered by a kitten) to take every kitten at once.
final class BasketCore: FileDragSource {
    static let px: CGFloat = 4
    private let art = CALayer()
    private let hint = NSTextField(labelWithString: "")
    private let countTag = NSTextField(labelWithString: "")

    /// Cushion centre and the radii kittens may use, in this view's coordinates.
    var seatCenter: CGPoint {
        CGPoint(x: CGFloat(Basket.center.x) * Self.px, y: bounds.height - CGFloat(Basket.center.y) * Self.px)
    }
    var seatRadii: CGSize { CGSize(width: Basket.seat.rx * Self.px, height: Basket.seat.ry * Self.px) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Drawn one point per pixel (76×63) and scaled up by the layer: same look, a fraction of the memory.
        art.contents = Basket.image(px: 1).cg
        art.magnificationFilter = .nearest
        art.frame = bounds
        art.shadowColor = rgb(0xFF9EB5).cgColor
        art.shadowOffset = .zero
        art.shadowRadius = 0
        art.shadowOpacity = 0      // only glows while a drag hovers; a hidden shadow still costs a render pass
        layer?.addSublayer(art)

        // Hint on the empty cushion.
        hint.alignment = .center
        hint.attributedStringValue = {
            let s = NSMutableAttributedString(string: "meow\n", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold), .foregroundColor: rgb(0xB0687E)])
            s.append(NSAttributedString(string: "drop here", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .medium), .foregroundColor: rgb(0xB0687E, 0.75)]))
            return s
        }()
        hint.sizeToFit()
        hint.setFrameOrigin(NSPoint(x: seatCenter.x - hint.frame.width / 2, y: seatCenter.y - hint.frame.height / 2))
        addSubview(hint)

        // Count tag on the front wall.
        countTag.alignment = .center
        countTag.wantsLayer = true
        countTag.layer?.backgroundColor = rgb(0x3A2618, 0.9).cgColor
        countTag.layer?.cornerRadius = 8
        addSubview(countTag)
        update(count: 0)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(count: Int) {
        hint.isHidden = count > 0
        countTag.isHidden = count == 0
        toolTip = count == 0 ? nil : "Drag the basket to take all \(count) kittens"
        countTag.attributedStringValue = NSAttributedString(string: "\(count) kitten\(count == 1 ? "" : "s") · drag the basket to take all", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 8.5, weight: .semibold), .foregroundColor: rgb(0xFFF3DC)])
        let w = ceil(countTag.intrinsicContentSize.width) + 16
        countTag.frame = NSRect(x: (bounds.width - w) / 2, y: 2, width: w, height: 16)
    }

    // Only the basket itself is grabbable, not the transparent corners.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        let gx = Int(p.x / Self.px), gy = Int((bounds.height - p.y) / Self.px)
        return Basket.contains(gridX: gx, gridY: gy) ? self : nil
    }

    /// A drag hovering over the window: the basket perks up.
    func setHungry(_ on: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        art.setValue(on ? 1.03 : 1.0, forKeyPath: "transform.scale")
        art.shadowRadius = on ? 16 : 0
        art.shadowOpacity = on ? 0.9 : 0
        CATransaction.commit()
    }

    /// Wobble when kittens land.
    func bounce() {
        let a = CAKeyframeAnimation(keyPath: "transform")
        a.values = [CATransform3DIdentity, CATransform3DMakeScale(1.04, 0.95, 1),
                    CATransform3DMakeScale(0.98, 1.02, 1), CATransform3DIdentity].map { NSValue(caTransform3D: $0) }
        a.duration = 0.4
        art.add(a, forKey: "bounce")
    }
}


// MARK: - The basket panel

final class BasketPanel: ShelfPanel {
    /// This many kittens fit on the cushion; the rest sit around the basket.
    static let insideMax = 4
    static let px: CGFloat = 3
    static let tileW: CGFloat = 60
    static var tileH: CGFloat { CGFloat(Kitten.rows) * px + KittenTile.labelH }
    /// The ellipse kittens past `insideMax` sit on, around the basket's middle.
    private static let ring = CGSize(width: 205, height: 172)

    private let basket: BasketCore
    private var tiles: [URL: KittenTile] = [:]
    private lazy var ringSeats: [CGPoint] = makeRingSeats()

    init() {
        let size = NSSize(width: 480, height: 380)
        let bw = CGFloat(Basket.cols) * BasketCore.px, bh = CGFloat(Basket.rows) * BasketCore.px
        basket = BasketCore(frame: NSRect(x: (size.width - bw) / 2, y: 44, width: bw, height: bh))
        super.init(size: size)
        root.addSubview(basket)
        basket.layer?.zPosition = -10_000
        addControlBar(tint: rgb(0xFFF3DC, 0.85), background: rgb(0x3A2618, 0.85))
    }

    // MARK: Kittens

    override func reload() {
        let items = Store.shared.items
        basket.urls = items
        basket.dragImage = items.count == 1 ? tiles[items[0]]?.dragImage : nil
        basket.update(count: items.count)

        for (url, t) in tiles where !items.contains(url) {
            t.removeFromSuperview()
            tiles[url] = nil
        }
        for url in items where tiles[url] == nil {
            let t = KittenTile(url: url, px: Self.px, width: Self.tileW)
            root.addSubview(t, positioned: .above, relativeTo: basket)
            t.setFrameOrigin(origin(of: items.firstIndex(of: url)!, count: items.count))
            tiles[url] = t
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            for (i, url) in items.enumerated() {
                guard let t = tiles[url] else { continue }
                let o = origin(of: i, count: items.count)
                t.animator().setFrameOrigin(o)
                t.layer?.zPosition = -o.y    // top-down: lower kittens are drawn over higher ones
            }
        }
    }

    /// Spots around the basket: straight behind it first, then alternating left and right
    /// down both sides. The strip below the basket stays free for the buttons.
    private func makeRingSeats() -> [CGPoint] {
        let c = CGPoint(x: basket.frame.midX, y: basket.frame.midY)
        let step = CGFloat.pi / 9      // 20°
        var out: [CGPoint] = []
        for k in 0...6 {
            for sign: CGFloat in k == 0 ? [1] : [-1, 1] {
                let a = CGFloat.pi / 2 + sign * CGFloat(k) * step
                out.append(CGPoint(x: c.x + Self.ring.width * cos(a), y: c.y + Self.ring.height * sin(a)))
            }
        }
        return out
    }

    /// Centre of the i-th kitten when `count` kittens are in play.
    private func seat(of i: Int, count: Int) -> CGPoint {
        if i < Self.insideMax {
            let c = CGPoint(x: basket.frame.minX + basket.seatCenter.x, y: basket.frame.minY + basket.seatCenter.y)
            let dx: CGFloat = 34, dy: CGFloat = 33
            let offsets: [CGPoint]
            switch min(count, Self.insideMax) {
            case 1: offsets = [.zero]
            case 2: offsets = [CGPoint(x: -dx, y: 0), CGPoint(x: dx, y: 0)]
            case 3: offsets = [CGPoint(x: 0, y: dy), CGPoint(x: -dx, y: -dy), CGPoint(x: dx, y: -dy)]
            default: offsets = [CGPoint(x: -dx, y: dy), CGPoint(x: dx, y: dy), CGPoint(x: -dx, y: -dy), CGPoint(x: dx, y: -dy)]
            }
            return CGPoint(x: c.x + offsets[i].x, y: c.y + offsets[i].y)
        }
        // Past the ring's capacity, kittens pile on top of each other.
        let j = i - Self.insideMax
        let layer = CGFloat(j / ringSeats.count)
        let p = ringSeats[j % ringSeats.count]
        return CGPoint(x: p.x + layer * 6, y: p.y - layer * 6)
    }

    /// Bottom-left corner of the i-th kitten tile.
    private func origin(of i: Int, count: Int) -> NSPoint {
        let p = seat(of: i, count: count)
        return NSPoint(x: p.x - Self.tileW / 2, y: p.y - Self.tileH / 2)
    }

    // MARK: Jump-in animation

    override func setHungry(_ on: Bool) { basket.setHungry(on) }

    override func didDrop(_ urls: [URL], at point: NSPoint) {
        basket.bounce()
        let items = Store.shared.items
        for (k, url) in urls.prefix(10).enumerated() {
            guard let tile = tiles[url], let i = items.firstIndex(of: url) else { continue }
            tile.alphaValue = 0
            let o = origin(of: i, count: items.count)
            let end = CGPoint(x: o.x + Self.tileW / 2, y: o.y + KittenTile.labelH + tile.spriteH / 2)
            let start = CGPoint(x: point.x + CGFloat(k) * 12, y: point.y - CGFloat(k) * 6)

            let ghost = CALayer()
            ghost.contents = tile.dragImage?.cg
            ghost.magnificationFilter = .nearest
            ghost.bounds = CGRect(origin: .zero, size: tile.dragImage?.size ?? .zero)
            ghost.position = end
            ghost.opacity = 0
            root.layer?.addSublayer(ghost)
            ghost.zPosition = 9_000

            // A hop: up over the rim, then down into place.
            let path = CGMutablePath()
            path.move(to: start)
            path.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + 90))
            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = path
            let squash = CAKeyframeAnimation(keyPath: "transform")
            squash.values = [CATransform3DMakeScale(0.9, 1.1, 1), CATransform3DIdentity,
                             CATransform3DMakeScale(1.15, 0.85, 1), CATransform3DIdentity].map { NSValue(caTransform3D: $0) }
            squash.keyTimes = [0, 0.5, 0.9, 1]
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1]
            fade.keyTimes = [0, 0.1, 1]
            let group = CAAnimationGroup()
            group.animations = [move, squash, fade]
            group.duration = 0.55
            group.beginTime = CACurrentMediaTime() + Double(k) * 0.09
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            group.fillMode = .backwards
            ghost.add(group, forKey: "jump")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55 + Double(k) * 0.09) {
                ghost.removeFromSuperlayer()
                tile.alphaValue = 1
            }
        }
        for url in urls.dropFirst(10) { tiles[url]?.alphaValue = 1 }
    }
}
