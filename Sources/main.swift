// Toss — shake the mouse, a kitten basket pops up, drop files on it: every file
// becomes a pixel kitten (coat = file type). Drag kittens into the terminal (or anywhere else).
// Dropped files are COPIED into a persistent stash, so screenshots that macOS
// deletes from its temp location stay available.

import Cocoa
import ServiceManagement
import QuickLookThumbnailing

// MARK: - Settings

enum Settings {
    static let d: UserDefaults = {
        UserDefaults.standard.register(defaults: ["shakeWithoutDrag": true])
        return UserDefaults.standard
    }()
    static var shakeWithoutDrag: Bool {
        get { d.bool(forKey: "shakeWithoutDrag") }
        set { d.set(newValue, forKey: "shakeWithoutDrag") }
    }
}

// MARK: - Stash (where dropped files live)

final class Store {
    static let shared = Store()

    let dir: URL = {
        // ~/.toss: no spaces in paths, and allowed in Claude Code's additionalDirectories.
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".toss", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private(set) var items: [URL] = []
    var onChange: (() -> Void)?

    /// Copies files into the stash and adds the copies to the shelf.
    func add(copying urls: [URL]) {
        for src in urls {
            // Already in the stash (e.g. dragged back in) — just re-add.
            if src.standardizedFileURL.path.hasPrefix(dir.standardizedFileURL.path) {
                append(src); continue
            }
            let dst = uniqueURL(for: src.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: src, to: dst)
                append(dst)
            } catch {
                NSLog("Toss: copy failed for \(src.path): \(error)")
            }
        }
    }

    /// Adds a file that is already inside the stash.
    func add(stored url: URL) { append(url) }

    func save(data: Data, name: String) {
        let dst = uniqueURL(for: name)
        if (try? data.write(to: dst)) != nil { append(dst) }
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        onChange?()
    }

    /// Removes items from the shelf. Files stay on disk until the next launch.
    func clear() {
        items.removeAll()
        onChange?()
    }

    func uniqueURL(for name: String) -> URL {
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var url = dir.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let candidate = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            url = dir.appendingPathComponent(candidate)
            n += 1
        }
        return url
    }

    /// Empties the stash: nothing survives an app restart or reboot.
    func wipe() {
        let fm = FileManager.default
        for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: f)
        }
    }

    private func append(_ url: URL) {
        guard !items.contains(url) else { return }
        // Touch so auto-cleanup counts from when it was stashed.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        items.append(url)
        onChange?()
    }
}

func shellEscaped(_ path: String) -> String {
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-+,@%:="))
    var out = ""
    for ch in path.unicodeScalars {
        if !safe.contains(ch) { out.append("\\") }
        out.unicodeScalars.append(ch)
    }
    return out
}

// MARK: - Shake detection (polls the cursor; needs no special permissions)

final class ShakeDetector {
    var onShake: (() -> Void)?
    private var timer: Timer?
    private var samples: [(t: TimeInterval, x: CGFloat)] = []
    private var lastFire: TimeInterval = 0

    func start() {
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let buttonDown = NSEvent.pressedMouseButtons & 1 != 0
        let anyMove = Settings.shakeWithoutDrag
        if !buttonDown && !anyMove { samples.removeAll(); return }

        samples.append((now, NSEvent.mouseLocation.x))
        samples.removeAll { now - $0.t > 0.7 }
        guard now - lastFire > 1.0, samples.count > 4 else { return }

        // Count direction reversals of at least `threshold` px.
        let threshold: CGFloat = buttonDown ? 30 : 35
        let needed = 3
        var reversals = 0
        var dir: CGFloat = 0
        var extreme = samples[0].x
        for s in samples.dropFirst() {
            let d = s.x - extreme
            if dir == 0 {
                if abs(d) >= threshold { dir = d > 0 ? 1 : -1; extreme = s.x }
            } else if d * dir > 0 {
                extreme = s.x
            } else if abs(d) >= threshold {
                reversals += 1; dir = -dir; extreme = s.x
            }
        }
        if reversals >= needed {
            lastFire = now
            samples.removeAll()
            onShake?()
        }
    }
}

