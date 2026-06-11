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
    private var lastClaudeLineAt: Date = .distantPast
    private var idleTimer: Timer?

    private let clickCooldown: TimeInterval = 10
    private let appSwitchCooldown: TimeInterval = 600
    private let claudeLineCooldown: TimeInterval = 45

    /// Local lines for Claude Code events — instant, never hit the API.
    private let claudeDoneLines = [
        "done!! come look 👀",
        "claude's finished. inspect the goods.",
        "ding! fresh code, hot out the oven.",
        "all done. i supervised, you're welcome.",
        "finished! i watched the whole time.",
    ]
    private let claudeWaitingLines = [
        "hey. HEY. claude needs you.",
        "claude's waiting on you, choom.",
        "input required!! this is not a drill.",
        "claude said knock knock. answer it.",
        "psst — terminal wants your attention.",
    ]

    /// Reminder templates — `%@` is the event title. Local and instant.
    private let calendarReminderLines = [
        "⏰ '%@' in 2 min!! go go go",
        "heads up — '%@' starts in 2 minutes 🏃‍♀️",
        "psst. '%@'. two minutes. don't be late!",
        "ding ding!! '%@' is about to start ⏰",
    ]

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

    func claudeDone() {
        showClaudeLine(claudeDoneLines.randomElement()!)
    }

    func claudeWaiting() {
        showClaudeLine(claudeWaitingLines.randomElement()!)
    }

    /// Calendar event starting in ~2 minutes. No cooldown: reminders are
    /// time-critical and must never be dropped. Respects mute.
    func calendarReminder(title: String) {
        guard !settings.muted else { return }
        let template = calendarReminderLines.randomElement()!
        scene?.showBubble(String(format: template, title))
        scene?.alertJump()
    }

    private func showClaudeLine(_ line: String) {
        guard !settings.muted else { return }
        guard Date().timeIntervalSince(lastClaudeLineAt) >= claudeLineCooldown else { return }
        lastClaudeLineAt = Date()
        scene?.showBubble(line)
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
