// Toss — shake the mouse, a shelf pops up, drop files on it, then drag them into the
// terminal (or anywhere else). Dropped files are COPIED into a stash, so screenshots
// that macOS deletes from its temp location stay available.
//
// The shelf comes in three styles (black hole, kitten basket, plain macOS window):
// shared code lives in Core.swift, each style in its own *Style.swift file.

import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: ShelfPanel!
    private let shake = ShakeDetector()
    private var idleTimer: Timer?
    private var lastActive: TimeInterval = 0
    private let settingsMenu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Store.shared.wipe()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.menu = buildMenu()
        ShelfMenu.shared.onStyleChange = { [weak self] in self?.switchStyle(to: $0) }
        use(Settings.style)

        shake.onShake = { [weak self] in self?.shakeDetected() }
        shake.start()
    }

    // MARK: Style

    private func use(_ style: ShelfStyle) {
        panel = style.makePanel()
        panel.activate()
        statusItem.button?.image = style.icon
            ?? NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Toss")
    }

    /// Swaps the shelf in place: same files, same spot on screen.
    private func switchStyle(to style: ShelfStyle) {
        guard style != Settings.style else { return }
        Settings.style = style
        let wasVisible = panel.isVisible
        let c = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        panel.hide()
        use(style)
        if wasVisible { open(near: c) }
    }

    // MARK: Shake

    private func shakeDetected() { open(near: NSEvent.mouseLocation) }

    private func open(near point: NSPoint) {
        panel.show(near: point)
        watchIdle()
    }

    /// Auto-close (unless set to "Only with ×"): the shelf closes after `Settings.autoClose`
    /// seconds with the cursor away from it and no mouse button held — so a drag into
    /// another window never gets cut short. An empty shelf from a stray shake goes after 2 s.
    private func watchIdle() {
        idleTimer?.invalidate()
        lastActive = ProcessInfo.processInfo.systemUptime
        idleTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] t in
            guard let self, self.panel.isVisible else { t.invalidate(); return }
            let now = ProcessInfo.processInfo.systemUptime
            let busy = NSEvent.pressedMouseButtons & 1 != 0 || self.panel.contains(screenPoint: NSEvent.mouseLocation)
            if busy || Settings.autoClose == 0 { self.lastActive = now; return }
            let limit = Double(Settings.autoClose)
            let wait = Store.shared.items.isEmpty ? min(2, limit) : limit
            if now - self.lastActive > wait {
                self.panel.collapse()
                t.invalidate()
            }
        }
    }

    // MARK: Menu bar

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.delegate = self
        m.addItem(withTitle: "Show Shelf", action: #selector(showShelf), keyEquivalent: "").target = self
        m.addItem(withTitle: "Copy Paths", action: #selector(copyPaths), keyEquivalent: "").target = self
        m.addItem(withTitle: "Clear Shelf", action: #selector(clearShelf), keyEquivalent: "").target = self
        m.addItem(.separator())
        settingsMenu.delegate = self
        m.addItem(withTitle: "Shelf Settings", action: nil, keyEquivalent: "").submenu = settingsMenu
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
        open(near: NSPoint(x: p.x - 160, y: p.y - 260))
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
        if menu === settingsMenu { ShelfMenu.shared.fill(menu) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
