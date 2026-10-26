// Shared by every shelf style: settings, the stash, shake detection, drag & drop,
// and the `ShelfPanel` base window each style builds on.

import Cocoa

// MARK: - Settings

enum Settings {
    static let d: UserDefaults = {
        UserDefaults.standard.register(defaults: ["shakeWithoutDrag": true, "autoClose": 10])
        return UserDefaults.standard
    }()
    /// Seconds without activity before the shelf closes itself; 0 = only the × button closes it.
    static var autoClose = d.integer(forKey: "autoClose") {
        didSet { d.set(autoClose, forKey: "autoClose") }
    }
    /// Empty the shelf when it closes (otherwise only the trash button does).
    static var clearOnClose = d.bool(forKey: "clearOnClose") {
        didSet { d.set(clearOnClose, forKey: "clearOnClose") }
    }
    /// Read on every shake-detector tick, so it's kept in memory.
    static var shakeWithoutDrag = d.bool(forKey: "shakeWithoutDrag") {
        didSet { d.set(shakeWithoutDrag, forKey: "shakeWithoutDrag") }
    }
    static var style = ShelfStyle(rawValue: d.string(forKey: "style") ?? "") ?? .kittens {
        didSet { d.set(style.rawValue, forKey: "style") }
    }
}

/// How the shelf looks. Picked with the palette button or the menu-bar menu.
enum ShelfStyle: String, CaseIterable {
    case hole, kittens, classic

    var title: String {
        switch self {
        case .hole: return "Black Hole"
        case .kittens: return "Kittens"
        case .classic: return "Classic"
        }
    }

    /// Menu-bar icon and menu item image.
    var icon: NSImage? {
        switch self {
        case .hole: return Self.holeIcon
        case .kittens: return NSImage(systemSymbolName: "cat.fill", accessibilityDescription: title)
            ?? NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: title)
        case .classic: return NSImage(systemSymbolName: "tray.full.fill", accessibilityDescription: title)
        }
    }

    /// SF Symbols has no black hole: a dark disc in a thin photon ring, with the accretion
    /// disk seen almost edge-on cutting across it. Drawn as a template image so the menu
    /// bar tints it for light and dark mode.
    private static let holeIcon: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            let ctx = NSGraphicsContext.current!
            let c = NSPoint(x: r.midX, y: r.midY)
            func circle(_ radius: CGFloat) -> NSBezierPath {
                NSBezierPath(ovalIn: NSRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
            }
            // The disk's own frame: centred, tilted a little.
            var tilt = AffineTransform(translationByX: c.x, byY: c.y)
            tilt.rotate(byDegrees: -12)
            let disk = NSBezierPath(ovalIn: NSRect(x: -8.6, y: -1.9, width: 17.2, height: 3.8))
            disk.transform(using: tilt)

            NSColor.black.set()
            let photon = circle(6.8)
            photon.lineWidth = 1.2
            photon.stroke()
            circle(4.6).fill()
            disk.lineWidth = 1.3
            // Far half of the disk: hidden behind the hole.
            NSGraphicsContext.saveGraphicsState()
            let far = NSBezierPath(rect: NSRect(x: -12, y: 0, width: 24, height: 12))
            far.transform(using: tilt)
            far.append(circle(5.8))
            far.windingRule = .evenOdd
            far.addClip()
            disk.stroke()
            NSGraphicsContext.restoreGraphicsState()
            // Near half: crosses in front of the hole, with a gap cut around it.
            let near = NSBezierPath(rect: NSRect(x: -12, y: -12, width: 24, height: 12))
            near.transform(using: tilt)
            near.addClip()
            ctx.compositingOperation = .destinationOut
            disk.lineWidth = 3.4
            disk.stroke()
            ctx.compositingOperation = .sourceOver
            disk.lineWidth = 1.3
            disk.stroke()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Black Hole"
        return img
    }()

    func makePanel() -> ShelfPanel {
        switch self {
        case .hole: return HolePanel()
        case .kittens: return BasketPanel()
        case .classic: return ClassicPanel()
        }
    }
}

// MARK: - Settings menu (the panel's gear button and the menu-bar "Shelf Settings")

final class ShelfMenu: NSObject {
    static let shared = ShelfMenu()
    var onStyleChange: ((ShelfStyle) -> Void)?

