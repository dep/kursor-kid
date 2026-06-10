import AppKit
import SpriteKit

/// Transparent, borderless, always-on-top strip along the bottom of the main
/// screen. Mouse events pass through except when the cursor is over Kiki
/// (toggled dynamically by BuddyScene).
final class OverlayWindow: NSPanel {
    static let stripHeight: CGFloat = 220

    init() {
        super.init(
            contentRect: Self.stripFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @objc private func screenChanged() {
        setFrame(Self.stripFrame(), display: true)
    }

    private static func stripFrame() -> NSRect {
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(x: screen.minX, y: screen.minY, width: screen.width, height: stripHeight)
    }
}
