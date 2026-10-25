// Style "Black Hole": a rip in space that opens from a point; files spiral in and orbit it.

import Cocoa
import QuickLookThumbnailing

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
        // The glow is round: a path spares Core Animation an offscreen pass every orbit frame.
        holder.shadowPath = CGPath(ellipseIn: holder.bounds, transform: nil)
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
        imageLayer.contents = img.cg
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

// MARK: - Black hole visuals (pure Core Animation, no hit testing)

final class BlackHoleFX: NSView {
    let holeR: CGFloat
    private let glow = CAGradientLayer()
    private let halo = CAGradientLayer()
    private let photonRing = CAShapeLayer()
    private let horizon = CAShapeLayer()
    private let emitter = CAEmitterLayer()
    /// Everything outside the horizon, split around it: thrown out on open, sucked in on close.
    private let back = CALayer()
    private let front = CALayer()
    private let flash = CAGradientLayer()
    private let shockwave = CAShapeLayer()
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
        back.frame = bounds
        root.addSublayer(back)

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
        back.addSublayer(glow)

        // Lensed halo (the far side of the disk bent around the hole)
        let haloD = holeR * 3.6
        centered(halo, haloD)
        halo.type = .conic
        halo.startPoint = CGPoint(x: 0.5, y: 0.5)
        halo.endPoint = CGPoint(x: 0.5, y: 0)
        halo.colors = Self.hot
        halo.mask = ringMask(d: haloD, inner: holeR * 1.02, peak: 0.05)
        back.addSublayer(halo)
        spinners.append((halo, 9))

        // Back half of the disk
        let diskD = w * 0.86
        back.addSublayer(tiltedDisk(d: diskD, spin: 5))

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
        back.addSublayer(emitter)

        // Event horizon + photon ring
        let circle = CGPath(ellipseIn: CGRect(x: -holeR, y: -holeR, width: holeR * 2, height: holeR * 2), transform: nil)
        horizon.path = circle
        horizon.position = c
        horizon.fillColor = NSColor.black.cgColor
        horizon.shadowColor = NSColor(srgbRed: 1, green: 0.6, blue: 0.2, alpha: 1).cgColor
        horizon.shadowRadius = 14
        horizon.shadowOpacity = 1
        horizon.shadowOffset = .zero
        horizon.shadowPath = circle
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
        front.frame = bounds
        let lowerHalf = CALayer()
        lowerHalf.frame = CGRect(x: 0, y: 0, width: w, height: bounds.midY)
        lowerHalf.backgroundColor = NSColor.black.cgColor
        front.mask = lowerHalf
        front.addSublayer(tiltedDisk(d: diskD, spin: 5))
        root.addSublayer(front)

        // Shockwave of the rip and the white-hot spark at the singularity (hidden until used)
        shockwave.path = circle
        shockwave.position = c
        shockwave.fillColor = nil
        shockwave.strokeColor = NSColor(srgbRed: 1, green: 0.85, blue: 0.6, alpha: 1).cgColor
        shockwave.lineWidth = 2
        shockwave.opacity = 0
        root.addSublayer(shockwave)