// MARK: - Drag source base (kittens and the basket)

class FileDragSource: NSView, NSDraggingSource {
    var urls: [URL] = []
    var dragImage: NSImage?
    var onDraggedOut: (() -> Void)?
    private var downEvent: NSEvent?

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        downEvent = event
        if event.clickCount == 2, urls.count == 1 { NSWorkspace.shared.open(urls[0]) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = downEvent, !urls.isEmpty else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard dx * dx + dy * dy > 16 else { return }
        downEvent = nil

        let side: CGFloat = 56
        let origin = convert(event.locationInWindow, from: nil)
        let items: [NSDraggingItem] = urls.enumerated().map { i, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let img = (i == 0 ? dragImage : nil) ?? NSWorkspace.shared.icon(forFile: url.path)
            let off = CGFloat(min(i, 6)) * 6
            item.setDraggingFrame(NSRect(x: origin.x - side / 2 + off, y: origin.y - side / 2 - off,
                                         width: side, height: side), contents: img)
            return item
        }
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .generic, .link] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation != [] { onDraggedOut?() }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard !urls.isEmpty else { return nil }
        let m = NSMenu()
        m.addItem(withTitle: "Copy path\(urls.count > 1 ? "s" : "")", action: #selector(copyPaths), keyEquivalent: "").target = self
        m.addItem(withTitle: "Copy as image", action: #selector(copyImage), keyEquivalent: "").target = self
        m.addItem(withTitle: "Show in Finder", action: #selector(reveal), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: urls.count > 1 ? "Clear all" : "Remove", action: #selector(removeItems), keyEquivalent: "").target = self
        return m
    }

    @objc private func copyPaths() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map { shellEscaped($0.path) }.joined(separator: " "), forType: .string)
    }
    @objc private func copyImage() {
        let imgs = urls.compactMap { NSImage(contentsOf: $0) }
        guard !imgs.isEmpty else { NSSound.beep(); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(imgs)
    }
    @objc private func reveal() { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    @objc private func removeItems() { urls.forEach { Store.shared.remove($0) } }
}

// MARK: - Pixel art: kittens and the basket, seen from above

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

extension NSImage {
    /// Rendered at 1x; layers upscale it with `.nearest`, so pixels stay sharp.
    var cg: CGImage? { cgImage(forProposedRect: nil, context: nil, hints: nil) }
}

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

    static let ginger    = Coat(name: "рыжий полосатый · картинка", body: rgb(0xF2A65A), paws: rgb(0xFFE3C2), eye: rgb(0x6FBF5F), stripes: rgb(0xD0702A))
    static let tuxedo    = Coat(name: "чёрный во фраке · PDF", body: rgb(0x34313A), paws: rgb(0xF5F1EA), eye: rgb(0xF2D45C), outline: rgb(0x121015))
    static let snowy     = Coat(name: "белый · текст", body: rgb(0xF7F4EE), paws: rgb(0xFBE4EA), eye: rgb(0x5FA8E0), outline: rgb(0x5E514B))
    static let greyTabby = Coat(name: "серый полосатый · код", body: rgb(0x9CA3AD), paws: rgb(0xDADEE3), eye: rgb(0xF2C14E), stripes: rgb(0x5D646E))
    static let siamese   = Coat(name: "сиамский · видео", body: rgb(0xF3E3C7), paws: rgb(0xFBF2E2), eye: rgb(0x4F9FE6), points: rgb(0x6B4A3A))
    static let calico    = Coat(name: "трёхцветный · музыка", body: rgb(0xFBF7F0), paws: rgb(0xFFFFFF), eye: rgb(0x6FBF5F), patches: [rgb(0xE8913A), rgb(0x3A3437)])
    static let chocolate = Coat(name: "шоколадный · архив", body: rgb(0x8A5A3C), paws: rgb(0xC9A07E), eye: rgb(0xF2C14E), stripes: rgb(0x6A4129))
    static let blue      = Coat(name: "русский голубой · папка", body: rgb(0x7F8FA6), paws: rgb(0xAAB7C9), eye: rgb(0x63C463))
    static let pink      = Coat(name: "розовый · дизайн", body: rgb(0xF4A7C0), paws: rgb(0xFFE0EA), eye: rgb(0x9B7BE0))
    static let cream     = Coat(name: "кремовый · другое", body: rgb(0xE9D3A8), paws: rgb(0xF8EBD2), eye: rgb(0x6FBF5F))

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

    /// Crisp at any scale: every sprite pixel is drawn as a `px`-point square.
    static func image(_ coat: Coat, px: CGFloat, blink: Bool = false) -> NSImage {
        NSImage(size: NSSize(width: CGFloat(cols) * px, height: CGFloat(rows) * px), flipped: true) { _ in
            for (y, row) in sprite.enumerated() {
                for (x, ch) in row.enumerated() {
                    guard let c = coat.color(ch, x, y, blink: blink) else { continue }
                    c.setFill()
                    NSRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px).fill()
                }
            }
            return true
        }
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

        art.frame = CGRect(x: (width - img.size.width) / 2, y: Self.labelH, width: img.size.width, height: spriteH)
        art.contents = img.cg
        art.magnificationFilter = .nearest
        art.shadowColor = NSColor.black.cgColor
        art.shadowOpacity = 0.3
        art.shadowRadius = 1.5
        art.shadowOffset = CGSize(width: 1, height: -2)
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

        let open = Kitten.image(coat, px: px).cg!, shut = Kitten.image(coat, px: px, blink: true).cg!
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
    static let px: CGFloat = 6
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
        let img = Basket.image(px: Self.px)
        art.contents = img.cg
        art.magnificationFilter = .nearest
        art.frame = bounds
        art.shadowColor = rgb(0xFF9EB5).cgColor
        art.shadowOffset = .zero
        art.shadowRadius = 0
        art.shadowOpacity = 0.9
        layer?.addSublayer(art)

        // Hint on the empty cushion.
        hint.alignment = .center
        hint.attributedStringValue = {
            let s = NSMutableAttributedString(string: "мяу\n", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .bold), .foregroundColor: rgb(0xB0687E)])
            s.append(NSAttributedString(string: "кидай сюда", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium), .foregroundColor: rgb(0xB0687E, 0.75)]))
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
        toolTip = count == 0 ? nil : "Потяни корзинку, чтобы забрать всех котиков (\(count))"
        countTag.attributedStringValue = NSAttributedString(string: "котиков: \(count) · тяни корзинку", attributes: [
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

// MARK: - Drop area

final class DropView: NSView {
    var onHighlight: ((Bool) -> Void)?
    /// Called after a drop with the drop point (view coords) and the newly stashed files.
    var onDrop: ((NSPoint, [URL]) -> Void)?
    private var highlighted = false {
        didSet { if highlighted != oldValue { onHighlight?(highlighted) } }
    }
    private let promiseQueue: OperationQueue = {
        let q = OperationQueue(); q.qualityOfService = .userInitiated; return q
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        var types: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff, .string]
        types += NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        registerForDraggedTypes(types)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func isOwnDrag(_ info: NSDraggingInfo) -> Bool {
        (info.draggingSource as? NSView)?.window === window
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if isOwnDrag(sender) { return [] }
        highlighted = true
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        isOwnDrag(sender) ? [] : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { highlighted = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlighted = false
        let pb = sender.draggingPasteboard
        let store = Store.shared
        let before = store.items.count
        let point = convert(sender.draggingLocation, from: nil)

        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            store.add(copying: urls)
        } else if let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver],
                  !receivers.isEmpty {
            for r in receivers {
                r.receivePromisedFiles(atDestination: store.dir, options: [:], operationQueue: promiseQueue) { [weak self] url, error in
                    DispatchQueue.main.async {
                        guard error == nil else { return }
                        store.add(stored: url)
                        self?.onDrop?(point, [url])
                    }
                }
            }
            return true
        } else if let img = (pb.readObjects(forClasses: [NSImage.self]) as? [NSImage])?.first,
                  let tiff = img.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            store.save(data: png, name: "Image \(timestamp()).png")
        } else if let text = pb.string(forType: .string), let data = text.data(using: .utf8) {
            store.save(data: data, name: "Text \(timestamp()).txt")
        } else {
            return false
        }
        onDrop?(point, Array(store.items.dropFirst(before)))
        return true
    }

    private func timestamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"; return f.string(from: Date())
    }
}

