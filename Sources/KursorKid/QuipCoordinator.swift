import AppKit
import KursorKidCore

/// Decides WHEN Kiki talks (cooldowns, settings, mute) and delivers lines to
/// the scene. The QuipService decides WHAT she says.
@MainActor
final class QuipCoordinator {
    private let service: QuipService
    private let settings: SettingsStore
    private let inputMonitor: InputMonitor
    private weak var scene: BuddyScene?

    private var lastClickQuipAt: Date = .distantPast
    private var lastAppSwitchQuipAt: Date = .distantPast
    private var lastTimeOfDayQuipDay: Int = -1
    private var idleTimer: Timer?

    private let clickCooldown: TimeInterval = 10
    private let appSwitchCooldown: TimeInterval = 600

    init(service: QuipService, settings: SettingsStore, inputMonitor: InputMonitor, scene: BuddyScene) {
        self.service = service
        self.settings = settings
        self.inputMonitor = inputMonitor
        self.scene = scene
        scheduleIdleChatter()
    }

    // MARK: - Triggers

    func boopQuip() {
        guard settings.clickQuipsEnabled, !settings.muted else { return }
        guard Date().timeIntervalSince(lastClickQuipAt) >= clickCooldown else { return }
        lastClickQuipAt = Date()
        deliver(trigger: .clicked)
    }

    func typingMarathonEnded() {
        guard settings.contextReactionsEnabled, !settings.muted else { return }
        deliver(trigger: .typingMarathon)
    }

    func appSwitched(to name: String) {
        guard settings.contextReactionsEnabled, !settings.muted else { return }
        guard Date().timeIntervalSince(lastAppSwitchQuipAt) >= appSwitchCooldown else { return }
        lastAppSwitchQuipAt = Date()
        deliver(trigger: .appSwitch, appOverride: name)
    }

    func timeOfDayGreetingIfFresh() {
        guard settings.contextReactionsEnabled, !settings.muted else { return }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        guard day != lastTimeOfDayQuipDay else { return }
        lastTimeOfDayQuipDay = day
        deliver(trigger: .timeOfDay)
    }

    /// (Re)starts the idle chatter timer with ±25% jitter.
    func scheduleIdleChatter() {
        idleTimer?.invalidate()
        guard settings.idleChatterEnabled else { return }
        let base = TimeInterval(settings.idleIntervalMinutes * 60)
        let jittered = base * Double.random(in: 0.75...1.25)
        idleTimer = Timer.scheduledTimer(withTimeInterval: jittered, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.settings.idleChatterEnabled, !self.settings.muted {
                    self.deliver(trigger: .idle)
                }
                self.scheduleIdleChatter()
            }
        }
    }

    // MARK: - Delivery

    private func deliver(trigger: QuipTrigger, appOverride: String? = nil) {
        let app = settings.contextReactionsEnabled
            ? (appOverride ?? inputMonitor.frontmostAppName)
            : nil
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm 'on' EEEE"
        let timeOfDay = formatter.string(from: Date())

        Task { [weak self] in
            guard let self else { return }
            let line = await self.service.fetchQuip(
                trigger: trigger, timeOfDay: timeOfDay, frontmostApp: app
            )
            await MainActor.run {
                self.scene?.showBubble(line)
            }
        }
    }
}
