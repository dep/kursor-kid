import AppKit
import KursorKidCore
import SpriteKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private var window: OverlayWindow!
    private var scene: BuddyScene!
    private var menuBar: MenuBarController!
    private var inputMonitor: InputMonitor!
    private var quips: QuipCoordinator!
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = OverlayWindow()
        scene = BuddyScene(scale: settings.spriteScale)

        let skView = SKView(frame: window.contentLayoutRect)
        skView.autoresizingMask = [.width, .height]
        skView.allowsTransparency = true
        skView.preferredFramesPerSecond = 30
        skView.presentScene(scene)
        window.contentView = skView

        inputMonitor = InputMonitor()
        let service = QuipService(apiKeyProvider: { KeychainStore.apiKey() })
        quips = QuipCoordinator(service: service, settings: settings, inputMonitor: inputMonitor, scene: scene)

        wireCallbacks()
        inputMonitor.start()
        inputMonitor.requestAccessibility()

        menuBar = MenuBarController(settings: settings)
        menuBar.isAccessibilityTrusted = { [weak self] in self?.inputMonitor.isTrusted ?? true }
        menuBar.onToggleVisibility = { [weak self] in self?.toggleBuddy() }
        menuBar.onOpenSettings = { [weak self] in self?.openSettings() }
        menuBar.onRequestAccessibility = { [weak self] in
            self?.inputMonitor.requestAccessibility()
            self?.openAccessibilityPane()
        }

        if settings.buddyVisible {
            window.orderFrontRegardless()
        }
        quips.timeOfDayGreetingIfFresh()
    }

    private func wireCallbacks() {
        inputMonitor.onKeystroke = { [weak self] in
            guard let self else { return }
            self.scene.engine.handle(.keystroke(now: CACurrentMediaTime()))
            // Re-attach the key monitor lazily in case trust was just granted.
        }
        inputMonitor.onFrontmostAppChange = { [weak self] name in
            self?.quips.appSwitched(to: name)
        }
        scene.onBoop = { [weak self] in
            self?.quips.boopQuip()
        }
        scene.onStateChange = { [weak self] from, to, duration in
            // A dance that lasted >2 min counts as a typing marathon.
            if from == .dance, to != .dance, duration > 120 {
                self?.quips.typingMarathonEnded()
            }
        }

        // Periodically retry attaching the key monitor until trust is granted.
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { return timer.invalidate() }
                self.inputMonitor.startKeyMonitorIfPossible()
                if self.inputMonitor.isTrusted { timer.invalidate() }
            }
        }
    }

    private func toggleBuddy() {
        settings.buddyVisible.toggle()
        if settings.buddyVisible {
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
    }

    func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                settings: settings,
                onScaleChange: { [weak self] scale in self?.scene.setSpriteScale(scale) },
                onChatterChange: { [weak self] in self?.quips.scheduleIdleChatter() }
            )
        }
        settingsWindow?.show()
    }

    private func openAccessibilityPane() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
