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
    private var calendarMonitor: CalendarMonitor!
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

        calendarMonitor = CalendarMonitor(settings: settings)
        calendarMonitor.onReminder = { [weak self] title in
            self?.quips.calendarReminder(title: title)
        }
        calendarMonitor.start()

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
        scheduleSelfShotIfRequested(view: skView)
    }

    // MARK: - kursorkid:// URL scheme (Claude Code hooks)

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handle(url) }
    }

    /// `kursorkid://claude/<thinking|working|waiting|done|clear>`
    private func handle(_ url: URL) {
        guard url.scheme == "kursorkid", url.host == "claude" else { return }
        let now = CACurrentMediaTime()
        switch url.lastPathComponent {
        case "thinking":
            scene.engine.handle(.claudeStatus(.thinking, now: now))
        case "working":
            scene.engine.handle(.claudeStatus(.working, now: now))
        case "waiting":
            let wasWaiting = scene.engine.claudeStatus == .waiting
            scene.engine.handle(.claudeStatus(.waiting, now: now))
            if !wasWaiting { quips.claudeWaiting() }
        case "done":
            let wasActive = scene.engine.claudeStatus != nil
            scene.engine.handle(.claudeStatus(nil, now: now))
            if wasActive {
                scene.celebrate()
                quips.claudeDone()
            }
        case "clear":
            scene.engine.handle(.claudeStatus(nil, now: now))
        default:
            break
        }
    }

    /// Dev utility: `--self-shot <path>` renders the scene to a PNG after a
    /// short warmup so behavior can be verified without screen recording
    /// permission. `--demo-bubble` shows a canned line first.
    private func scheduleSelfShotIfRequested(view: SKView) {
        guard let flagIndex = CommandLine.arguments.firstIndex(of: "--self-shot"),
              CommandLine.arguments.count > flagIndex + 1 else { return }
        let path = CommandLine.arguments[flagIndex + 1]
        if CommandLine.arguments.contains("--demo-bubble") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.scene.showBubble(CannedQuips.line(for: .clicked))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, let texture = view.texture(from: self.scene),
                  let cg = texture.cgImage() as CGImage? else {
                print("self-shot failed")
                NSApp.terminate(nil)
                return
            }
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: path))
            print("self-shot written to \(path)")
            NSApp.terminate(nil)
        }
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
                calendarMonitor: calendarMonitor,
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
