import AppKit
import KursorKidCore

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let settings: SettingsStore

    var onToggleVisibility: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onRequestAccessibility: (() -> Void)?
    var isAccessibilityTrusted: () -> Bool = { true }

    init(settings: SettingsStore) {
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.statusIcon()
            button.toolTip = "Kursor Kid"
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggle = NSMenuItem(
            title: settings.buddyVisible ? "Hide Kiki" : "Show Kiki",
            action: #selector(toggleVisibility), keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let mute = NSMenuItem(title: "Mute Chatter", action: #selector(toggleMute), keyEquivalent: "")
        mute.target = self
        mute.state = settings.muted ? .on : .off
        menu.addItem(mute)

        if !isAccessibilityTrusted() {
            let ax = NSMenuItem(
                title: "Enable Typing Detection…",
                action: #selector(requestAccessibility), keyEquivalent: ""
            )
            ax.target = self
            menu.addItem(ax)
        }

        menu.addItem(.separator())

        let prefs = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Kursor Kid", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func toggleVisibility() { onToggleVisibility?() }
    @objc private func toggleMute() { settings.muted.toggle() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func requestAccessibility() { onRequestAccessibility?() }

    /// Tiny pixel-Kiki face as the status icon (rendered, not a glyph).
    private static func statusIcon() -> NSImage? {
        let grid = [
            "..HHHHHH..",
            ".HHHHHHHH.",
            "hHSSSSSSHh",
            "hHSOSSOSSh",
            "hHSSSSSSHh",
            "hh.SOOS.hh",
            "hh.JJJJ.hh",
            ".P.JPPJ.P.",
        ]
        guard let cg = PixelArt.image(from: grid, palette: KikiSprites.palette) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: 20, height: 16))
        image.isTemplate = false
        return image
    }
}