    /// Style, auto-close and clearing options, checked to match the current settings.
    func fill(_ m: NSMenu) {
        m.removeAllItems()
        header("Style", in: m)
        for s in ShelfStyle.allCases {
            let i = item(s.title, #selector(pickStyle(_:)), s.rawValue, on: s == Settings.style, in: m)
            i.image = s.icon
        }
        m.addItem(.separator())
        header("Close the Shelf", in: m)
        for sec in [3, 10, 30] {
            item("After \(sec) s Idle", #selector(pickAutoClose(_:)), sec, on: Settings.autoClose == sec, in: m)
        }
        item("Only with ×", #selector(pickAutoClose(_:)), 0, on: Settings.autoClose == 0, in: m)
        m.addItem(.separator())
        header("Clear Files", in: m)
        item("When the Shelf Closes", #selector(pickClear(_:)), true, on: Settings.clearOnClose, in: m)
        item("Only with the Trash Button", #selector(pickClear(_:)), false, on: !Settings.clearOnClose, in: m)
    }

    private func header(_ title: String, in m: NSMenu) {
        let h = m.addItem(withTitle: title, action: nil, keyEquivalent: "")
        h.isEnabled = false
    }

    @discardableResult
    private func item(_ title: String, _ action: Selector, _ value: Any, on: Bool, in m: NSMenu) -> NSMenuItem {
        let i = m.addItem(withTitle: title, action: action, keyEquivalent: "")
        i.target = self
        i.representedObject = value
        i.state = on ? .on : .off
        i.indentationLevel = 1
        return i
    }

    @objc private func pickStyle(_ i: NSMenuItem) {
        guard let raw = i.representedObject as? String, let s = ShelfStyle(rawValue: raw) else { return }
        onStyleChange?(s)
    }
    @objc private func pickAutoClose(_ i: NSMenuItem) { Settings.autoClose = i.representedObject as? Int ?? 10 }
    @objc private func pickClear(_ i: NSMenuItem) { Settings.clearOnClose = i.representedObject as? Bool ?? false }
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
        var changed = false
        for src in urls {
            // Already in the stash (e.g. dragged back in) — just re-add.
            if src.standardizedFileURL.path.hasPrefix(dir.standardizedFileURL.path) {
                changed = append(src) || changed; continue
            }
            let dst = uniqueURL(for: src.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: src, to: dst)
                changed = append(dst) || changed
            } catch {
                NSLog("Toss: copy failed for \(src.path): \(error)")
            }
        }
        // One relayout for the whole drop, not one per file.
        if changed { onChange?() }
    }

    /// Adds a file that is already inside the stash.
    func add(stored url: URL) { if append(url) { onChange?() } }

    func save(data: Data, name: String) {
        let dst = uniqueURL(for: name)
        if (try? data.write(to: dst)) != nil, append(dst) { onChange?() }
    }

    func remove(_ urls: [URL]) {
        let gone = Set(urls)
        items.removeAll { gone.contains($0) }
        onChange?()
    }
    func remove(_ url: URL) { remove([url]) }

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

    /// Returns false if the file was already on the shelf. Callers send `onChange`.
    private func append(_ url: URL) -> Bool {
        guard !items.contains(url) else { return false }
        // Touch so auto-cleanup counts from when it was stashed.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        items.append(url)
        return true
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

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

extension NSImage {
    var cg: CGImage? { cgImage(forProposedRect: nil, context: nil, hints: nil) }
}

// MARK: - Shake detection (polls the cursor; needs no special permissions)

final class ShakeDetector {
    var onShake: (() -> Void)?
    private var timer: Timer?
    private var samples: [(t: TimeInterval, x: CGFloat, y: CGFloat)] = []
    private var lastFire: TimeInterval = 0
    private var lastX: CGFloat = .nan
    private var lastY: CGFloat = .nan
    private var lastMove: TimeInterval = 0

    /// 60 Hz while the cursor moves; 10 Hz once it has rested, to save wakeups.
    private static let fast = 1.0 / 60.0, slow = 1.0 / 10.0

    func start() { schedule(Self.fast) }

    private func schedule(_ interval: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let loc = NSEvent.mouseLocation
        let moved = loc.x != lastX || loc.y != lastY
        lastX = loc.x; lastY = loc.y
        let interval = timer?.timeInterval ?? Self.fast
        if moved {
            lastMove = now
            if interval != Self.fast { schedule(Self.fast) }
        } else if interval == Self.fast, now - lastMove > 0.5 {
            schedule(Self.slow)
        }

        let buttonDown = NSEvent.pressedMouseButtons & 1 != 0
        if !buttonDown && !Settings.shakeWithoutDrag { samples.removeAll(); return }

        while let first = samples.first, now - first.t > 0.9 { samples.removeFirst() }
        // A resting cursor adds nothing to the reversal count.
        guard moved else { return }
        samples.append((now, loc.x, loc.y))
        guard now - lastFire > 1.0, samples.count > 6 else { return }

        // Shake in any direction: find the main axis of the motion and count
        // reversals along it. Circles and arcs have no main axis, so they don't count.
        let n = CGFloat(samples.count)
        let mx = samples.reduce(0) { $0 + $1.x } / n, my = samples.reduce(0) { $0 + $1.y } / n
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        for p in samples {
            let dx = p.x - mx, dy = p.y - my
            sxx += dx * dx; syy += dy * dy; sxy += dx * dy
        }
        let half = (sxx + syy) / 2, root = ((sxx - syy) * (sxx - syy) / 4 + sxy * sxy).squareRoot()
        let major = half + root, minor = half - root
        guard major > minor * 6 else { return }
        let angle = atan2(2 * sxy, sxx - syy) / 2
        let ux = cos(angle), uy = sin(angle)
        let along = samples.map { $0.x * ux + $0.y * uy }

        // Count direction reversals of at least `threshold` px.
        let threshold: CGFloat = buttonDown ? 45 : 55
        let needed = 4
        var reversals = 0
        var dir: CGFloat = 0
        var extreme = along[0]
        for v in along.dropFirst() {
            let d = v - extreme
            if dir == 0 {
                if abs(d) >= threshold { dir = d > 0 ? 1 : -1; extreme = v }
            } else if d * dir > 0 {
                extreme = v
            } else if abs(d) >= threshold {
                reversals += 1; dir = -dir; extreme = v
            }
        }
        if reversals >= needed {
            lastFire = now
            samples.removeAll()
            onShake?()
        }
    }
}

// MARK: - Drag source base (every file tile, and each style's "take all" handle)

/// Dragging out copies: the files stay on the shelf, so they can go into several windows.
class FileDragSource: NSView, NSDraggingSource {
    var urls: [URL] = []
    var dragImage: NSImage?
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
    @objc private func removeItems() { Store.shared.remove(urls) }
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
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"; return f
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
            store.save(data: png, name: "Image \(Self.stamp.string(from: Date())).png")
        } else if let text = pb.string(forType: .string), let data = text.data(using: .utf8) {
            store.save(data: data, name: "Text \(Self.stamp.string(from: Date())).txt")
        } else {
            return false
        }
        onDrop?(point, Array(store.items.dropFirst(before)))
        return true
    }
}

/// "Take everything": a stack icon with the file count, in every style's button bar.
final class GrabAllHandle: FileDragSource {
    var tint: NSColor = .secondaryLabelColor
    var pointSize: CGFloat = 11

    override var intrinsicContentSize: NSSize { NSSize(width: 34, height: 22) }

    override func draw(_ dirtyRect: NSRect) {
        let color = urls.isEmpty ? tint.withAlphaComponent(0.35) : tint
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let img = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "Take all")?
            .withSymbolConfiguration(cfg) else { return }
        let text = NSAttributedString(string: "\(urls.count)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .semibold), .foregroundColor: color])
        let ts = text.size()
        var x = (bounds.width - img.size.width - 3 - ts.width) / 2
        img.draw(in: NSRect(x: x, y: (bounds.height - img.size.height) / 2, width: img.size.width, height: img.size.height))
        x += img.size.width + 3
        text.draw(at: NSPoint(x: x, y: (bounds.height - ts.height) / 2))
    }
}

// MARK: - Shelf panel base: window, control bar, settings menu, open/close

class ShelfPanel: NSPanel {
    let root: DropView
    let grabAll = GrabAllHandle()
    private(set) var isCollapsing = false

    var center: CGPoint { CGPoint(x: root.bounds.midX, y: root.bounds.midY) }

    // MARK: Per-style hooks

    /// How far the window may hang off the screen edge (transparent margins).
    var edgeSlack: CGFloat { 30 }
    /// Rotation of the open / close animation, in radians.
    var spin: (open: CGFloat, close: CGFloat) { (0, 0) }

    func reload() {}
    func setHungry(_ on: Bool) {}
    func didDrop(_ urls: [URL], at point: NSPoint) {}
    func didShow() {}
    func didHide() {}

    /// True when a screen point is over the visible part of the shelf.
    func contains(screenPoint p: NSPoint) -> Bool { frame.insetBy(dx: edgeSlack, dy: edgeSlack).contains(p) }

    func openAnimation() -> CAAnimation {
        let open = CASpringAnimation(keyPath: "sublayerTransform")
        open.fromValue = NSValue(caTransform3D: scaleTransform(0.05, rotate: spin.open))
        open.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        open.damping = 12
        open.stiffness = 200
        open.duration = open.settlingDuration
        return open
    }

    func closeAnimation() -> CAAnimation {
        let close = CABasicAnimation(keyPath: "sublayerTransform")
        close.toValue = NSValue(caTransform3D: scaleTransform(0.02, rotate: spin.close))
        close.duration = 0.3
        close.timingFunction = CAMediaTimingFunction(name: .easeIn)
        return close
    }

    // MARK: Setup

    init(size: NSSize) {
        root = DropView(frame: NSRect(origin: .zero, size: size))
        super.init(contentRect: root.frame, styleMask: [.borderless, .nonactivatingPanel],
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
        root.onHighlight = { [weak self] on in self?.setHungry(on) }
        root.onDrop = { [weak self] point, urls in self?.didDrop(urls, at: point) }
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { collapse() }

    /// Becomes the shelf the app shows: follows the stash from now on.
    func activate() {
        Store.shared.onChange = { [weak self] in self?.storeChanged() }
        storeChanged()
    }

    private func storeChanged() {
        let items = Store.shared.items
        grabAll.urls = items
        grabAll.toolTip = items.isEmpty ? nil : "Drag to take all \(items.count) file\(items.count == 1 ? "" : "s")"
        grabAll.needsDisplay = true
        reload()
    }

    /// Take all · copy paths · clear · settings · close, centred at the bottom.
    @discardableResult
    func addControlBar(tint: NSColor, background: NSColor? = nil, pointSize: CGFloat = 11,
                       bottom: CGFloat = 12) -> NSStackView {
        grabAll.tint = tint
        grabAll.pointSize = pointSize
        let buttons: [NSView] = [
            grabAll,
            control("doc.on.doc", "Copy paths (paste into terminal)", #selector(copyPaths), tint, pointSize),
            control("trash", "Clear files", #selector(clearShelf), tint, pointSize),
            control("gearshape", "Style & settings", #selector(openSettings(_:)), tint, pointSize),
            control("xmark", "Close (Esc)", #selector(closeShelf), tint, pointSize),
        ]
        let bar = NSStackView(views: buttons)
        bar.spacing = 14
        bar.translatesAutoresizingMaskIntoConstraints = false
        if let background {
            bar.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
            bar.wantsLayer = true
            bar.layer?.backgroundColor = background.cgColor
            bar.layer?.cornerRadius = 11
        }
        root.addSubview(bar)
        bar.layer?.zPosition = 10_000
        NSLayoutConstraint.activate([
            bar.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            bar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -bottom),
            bar.heightAnchor.constraint(equalToConstant: 22),
        ])
        return bar
    }

    private func control(_ symbol: String, _ tip: String, _ action: Selector,
                         _ tint: NSColor, _ pointSize: CGFloat) -> NSButton {
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!.withSymbolConfiguration(cfg)!
        let b = NSButton(image: img, target: self, action: action)
        b.isBordered = false
        b.contentTintColor = tint
        b.toolTip = tip
        return b
    }

    @objc func copyPaths() {
        let items = Store.shared.items
        guard !items.isEmpty else { NSSound.beep(); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(items.map { shellEscaped($0.path) }.joined(separator: " "), forType: .string)
    }

    /// Empties the shelf; the window stays open.
    @objc func clearShelf() { Store.shared.clear() }

    @objc func closeShelf() { collapse() }

    @objc private func openSettings(_ sender: NSButton) {
        let m = NSMenu()
        ShelfMenu.shared.fill(m)
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    // MARK: Open / close

    /// Scale around the window center regardless of the layer's anchor point.
    func scaleTransform(_ s: CGFloat, rotate: CGFloat = 0) -> CATransform3D {
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
        let vf = screen.visibleFrame
        let w = frame.width, h = frame.height, slack = edgeSlack
        var origin = NSPoint(x: point.x - w / 2, y: point.y - h / 2)
        origin.x = min(max(origin.x, vf.minX - slack), vf.maxX - w + slack)
        origin.y = min(max(origin.y, vf.minY - slack), vf.maxY - h + slack)
        let wasVisible = isVisible
        if !wasVisible { setFrameOrigin(origin) }
        orderFrontRegardless()
        didShow()
        guard !wasVisible else { return }

        alphaValue = 1
        root.layer?.removeAnimation(forKey: "close")
        root.layer?.sublayerTransform = CATransform3DIdentity
        root.layer?.add(openAnimation(), forKey: "open")
    }

    func collapse() {
        guard isVisible, !isCollapsing else { return }
        isCollapsing = true
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.isCollapsing else { return }
            self.hide()
            if Settings.clearOnClose { Store.shared.clear() }
        }
        let close = closeAnimation()
        close.fillMode = .forwards
        close.isRemovedOnCompletion = false
        root.layer?.add(close, forKey: "close")
        CATransaction.commit()
    }

    /// Hides at once, no animation (also used when switching styles).
    func hide() {
        orderOut(nil)
        root.layer?.removeAnimation(forKey: "open")
        root.layer?.removeAnimation(forKey: "close")
        root.layer?.sublayerTransform = CATransform3DIdentity
        isCollapsing = false
        didHide()
    }
}