        flash.type = .radial
        centered(flash, holeR * 3)
        flash.startPoint = CGPoint(x: 0.5, y: 0.5)
        flash.endPoint = CGPoint(x: 1, y: 1)
        flash.colors = [NSColor.white, NSColor(srgbRed: 1, green: 0.75, blue: 0.4, alpha: 0.8), .clear].map(\.cgColor)
        flash.locations = [0, 0.3, 1]
        flash.opacity = 0
        root.addSublayer(flash)
    }

    // MARK: Rip open / seal

    /// Opening: space tears from a single point inside. A spark, a slit that widens
    /// into the round horizon, then a shockwave throws the disk and glow outward.
    func tearOpen() {
        reset()
        let t0 = CACurrentMediaTime()

        let spark = CAAnimationGroup()
        spark.animations = [keyframes("opacity", [0, 1, 0], times: [0, 0.2, 1]),
                            keyframes("transform.scale", [0.1, 0.5, 1.5], times: [0, 0.2, 1])]
        spark.duration = 0.55
        flash.add(spark, forKey: "tear")

        for l in [horizon, photonRing] {
            l.add(rip(open: true, begin: t0 + 0.04, duration: 0.5), forKey: "tear")
        }

        let wave = CAAnimationGroup()
        let reach = bounds.width / 2 / holeR
        wave.animations = [keyframes("transform.scale", [1, reach], times: [0, 1]),
                           keyframes("opacity", [0.9, 0], times: [0, 1])]
        wave.beginTime = t0 + 0.22
        wave.duration = 0.5
        wave.timingFunction = CAMediaTimingFunction(name: .easeOut)
        shockwave.add(wave, forKey: "tear")

        for l in [back, front] {
            let out = CAAnimationGroup()
            out.animations = [keyframes("transform.scale", [0.3, 1], times: [0, 1]),
                              keyframes("opacity", [0, 1], times: [0, 1])]
            out.beginTime = t0 + 0.22
            out.duration = 0.5
            out.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            out.fillMode = .backwards
            l.add(out, forKey: "tear")
        }
    }

    /// Closing: the disk and glow fall into the hole, the horizon pinches into a slit,
    /// then a point, and the rip seals with a last spark. Returns the total duration.
    @discardableResult
    func seal() -> CFTimeInterval {
        reset()
        let t0 = CACurrentMediaTime()

        for l in [back, front] {
            let fall = CAAnimationGroup()
            fall.animations = [keyframes("transform.scale", [1, 0.15], times: [0, 1]),
                               keyframes("opacity", [1, 0], times: [0, 1])]
            fall.duration = 0.25
            fall.timingFunction = CAMediaTimingFunction(name: .easeIn)
            hold(fall)
            l.add(fall, forKey: "seal")
        }

        for l in [horizon, photonRing] {
            let pinch = rip(open: false, begin: t0 + 0.12, duration: 0.25)
            hold(pinch)
            l.add(pinch, forKey: "seal")
        }

        let spark = CAAnimationGroup()
        spark.animations = [keyframes("opacity", [0, 1, 0], times: [0, 0.3, 1]),
                            keyframes("transform.scale", [0.05, 0.4, 0.02], times: [0, 0.3, 1])]
        spark.beginTime = t0 + 0.33
        spark.duration = 0.22
        flash.add(spark, forKey: "seal")
        return 0.55
    }

    /// Drops any held seal / tear state so the hole is whole again.
    func reset() {
        for l in [back, front, horizon, photonRing, flash, shockwave] {
            l.removeAnimation(forKey: "seal")
            l.removeAnimation(forKey: "tear")
        }
    }

    /// The horizon as a rip: point -> thin horizontal slit -> round hole (or back).
    private func rip(open: Bool, begin: CFTimeInterval, duration: CFTimeInterval) -> CAAnimationGroup {
        var sx: [CGFloat] = [0.02, 0.85, 1], sy: [CGFloat] = [0.02, 0.05, 1]
        var times: [Double] = [0, 0.35, 1]
        if !open {
            sx.reverse(); sy.reverse()
            times = [0, 0.65, 1]
        }
        let g = CAAnimationGroup()
        g.animations = [keyframes("transform.scale.x", sx, times: times),
                        keyframes("transform.scale.y", sy, times: times)]
        g.beginTime = begin
        g.duration = duration
        g.timingFunction = CAMediaTimingFunction(name: open ? .easeOut : .easeIn)
        g.fillMode = .backwards
        return g
    }

    private func keyframes(_ path: String, _ values: [CGFloat], times: [Double]) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: path)
        a.values = values
        a.keyTimes = times.map { NSNumber(value: $0) }
        return a
    }

    /// Keep the end state until `reset()`, so nothing pops back before the window hides.
    private func hold(_ a: CAAnimation) {
        a.fillMode = a.fillMode == .backwards ? .both : .forwards
        a.isRemovedOnCompletion = false
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
        return img.cg!
    }
}

