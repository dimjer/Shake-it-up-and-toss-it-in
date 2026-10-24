// Toss — shake the mouse, a black hole opens, drop files on it,
// then drag them from the shelf into the terminal (or anywhere else).
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

// MARK: - Drag source base (orbiting files and the hole core)

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

/// A file captured in orbit around the hole: round thumbnail, extension badge, name below.
final class OrbitTile: FileDragSource {
    static let labelH: CGFloat = 14
    let side: CGFloat
    private let imageLayer = CALayer()

    init(url: URL, side: CGFloat, width: CGFloat) {
        self.side = side
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: side + Self.labelH))
        urls = [url]
        toolTip = url.lastPathComponent
        wantsLayer = true
        let amber = NSColor(srgbRed: 1, green: 0.75, blue: 0.4, alpha: 1)

        let holder = CALayer()
        holder.frame = CGRect(x: (width - side) / 2, y: Self.labelH, width: side, height: side)
        holder.shadowColor = NSColor(srgbRed: 1, green: 0.55, blue: 0.15, alpha: 1).cgColor
        holder.shadowOpacity = 0.9
        holder.shadowRadius = 8
        holder.shadowOffset = .zero
        layer?.addSublayer(holder)

        imageLayer.frame = holder.bounds
        imageLayer.cornerRadius = side / 2
        imageLayer.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        imageLayer.borderWidth = 1.5
        imageLayer.borderColor = amber.withAlphaComponent(0.9).cgColor
        holder.addSublayer(imageLayer)

        let ext = url.pathExtension.uppercased()
        if !ext.isEmpty {
            let badge = CATextLayer()
            badge.string = ext
            badge.font = NSFont.monospacedSystemFont(ofSize: 7, weight: .bold)
            badge.fontSize = 7
            badge.alignmentMode = .center
            badge.foregroundColor = NSColor.black.cgColor
            badge.backgroundColor = amber.cgColor
            badge.contentsScale = 2
            let bw = CGFloat(ext.count) * 5 + 8
            badge.frame = CGRect(x: side - bw + 4, y: -2, width: bw, height: 11)
            badge.cornerRadius = 5.5
            holder.addSublayer(badge)
        }

        let name = NSTextField(labelWithString: url.lastPathComponent)
        name.font = .monospacedSystemFont(ofSize: 8.5, weight: .medium)
        name.textColor = amber.withAlphaComponent(0.95)
        name.alignment = .center
        name.lineBreakMode = .byTruncatingMiddle
        name.cell?.truncatesLastVisibleLine = true
        // Dark pill behind the name so it reads on any wallpaper.
        let textW = min(width, ceil(name.intrinsicContentSize.width) + 8)
        name.frame = NSRect(x: (width - textW) / 2, y: 0, width: textW, height: Self.labelH - 1)
        name.wantsLayer = true
        name.layer?.backgroundColor = NSColor(white: 0.05, alpha: 0.8).cgColor
        name.layer?.cornerRadius = (Self.labelH - 1) / 2
        addSubview(name)

        setImage(NSWorkspace.shared.icon(forFile: url.path))
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 128, height: 128),
                                               scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            guard let img = rep?.nsImage else { return }
            DispatchQueue.main.async { self?.setImage(img) }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setImage(_ img: NSImage) {
        dragImage = img
        imageLayer.contents = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

/// The event horizon itself: shows the count, drag from it to pull everything out.
final class HoleCore: FileDragSource {
    private let big = NSTextField(labelWithString: "")
    private let small = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        for l in [big, small] {
            l.alignment = .center
            l.translatesAutoresizingMaskIntoConstraints = false
            let glow = NSShadow()
            glow.shadowColor = NSColor(srgbRed: 1, green: 0.6, blue: 0.2, alpha: 1)
            glow.shadowBlurRadius = 8
            l.shadow = glow
            addSubview(l)
        }
        NSLayoutConstraint.activate([
            big.centerXAnchor.constraint(equalTo: centerXAnchor),
            big.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 6),
            small.centerXAnchor.constraint(equalTo: centerXAnchor),
            small.topAnchor.constraint(equalTo: big.bottomAnchor, constant: 0),
        ])
        update(count: 0)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(count: Int) {
        let amber = NSColor(srgbRed: 1, green: 0.78, blue: 0.45, alpha: 1)
        if count == 0 {
            big.stringValue = ""
            small.stringValue = ""
            toolTip = nil
        } else {
            big.attributedStringValue = spaced("\(count)", size: 26, weight: .bold, color: amber, kern: 1)
            small.attributedStringValue = spaced("PULL OUT", size: 7, weight: .medium, color: amber.withAlphaComponent(0.6), kern: 2.5)
            toolTip = "Drag from the hole to pull out all \(count) file\(count == 1 ? "" : "s")"
        }
    }

    private func spaced(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, kern: CGFloat) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .kern: kern,
        ])
    }

    // Only the round horizon is grabbable.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        let r = bounds.width / 2
        return hypot(p.x - r, p.y - r) <= r ? self : nil
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

