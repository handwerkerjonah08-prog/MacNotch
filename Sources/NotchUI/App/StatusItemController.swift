import AppKit

/// Optional menu bar icon: a small MacBook screen with a notch.
@MainActor
final class StatusItemController: NSObject {
    private var item: NSStatusItem?
    private let openIsland: () -> Void
    private let openSettings: () -> Void

    init(openIsland: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.openIsland = openIsland
        self.openSettings = openSettings
        super.init()
    }

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = Self.icon
            item.button?.toolTip = "MacNotch"
            item.menu = makeMenu()
            self.item = item
        } else if !visible, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Island", action: #selector(openIslandAction), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit MacNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func openIslandAction() { openIsland() }
    @objc private func openSettingsAction() { openSettings() }

    static let icon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let screen = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 3.5, width: 15, height: 11), xRadius: 2.2, yRadius: 2.2)
            screen.lineWidth = 1.4
            NSColor.black.setStroke()
            screen.stroke()
            let notch = NSBezierPath(roundedRect: NSRect(x: 6, y: 11.5, width: 6, height: 3), xRadius: 1.4, yRadius: 1.4)
            NSColor.black.setFill()
            notch.fill()
            NSRect(x: 6, y: 13, width: 6, height: 1.5).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "MacNotch"
        return image
    }()
}