// MARK: - The basket panel

final class BasketPanel: NSPanel {
    static let width: CGFloat = 520, height: CGFloat = 480
    private let root = DropView(frame: NSRect(x: 0, y: 0, width: BasketPanel.width, height: BasketPanel.height))
    private let basket: BasketCore
    private var tiles: [URL: KittenTile] = [:]
    private var style = Style.all[0]
    private(set) var isCollapsing = false

    private var slots: [CGPoint] = []

    /// Kitten size steps down as the basket fills up.
    struct Style: Equatable {
        let px: CGFloat, width: CGFloat
        var tileH: CGFloat { CGFloat(Kitten.rows) * px + KittenTile.labelH }
        static let all = [Style(px: 4, width: 76), Style(px: 3, width: 64), Style(px: 2, width: 52), Style(px: 2, width: 42)]
    }

    private var center: CGPoint { CGPoint(x: Self.width / 2, y: Self.height / 2) }

    init() {
        let bw = CGFloat(Basket.cols) * BasketCore.px, bh = CGFloat(Basket.rows) * BasketCore.px
        basket = BasketCore(frame: NSRect(x: (Self.width - bw) / 2, y: 44, width: bw, height: bh))
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        root.wantsLayer = true
        contentView = root
        root.addSubview(basket)
        basket.layer?.zPosition = -10_000
        buildControls()

        root.onHighlight = { [weak self] on in self?.basket.setHungry(on) }
        root.onDrop = { [weak self] point, urls in self?.jumpIn(urls, from: point) }
        basket.onDraggedOut = { [weak self] in
            Store.shared.clear()
            self?.collapse()
        }
        Store.shared.onChange = { [weak self] in self?.reload() }
        reload()
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { collapse() }

    private func buildControls() {
        let buttons = [
            control("doc.on.doc", "Скопировать пути (вставить в терминал)", #selector(copyPaths)),
            control("trash", "Очистить", #selector(clearShelf)),
            control("xmark", "Закрыть (Esc)", #selector(closeHole)),
        ]
        let bar = NSStackView(views: buttons)
        bar.spacing = 14
        bar.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        bar.wantsLayer = true
        bar.layer?.backgroundColor = rgb(0x3A2618, 0.85).cgColor
        bar.layer?.cornerRadius = 11
        bar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(bar)
        bar.layer?.zPosition = 10_000
        NSLayoutConstraint.activate([
            bar.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            bar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            bar.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    private func control(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!.withSymbolConfiguration(cfg)!
        let b = NSButton(image: img, target: self, action: action)
        b.isBordered = false
        b.contentTintColor = rgb(0xFFF3DC, 0.85)
        b.toolTip = tip
        return b
    }

    // MARK: Kittens

    private func reload() {
        let items = Store.shared.items
        basket.urls = items
        basket.dragImage = items.count == 1 ? tiles[items[0]]?.dragImage : nil
        basket.update(count: items.count)

        var next = Style.all.last!
        var nextSlots = seats(for: next)
        for st in Style.all {
            let s = seats(for: st)
            if s.count >= items.count { next = st; nextSlots = s; break }
        }
        slots = nextSlots
        if next != style {
            // Kittens resize: recreate them all.
            style = next
            tiles.values.forEach { $0.removeFromSuperview() }
            tiles.removeAll()
        }
        for (url, t) in tiles where !items.contains(url) {
            t.removeFromSuperview()
            tiles[url] = nil
        }
        for url in items where tiles[url] == nil {
            let t = KittenTile(url: url, px: style.px, width: style.width)
            t.onDraggedOut = { [weak self] in
                // The dragged kitten leaves; the rest shuffle over.
                Store.shared.remove(url)
                if Store.shared.items.isEmpty { self?.collapse() }
            }
            root.addSubview(t, positioned: .above, relativeTo: basket)
            t.setFrameOrigin(origin(of: items.firstIndex(of: url)!))
            tiles[url] = t
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            for (i, url) in items.enumerated() {
                guard let t = tiles[url] else { continue }
                let o = origin(of: i)
                t.animator().setFrameOrigin(o)
                t.layer?.zPosition = -o.y    // top-down: lower kittens are drawn over higher ones
            }
        }
    }

    /// Kitten spots on the cushion for a style, nearest to the middle first.
    private func seats(for st: Style) -> [CGPoint] {
        let c = CGPoint(x: basket.frame.minX + basket.seatCenter.x, y: basket.frame.minY + basket.seatCenter.y)
        let r = basket.seatRadii
        let halfW = CGFloat(Kitten.cols) * st.px / 2 + 4, halfH = st.tileH / 2
        func fits(_ p: CGPoint) -> Bool {
            [(-1, -1), (-1, 1), (1, -1), (1, 1)].allSatisfy { sx, sy in
                let dx = (p.x + CGFloat(sx) * halfW - c.x) / r.width, dy = (p.y + CGFloat(sy) * halfH - c.y) / r.height
                return dx * dx + dy * dy <= 1
            }
        }
        var out: [CGPoint] = []
        let stepY = st.tileH - 2
        let n = Int(r.height / stepY) + 1, m = Int(r.width / st.width) + 1
        for row in -n...n {
            let shift: CGFloat = row % 2 == 0 ? 0 : 0.5      // brick pattern, like a pile
            for col in -m...m {
                let p = CGPoint(x: c.x + (CGFloat(col) + shift) * st.width, y: c.y + CGFloat(row) * stepY)
                if fits(p) { out.append(p) }
            }
        }
        func d(_ p: CGPoint) -> CGFloat { pow((p.x - c.x) / r.width, 2) + pow((p.y - c.y) / r.height, 2) }
        return out.sorted { d($0) != d($1) ? d($0) < d($1) : ($0.y != $1.y ? $0.y > $1.y : $0.x < $1.x) }
    }

    /// Bottom-left corner of the i-th kitten tile. Past capacity, kittens pile on top of each other.
    private func origin(of i: Int) -> NSPoint {
        guard !slots.isEmpty else { return center }
        let layer = CGFloat(i / slots.count)
        let p = slots[i % slots.count]
        return NSPoint(x: p.x - style.width / 2 + layer * 6, y: p.y - style.tileH / 2 - layer * 6)
    }

    // MARK: Jump-in animation

    private func jumpIn(_ urls: [URL], from point: NSPoint) {
        basket.bounce()
        let items = Store.shared.items
        for (k, url) in urls.prefix(10).enumerated() {
            guard let tile = tiles[url], let i = items.firstIndex(of: url) else { continue }
            tile.alphaValue = 0
            let o = origin(of: i)
            let end = CGPoint(x: o.x + style.width / 2, y: o.y + KittenTile.labelH + tile.spriteH / 2)
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

    // MARK: Open / close

    /// Scale around the window center regardless of the layer's anchor point.
    private func scaleTransform(_ s: CGFloat) -> CATransform3D {
        guard let l = root.layer else { return CATransform3DIdentity }
        let pivot = CGPoint(x: center.x - l.anchorPoint.x * l.bounds.width,
                            y: center.y - l.anchorPoint.y * l.bounds.height)
        var t = CATransform3DMakeTranslation(-pivot.x, -pivot.y, 0)
        t = CATransform3DConcat(t, CATransform3DMakeScale(s, s, 1))
        return CATransform3DConcat(t, CATransform3DMakeTranslation(pivot.x, pivot.y, 0))
    }

    func show(near point: NSPoint) {
        isCollapsing = false
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main!
        let vf = screen.frame
        let w = Self.width, h = Self.height
        var origin = NSPoint(x: point.x - w / 2, y: point.y - h / 2)
        origin.x = min(max(origin.x, vf.minX - 30), vf.maxX - w + 30)
        origin.y = min(max(origin.y, vf.minY - 30), vf.maxY - h + 30)
        let wasVisible = isVisible
        if !wasVisible { setFrameOrigin(origin) }
        orderFrontRegardless()
        guard !wasVisible else { return }

        alphaValue = 1
        let open = CASpringAnimation(keyPath: "sublayerTransform")
        open.fromValue = NSValue(caTransform3D: scaleTransform(0.05))
        open.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        open.damping = 12
        open.stiffness = 200
        open.duration = open.settlingDuration
        root.layer?.sublayerTransform = CATransform3DIdentity
        root.layer?.add(open, forKey: "open")
    }

    func collapse() {
        guard isVisible, !isCollapsing else { return }
        isCollapsing = true
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.isCollapsing else { return }
            self.orderOut(nil)
            self.root.layer?.removeAnimation(forKey: "close")
            self.root.layer?.sublayerTransform = CATransform3DIdentity
            self.isCollapsing = false
        }
        let close = CABasicAnimation(keyPath: "sublayerTransform")
        close.toValue = NSValue(caTransform3D: scaleTransform(0.02))
        close.duration = 0.3
        close.timingFunction = CAMediaTimingFunction(name: .easeIn)
        close.fillMode = .forwards
        close.isRemovedOnCompletion = false
        root.layer?.add(close, forKey: "close")
        CATransaction.commit()
    }

    /// True when a screen point is over the basket window.
    func contains(screenPoint p: NSPoint) -> Bool { frame.insetBy(dx: 30, dy: 30).contains(p) }

    @objc func copyPaths() {
        let items = Store.shared.items
        guard !items.isEmpty else { NSSound.beep(); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(items.map { shellEscaped($0.path) }.joined(separator: " "), forType: .string)
    }

    @objc func clearShelf() {
        Store.shared.clear()
        collapse()
    }

    @objc func closeHole() { collapse() }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let panel = BasketPanel()
    private let shake = ShakeDetector()
    private var autoHideTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Store.shared.wipe()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "Toss")
            ?? NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Toss")
        statusItem.menu = buildMenu()

        shake.onShake = { [weak self] in self?.shakeDetected() }
        shake.start()
    }

    private func shakeDetected() {
        panel.show(near: NSEvent.mouseLocation)
        armAutoHide()
    }

    /// If the shelf was summoned by a shake but nothing got dropped, hide it again.
    private func armAutoHide() {
        autoHideTimer?.invalidate()
        var releasedAt: TimeInterval?
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if !Store.shared.items.isEmpty || !self.panel.isVisible { t.invalidate(); return }
            let down = NSEvent.pressedMouseButtons & 1 != 0
            if down { releasedAt = nil; return }
            let now = ProcessInfo.processInfo.systemUptime
            if releasedAt == nil { releasedAt = now }
            if now - releasedAt! > 2.0, !self.panel.contains(screenPoint: NSEvent.mouseLocation) {
                self.panel.collapse()
                t.invalidate()
            }
        }
    }

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.delegate = self
        m.addItem(withTitle: "Show Shelf", action: #selector(showShelf), keyEquivalent: "").target = self
        m.addItem(withTitle: "Copy Paths", action: #selector(copyPaths), keyEquivalent: "").target = self
        m.addItem(withTitle: "Clear Shelf", action: #selector(clearShelf), keyEquivalent: "").target = self
        m.addItem(.separator())
        let anyMove = m.addItem(withTitle: "Shake Without Dragging Too", action: #selector(toggleAnyMove), keyEquivalent: "")
        anyMove.target = self
        anyMove.tag = 1
        let login = m.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.tag = 2
        m.addItem(withTitle: "Open Stash Folder", action: #selector(openStash), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Quit Toss", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return m
    }

    @objc private func showShelf() {
        let p = NSEvent.mouseLocation
        panel.show(near: NSPoint(x: p.x - 160, y: p.y - 260))
    }
    @objc private func copyPaths() { panel.copyPaths() }
    @objc private func clearShelf() { panel.clearShelf() }
    @objc private func toggleAnyMove() { Settings.shakeWithoutDrag.toggle() }
    @objc private func openStash() { NSWorkspace.shared.open(Store.shared.dir) }
    @objc private func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            let a = NSAlert(); a.messageText = "Couldn't change login item"; a.informativeText = error.localizedDescription
            a.runModal()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menu.item(withTag: 1)?.state = Settings.shakeWithoutDrag ? .on : .off
        menu.item(withTag: 2)?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