// MARK: - Black hole visuals (pure Core Animation, no hit testing)

final class BlackHoleFX: NSView {
    let holeR: CGFloat
    private let glow = CAGradientLayer()
    private let halo = CAGradientLayer()
    private let photonRing = CAShapeLayer()
    private let horizon = CAShapeLayer()
    private let emitter = CAEmitterLayer()
    private var spinners: [(CALayer, Double)] = []

    static let hot: [CGColor] = [
        NSColor(srgbRed: 1.00, green: 0.97, blue: 0.85, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.70, blue: 0.30, alpha: 1),
        NSColor(srgbRed: 0.85, green: 0.30, blue: 0.10, alpha: 0.9),
        NSColor(srgbRed: 0.45, green: 0.10, blue: 0.35, alpha: 0.5),
        NSColor(srgbRed: 1.00, green: 0.60, blue: 0.20, alpha: 0.9),
        NSColor(srgbRed: 1.00, green: 0.92, blue: 0.70, alpha: 1),
        NSColor(srgbRed: 0.95, green: 0.45, blue: 0.15, alpha: 0.8),
        NSColor(srgbRed: 1.00, green: 0.97, blue: 0.85, alpha: 1),
    ].map(\.cgColor)

    init(frame: NSRect, holeR: CGFloat) {
        self.holeR = holeR
        super.init(frame: frame)
        wantsLayer = true
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var c: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    private func centered(_ l: CALayer, _ d: CGFloat) {
        l.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        l.position = c
    }

    /// Soft radial ring mask: transparent inside `inner`, fades out to the edge.
    private func ringMask(d: CGFloat, inner: CGFloat, peak: CGFloat = 0.06) -> CAGradientLayer {
        let m = CAGradientLayer()
        m.type = .radial
        m.frame = CGRect(x: 0, y: 0, width: d, height: d)
        m.startPoint = CGPoint(x: 0.5, y: 0.5)
        m.endPoint = CGPoint(x: 1, y: 1)
        let i = Double(inner / (d / 2))
        m.colors = [NSColor.clear, .clear, .white, NSColor.white.withAlphaComponent(0.5), .clear].map(\.cgColor)
        m.locations = [0, i, min(i + peak, 0.95), 0.72, 1].map { NSNumber(value: $0) }
        return m
    }

    private func conic(d: CGFloat) -> CAGradientLayer {
        let g = CAGradientLayer()
        g.type = .conic
        g.frame = CGRect(x: 0, y: 0, width: d, height: d)
        g.startPoint = CGPoint(x: 0.5, y: 0.5)
        g.endPoint = CGPoint(x: 0.5, y: 0)
        g.colors = Self.hot
        return g
    }

    /// The accretion disk seen almost edge-on.
    private func tiltedDisk(d: CGFloat, spin: Double) -> CALayer {
        let plane = CALayer()
        centered(plane, d)
        var t = CATransform3DIdentity
        t.m34 = -1 / 900
        t = CATransform3DRotate(t, 1.27, 1, 0, 0)
        plane.transform = t
        let disk = conic(d: d)
        disk.mask = ringMask(d: d, inner: holeR * 1.2, peak: 0.1)
        plane.addSublayer(disk)
        spinners.append((disk, spin))
        return plane
    }

    private func build() {
        guard let root = layer else { return }
        let w = bounds.width

        // Ambient glow
        glow.type = .radial
        glow.frame = bounds
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.colors = [NSColor(srgbRed: 1, green: 0.55, blue: 0.2, alpha: 0.45),
                       NSColor(srgbRed: 0.5, green: 0.15, blue: 0.6, alpha: 0.18),
                       NSColor.clear].map(\.cgColor)
        glow.locations = [0.2, 0.5, 1]
        glow.opacity = 0.7
        root.addSublayer(glow)

        // Lensed halo (the far side of the disk bent around the hole)
        let haloD = holeR * 3.6
        centered(halo, haloD)
        halo.type = .conic
        halo.startPoint = CGPoint(x: 0.5, y: 0.5)
        halo.endPoint = CGPoint(x: 0.5, y: 0)
        halo.colors = Self.hot
        halo.mask = ringMask(d: haloD, inner: holeR * 1.02, peak: 0.05)
        root.addSublayer(halo)
        spinners.append((halo, 9))

        // Back half of the disk
        let diskD = w * 0.86
        root.addSublayer(tiltedDisk(d: diskD, spin: 5))

        // Infalling particles
        emitter.emitterPosition = c
        emitter.emitterShape = .circle
        emitter.emitterMode = .outline
        emitter.emitterSize = CGSize(width: w * 0.9, height: w * 0.9)
        emitter.renderMode = .additive
        let cell = CAEmitterCell()
        cell.contents = Self.dotImage()
        cell.birthRate = 30
        cell.lifetime = 2.6
        cell.velocity = -70
        cell.velocityRange = 15
        cell.scale = 0.18
        cell.scaleRange = 0.1
        cell.scaleSpeed = -0.05
        cell.alphaSpeed = -0.25
        cell.color = NSColor(srgbRed: 1, green: 0.8, blue: 0.55, alpha: 0.9).cgColor
        cell.spin = 2
        emitter.emitterCells = [cell]
        root.addSublayer(emitter)

        // Event horizon + photon ring
        let circle = CGPath(ellipseIn: CGRect(x: -holeR, y: -holeR, width: holeR * 2, height: holeR * 2), transform: nil)
        horizon.path = circle
        horizon.position = c
        horizon.fillColor = NSColor.black.cgColor
        horizon.shadowColor = NSColor(srgbRed: 1, green: 0.6, blue: 0.2, alpha: 1).cgColor
        horizon.shadowRadius = 14
        horizon.shadowOpacity = 1
        horizon.shadowOffset = .zero
        root.addSublayer(horizon)

        photonRing.path = CGPath(ellipseIn: CGRect(x: -holeR - 1.5, y: -holeR - 1.5,
                                                   width: holeR * 2 + 3, height: holeR * 2 + 3), transform: nil)
        photonRing.position = c
        photonRing.fillColor = nil
        photonRing.strokeColor = NSColor(srgbRed: 1, green: 0.93, blue: 0.75, alpha: 0.95).cgColor
        photonRing.lineWidth = 1.6
        photonRing.shadowColor = NSColor(srgbRed: 1, green: 0.8, blue: 0.4, alpha: 1).cgColor
        photonRing.shadowRadius = 5
        photonRing.shadowOpacity = 1
        photonRing.shadowOffset = .zero
        root.addSublayer(photonRing)

        // Near half of the disk crosses in front of the hole
        let front = CALayer()
        front.frame = bounds
        let lowerHalf = CALayer()
        lowerHalf.frame = CGRect(x: 0, y: 0, width: w, height: bounds.midY)
        lowerHalf.backgroundColor = NSColor.black.cgColor
        front.mask = lowerHalf
        front.addSublayer(tiltedDisk(d: diskD, spin: 5))
        root.addSublayer(front)
    }

    func startAnimations() {
        for (l, dur) in spinners {
            let a = CABasicAnimation(keyPath: "transform.rotation.z")
            a.fromValue = 0
            a.toValue = -2 * Double.pi
            a.duration = dur
            a.repeatCount = .infinity
            l.add(a, forKey: "spin")
        }
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = 0.55
        breathe.toValue = 0.85
        breathe.duration = 2.4
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        glow.add(breathe, forKey: "breathe")
    }

    /// Hovering a drag over the hole: it gets hungrier.
    func setHungry(_ on: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        glow.setValue(on ? 1.15 : 1.0, forKeyPath: "transform.scale")
        horizon.shadowRadius = on ? 26 : 14
        photonRing.lineWidth = on ? 2.6 : 1.6
        CATransaction.commit()
        emitter.birthRate = on ? 4 : 1
    }

    /// Flash when something falls in.
    func gulp() {
        let a = CAKeyframeAnimation(keyPath: "shadowRadius")
        a.values = [14, 40, 14]
        a.duration = 0.6
        horizon.add(a, forKey: "gulp")
        let s = CAKeyframeAnimation(keyPath: "transform.scale")
        s.values = [1, 1.08, 1]
        s.duration = 0.5
        photonRing.add(s, forKey: "gulp")
    }

    private static func dotImage() -> CGImage {
        let img = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { r in
            NSGradient(colors: [.white, NSColor.white.withAlphaComponent(0)])!
                .draw(in: NSBezierPath(ovalIn: r), relativeCenterPosition: .zero)
            return true
        }
        return img.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
}

// MARK: - The black hole panel

final class HolePanel: NSPanel {
    static let size: CGFloat = 440
    private let holeR: CGFloat = 60
    private let orbitR: CGFloat = 150
    private let root = DropView(frame: NSRect(x: 0, y: 0, width: HolePanel.size, height: HolePanel.size))
    private let fx: BlackHoleFX
    private let core: HoleCore
    private var tiles: [URL: OrbitTile] = [:]
    private var orbitAngle: CGFloat = 0
    private var orbitTimer: Timer?
    private var lastTick: TimeInterval = 0
    private(set) var isCollapsing = false

    private var center: CGPoint { CGPoint(x: Self.size / 2, y: Self.size / 2) }

    init() {
        let s = Self.size
        fx = BlackHoleFX(frame: NSRect(x: 0, y: 0, width: s, height: s), holeR: holeR)
        core = HoleCore(frame: NSRect(x: s / 2 - holeR, y: s / 2 - holeR, width: holeR * 2, height: holeR * 2))
        super.init(contentRect: NSRect(x: 0, y: 0, width: s, height: s),
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
        root.addSubview(fx)
        root.addSubview(core)
        buildControls()

        root.onHighlight = { [weak self] on in self?.fx.setHungry(on) }
        root.onDrop = { [weak self] point, urls in self?.swallow(urls, from: point) }
        core.onDraggedOut = { [weak self] in
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
            control("doc.on.doc", "Copy paths (paste into terminal)", #selector(copyPaths)),
            control("trash", "Clear", #selector(clearShelf)),
            control("xmark", "Close (Esc)", #selector(closeHole)),
        ]
        let bar = NSStackView(views: buttons)
        bar.spacing = 14
        bar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            bar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
        ])
    }

    private func control(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!.withSymbolConfiguration(cfg)!
        let b = NSButton(image: img, target: self, action: action)
        b.isBordered = false
        b.contentTintColor = NSColor(srgbRed: 1, green: 0.8, blue: 0.55, alpha: 0.75)
        b.toolTip = tip
        return b
    }

    // MARK: Orbit

    private func reload() {
        let items = Store.shared.items
        core.urls = items
        core.dragImage = items.count == 1 ? tiles[items[0]]?.dragImage : nil
        core.update(count: items.count)

        for (url, t) in tiles where !items.contains(url) {
            t.removeFromSuperview()
            tiles[url] = nil
        }
        let side: CGFloat = items.count > 12 ? 34 : 44
        for url in items where tiles[url] == nil {
            let t = OrbitTile(url: url, side: side, width: 92)
            t.onDraggedOut = { [weak self] in
                // The dragged file leaves the orbit; the rest keep circling.
                Store.shared.remove(url)
                if Store.shared.items.isEmpty { self?.collapse() }
            }
            root.addSubview(t, positioned: .below, relativeTo: core)
            tiles[url] = t
        }
        layoutOrbit()
    }

    private func layoutOrbit() {
        let items = Store.shared.items
        guard !items.isEmpty else { return }
        for (i, url) in items.enumerated() {
            guard let t = tiles[url] else { continue }
            let a = orbitAngle + CGFloat(i) * 2 * .pi / CGFloat(items.count)
            // Slightly flattened orbit to match the tilted disk.
            let p = CGPoint(x: center.x + orbitR * cos(a), y: center.y + orbitR * 0.82 * sin(a))
            t.setFrameOrigin(NSPoint(x: p.x - t.frame.width / 2, y: p.y - OrbitTile.labelH - t.side / 2))
        }
    }

    private func startOrbit() {
        orbitTimer?.invalidate()
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tickOrbit() }
        RunLoop.main.add(timer, forMode: .common)
        orbitTimer = timer
    }

    private func tickOrbit() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastTick
        lastTick = now
        // Slow down (but keep circling) while the cursor is near the orbit, so files are easy to grab.
        let m = mouseLocationOutsideOfEventStream
        let d = hypot(m.x - center.x, m.y - center.y)
        let nearOrbit = d > orbitR - 50 && d < orbitR + 50
        orbitAngle += CGFloat(dt) * (nearOrbit ? 0.08 : 0.3)
        layoutOrbit()
    }

    // MARK: Swallow animation

    private func swallow(_ urls: [URL], from point: NSPoint) {
        fx.gulp()
        for (k, url) in urls.prefix(8).enumerated() {
            let tile = tiles[url]
            tile?.alphaValue = 0
            let img = tile?.dragImage ?? NSWorkspace.shared.icon(forFile: url.path)

            let ghost = CALayer()
            ghost.contents = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
            ghost.contentsGravity = .resizeAspect
            ghost.bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
            ghost.position = center
            ghost.opacity = 0
            root.layer?.addSublayer(ghost)

            let start = CGPoint(x: point.x + CGFloat(k) * 10, y: point.y - CGFloat(k) * 10)
            let path = CGMutablePath()
            let r0 = max(hypot(start.x - center.x, start.y - center.y), 40)
            let a0 = atan2(start.y - center.y, start.x - center.x)
            for i in 0...48 {
                let t = CGFloat(i) / 48
                let r = r0 * pow(1 - t, 1.3)
                let a = a0 + t * 2.6 * .pi
                let p = CGPoint(x: center.x + r * cos(a), y: center.y + r * 0.85 * sin(a))
                i == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = path
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1
            scale.toValue = 0.02
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = 4 * Double.pi
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0.8, 0]
            fade.keyTimes = [0, 0.5, 0.85, 1]
            let group = CAAnimationGroup()
            group.animations = [move, scale, spin, fade]
            group.duration = 0.8
            group.beginTime = CACurrentMediaTime() + Double(k) * 0.08
            group.timingFunction = CAMediaTimingFunction(name: .easeIn)
            group.fillMode = .backwards
            ghost.add(group, forKey: "swallow")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85 + Double(k) * 0.08) {
                ghost.removeFromSuperlayer()
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.5
                    tile?.animator().alphaValue = 1
                }
            }
        }
        for url in urls.dropFirst(8) { tiles[url]?.alphaValue = 1 }
    }

