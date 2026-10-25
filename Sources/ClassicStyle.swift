// Style "Classic": a plain macOS shelf — frosted window, grid of icons, drop zone.

import Cocoa
import QuickLookThumbnailing

/// A file in the grid: Finder-style icon or thumbnail with its name below.
final class ClassicTile: FileDragSource {
    static let size = NSSize(width: 78, height: 84)
    private let icon = CALayer()
    private var hover: NSTrackingArea?

    init(url: URL) {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        urls = [url]
        toolTip = url.lastPathComponent
        wantsLayer = true
        layer?.cornerRadius = 8

        icon.frame = CGRect(x: (Self.size.width - 48) / 2, y: 32, width: 48, height: 48)
        icon.contentsGravity = .resizeAspect
        layer?.addSublayer(icon)

        let name = NSTextField(wrappingLabelWithString: url.lastPathComponent)
        name.font = .systemFont(ofSize: 10.5)
        name.textColor = .labelColor
        name.alignment = .center
        name.maximumNumberOfLines = 2
        name.lineBreakMode = .byTruncatingMiddle
        name.cell?.truncatesLastVisibleLine = true
        name.frame = NSRect(x: 3, y: 2, width: Self.size.width - 6, height: 28)
        addSubview(name)

        setImage(NSWorkspace.shared.icon(forFile: url.path))
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 96, height: 96),
                                               scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            guard let img = rep?.nsImage else { return }
            DispatchQueue.main.async { self?.setImage(img) }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setImage(_ img: NSImage) {
        dragImage = img
        icon.contents = img.cg
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hover { removeTrackingArea(hover) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(t)
        hover = t
    }
    override func mouseEntered(with event: NSEvent) { setHighlighted(true) }
    override func mouseExited(with event: NSEvent) { setHighlighted(false) }

    private func setHighlighted(_ on: Bool) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = on ? NSColor.labelColor.withAlphaComponent(0.08).cgColor : nil
        }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - The classic panel

final class ClassicPanel: ShelfPanel {
    private static let size = NSSize(width: 344, height: 360)   // three full rows
    private static let cols = 4
    private let effect = NSVisualEffectView()
    private let count = NSTextField(labelWithString: "")
    private let scroll = NSScrollView()
    private let grid = FlippedView()
    private let zone = NSView()
    private let zoneBorder = CAShapeLayer()
    private let hint = NSTextField(labelWithString: "Drop files here")
    private var tiles: [URL: ClassicTile] = [:]
    private var hungry = false

    /// The window keeps clear of the screen edges.
    override var edgeSlack: CGFloat { -8 }

    init() {
        let size = Self.size
        super.init(size: size)
        hasShadow = true

        effect.frame = root.bounds
        effect.autoresizingMask = [.width, .height]
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(12)
        root.addSubview(effect)

        // Title row
        let title = NSTextField(labelWithString: "Toss")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.frame = NSRect(x: 16, y: size.height - 30, width: 40, height: 17)
        root.addSubview(title)
        count.font = .systemFont(ofSize: 12)
        count.textColor = .secondaryLabelColor
        count.frame = NSRect(x: 56, y: size.height - 30, width: 200, height: 16)
        root.addSubview(count)

        // Drop zone behind the grid
        let content = NSRect(x: 10, y: 44, width: size.width - 20, height: size.height - 44 - 40)
        zone.frame = content
        zone.wantsLayer = true
        zoneBorder.frame = zone.bounds
        zoneBorder.path = CGPath(roundedRect: zone.bounds.insetBy(dx: 2, dy: 2), cornerWidth: 10, cornerHeight: 10, transform: nil)
        zoneBorder.lineWidth = 1.5
        zoneBorder.lineDashPattern = [6, 4]
        zone.layer?.addSublayer(zoneBorder)
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = .secondaryLabelColor
        hint.sizeToFit()
        hint.setFrameOrigin(NSPoint(x: (content.width - hint.frame.width) / 2, y: (content.height - hint.frame.height) / 2))
        zone.addSubview(hint)
        root.addSubview(zone)

        scroll.frame = content
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = grid
        root.addSubview(scroll)

        addControlBar(tint: .secondaryLabelColor, pointSize: 12, bottom: 11)
    }

    private static func roundedMask(_ r: CGFloat) -> NSImage {
        let edge = 2 * r + 1
        let img = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        img.resizingMode = .stretch
        return img
    }

    // MARK: Grid

    override func reload() {
        let items = Store.shared.items
        count.stringValue = items.isEmpty ? "" : "\(items.count) \(Self.files(items.count))"

        for (url, t) in tiles where !items.contains(url) {
            t.removeFromSuperview()
            tiles[url] = nil
        }
        for url in items where tiles[url] == nil {
            let t = ClassicTile(url: url)
            grid.addSubview(t)
            tiles[url] = t
        }

        let w = scroll.contentSize.width
        let gap = (w - CGFloat(Self.cols) * ClassicTile.size.width) / CGFloat(Self.cols + 1)
        let rows = (items.count + Self.cols - 1) / Self.cols
        grid.frame = NSRect(x: 0, y: 0, width: w,
                            height: max(scroll.contentSize.height, CGFloat(rows) * (ClassicTile.size.height + 4) + 6))
        for (i, url) in items.enumerated() {
            let col = i % Self.cols, row = i / Self.cols
            tiles[url]?.setFrameOrigin(NSPoint(x: gap + CGFloat(col) * (ClassicTile.size.width + gap),
                                               y: 6 + CGFloat(row) * (ClassicTile.size.height + 4)))
        }
        updateZone()
    }

    private static func files(_ n: Int) -> String { n == 1 ? "file" : "files" }

    private func updateZone() {
        let empty = Store.shared.items.isEmpty
        zone.isHidden = !empty && !hungry
        hint.isHidden = !empty
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let accent = NSColor.controlAccentColor
            zoneBorder.strokeColor = (hungry ? accent : NSColor.tertiaryLabelColor).cgColor
            zoneBorder.fillColor = hungry ? accent.withAlphaComponent(0.1).cgColor : nil
        }
    }

    override func setHungry(_ on: Bool) {
        hungry = on
        updateZone()
    }

    override func didDrop(_ urls: [URL], at point: NSPoint) {
        for url in urls {
            guard let t = tiles[url] else { continue }
            t.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                t.animator().alphaValue = 1
            }
        }
        if let last = urls.last, let t = tiles[last] { grid.scrollToVisible(t.frame) }
    }

    // MARK: Open / close — a quick fade, like a system popover

    override func didShow() { invalidateShadow() }

    override func openAnimation() -> CAAnimation {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let grow = CABasicAnimation(keyPath: "sublayerTransform")
        grow.fromValue = NSValue(caTransform3D: scaleTransform(0.96))
        grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        let g = CAAnimationGroup()
        g.animations = [fade, grow]
        g.duration = 0.16
        g.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return g
    }

    override func closeAnimation() -> CAAnimation {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.toValue = 0
        let shrink = CABasicAnimation(keyPath: "sublayerTransform")
        shrink.toValue = NSValue(caTransform3D: scaleTransform(0.97))
        let g = CAAnimationGroup()
        g.animations = [fade, shrink]
        g.duration = 0.14
        g.timingFunction = CAMediaTimingFunction(name: .easeIn)
        return g
    }

    override func contains(screenPoint p: NSPoint) -> Bool { frame.contains(p) }
}