// MARK: - The black hole panel

final class HolePanel: ShelfPanel {
    static let size: CGFloat = 440
    private let holeR: CGFloat = 60
    private let orbitR: CGFloat = 150
    private let fx: BlackHoleFX
    private let core: HoleCore
    private var tiles: [URL: OrbitTile] = [:]
    private var orbitAngle: CGFloat = 0
    private var orbitTimer: Timer?
    private var lastTick: TimeInterval = 0

    override var edgeSlack: CGFloat { 40 }

    init() {
        let s = Self.size
        fx = BlackHoleFX(frame: NSRect(x: 0, y: 0, width: s, height: s), holeR: holeR)
        core = HoleCore(frame: NSRect(x: s / 2 - holeR, y: s / 2 - holeR, width: holeR * 2, height: holeR * 2))
        super.init(size: NSSize(width: s, height: s))
        root.addSubview(fx)
        root.addSubview(core)
        addControlBar(tint: NSColor(srgbRed: 1, green: 0.8, blue: 0.55, alpha: 0.75), pointSize: 12, bottom: 16)
    }

    // MARK: Orbit

    override func reload() {
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
        // Nothing in orbit: nothing to move.
        guard !tiles.isEmpty else { lastTick = ProcessInfo.processInfo.systemUptime; return }
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

    override func setHungry(_ on: Bool) { fx.setHungry(on) }

    override func didDrop(_ urls: [URL], at point: NSPoint) {
        fx.gulp()
        for (k, url) in urls.prefix(8).enumerated() {
            let tile = tiles[url]
            tile?.alphaValue = 0
            let img = tile?.dragImage ?? NSWorkspace.shared.icon(forFile: url.path)

            let ghost = CALayer()
            ghost.contents = img.cg
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

    override func didShow() {
        fx.startAnimations()
        startOrbit()
    }

    override func didHide() {
        orbitTimer?.invalidate()
        fx.reset()
        for v in satellites { v.layer?.removeAnimation(forKey: "seal") }
    }

    /// No spiral: a black hole is a rip in space, so it opens from a point inside
    /// and seals back into it. The hole draws that itself; files and buttons follow.
    override func openAnimation() -> CAAnimation {
        fx.tearOpen()
        let t0 = CACurrentMediaTime()
        for v in satellites {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 0
            a.toValue = 1
            a.beginTime = t0 + 0.35
            a.duration = 0.3
            a.fillMode = .backwards
            v.layer?.add(a, forKey: "tear")
        }
        return pause(0.75)
    }

    override func closeAnimation() -> CAAnimation {
        let total = fx.seal()
        // Files, count and buttons get pulled into the centre with everything else.
        for v in satellites {
            guard let l = v.layer else { continue }
            let pull = CABasicAnimation(keyPath: "position")
            pull.fromValue = NSValue(point: l.position)
            pull.toValue = NSValue(point: NSPoint(x: l.position.x + center.x - v.frame.midX,
                                                  y: l.position.y + center.y - v.frame.midY))
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            let g = CAAnimationGroup()
            g.animations = [pull, fade]
            g.duration = 0.25
            g.timingFunction = CAMediaTimingFunction(name: .easeIn)
            g.fillMode = .forwards
            g.isRemovedOnCompletion = false
            l.add(g, forKey: "seal")
        }
        return pause(total)
    }

    /// Everything in the window except the hole itself.
    private var satellites: [NSView] { root.subviews.filter { $0 !== fx } }

    /// A do-nothing animation that keeps the window's open / close running for `d` seconds.
    private func pause(_ d: CFTimeInterval) -> CAAnimation {
        let a = CABasicAnimation(keyPath: "sublayerTransform")
        a.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
        a.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        a.duration = d
        return a
    }

    /// True when a screen point is within the visible hole + orbit.
    override func contains(screenPoint p: NSPoint) -> Bool {
        let c = NSPoint(x: frame.midX, y: frame.midY)
        return hypot(p.x - c.x, p.y - c.y) < orbitR + 40
    }
}