    // MARK: Open / close

    /// Scale around the window center regardless of the layer's anchor point.
    private func scaleTransform(_ s: CGFloat, rotate: CGFloat = 0) -> CATransform3D {
        guard let l = root.layer else { return CATransform3DIdentity }
        let pivot = CGPoint(x: center.x - l.anchorPoint.x * l.bounds.width,
                            y: center.y - l.anchorPoint.y * l.bounds.height)
        var t = CATransform3DMakeTranslation(-pivot.x, -pivot.y, 0)
        t = CATransform3DConcat(t, CATransform3DMakeRotation(rotate, 0, 0, 1))
        t = CATransform3DConcat(t, CATransform3DMakeScale(s, s, 1))
        return CATransform3DConcat(t, CATransform3DMakeTranslation(pivot.x, pivot.y, 0))
    }

    func show(near point: NSPoint) {
        isCollapsing = false
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main!
        let vf = screen.frame
        let s = Self.size
        var origin = NSPoint(x: point.x - s / 2, y: point.y - s / 2)
        origin.x = min(max(origin.x, vf.minX - 40), vf.maxX - s + 40)
        origin.y = min(max(origin.y, vf.minY - 40), vf.maxY - s + 40)
        let wasVisible = isVisible
        if !wasVisible { setFrameOrigin(origin) }
        orderFrontRegardless()
        fx.startAnimations()
        startOrbit()
        guard !wasVisible else { return }

        alphaValue = 1
        let open = CASpringAnimation(keyPath: "sublayerTransform")
        open.fromValue = NSValue(caTransform3D: scaleTransform(0.05, rotate: 2))
        open.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        open.damping = 14
        open.stiffness = 180
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
            self.orbitTimer?.invalidate()
            self.root.layer?.removeAnimation(forKey: "close")
            self.root.layer?.sublayerTransform = CATransform3DIdentity
            self.isCollapsing = false
        }
        let close = CABasicAnimation(keyPath: "sublayerTransform")
        close.toValue = NSValue(caTransform3D: scaleTransform(0.02, rotate: -3))
        close.duration = 0.35
        close.timingFunction = CAMediaTimingFunction(name: .easeIn)
        close.fillMode = .forwards
        close.isRemovedOnCompletion = false
        root.layer?.add(close, forKey: "close")
        CATransaction.commit()
    }

    /// True when a screen point is within the visible hole + orbit.
    func contains(screenPoint p: NSPoint) -> Bool {
        let c = NSPoint(x: frame.midX, y: frame.midY)
        return hypot(p.x - c.x, p.y - c.y) < orbitR + 40
    }

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
    private let panel = HolePanel()
    private let shake = ShakeDetector()
    private var autoHideTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Store.shared.wipe()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Toss")
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
