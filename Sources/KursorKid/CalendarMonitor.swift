import EventKit
import KursorKidCore

/// Polls EventKit every 30 seconds for events on the enabled calendars and
/// fires `onReminder` ~2 minutes before each event starts (via the pure
/// ReminderScheduler, which guarantees one reminder per event).
///
/// Polling beats per-event timers here: every tick re-reads reality, so
/// sleep/wake, calendar edits, and timezone changes are self-healing.
@MainActor
final class CalendarMonitor {
    struct CalendarInfo: Identifiable, Equatable {
        let id: String
        let title: String
        let source: String
    }

    /// Called with the event title when a reminder is due.
    var onReminder: ((String) -> Void)?

    private let store = EKEventStore()
    private let settings: SettingsStore
    private let scheduler = ReminderScheduler()
    private var timer: Timer?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    var accessDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .denied || status == .restricted
    }

    /// Triggers the system permission prompt. Returns whether access was granted.
    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// All event calendars, sorted by account then name, for the Settings UI.
    func calendars() -> [CalendarInfo] {
        store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title) }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        poll()
    }

    private func poll() {
        guard settings.calendarRemindersEnabled, hasFullAccess else { return }

        let enabledIDs = settings.enabledCalendarIDs
        let calendars = store.calendars(for: .event)
            .filter { enabledIDs?.contains($0.calendarIdentifier) ?? true }
        guard !calendars.isEmpty else { return }

        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now, end: now.addingTimeInterval(3600), calendars: calendars
        )
        let upcoming = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map {
                UpcomingEvent(
                    id: $0.eventIdentifier ?? "\($0.title ?? "?")-\($0.startDate.timeIntervalSince1970)",
                    title: $0.title ?? "untitled",
                    startDate: $0.startDate
                )
            }

        for event in scheduler.dueReminders(events: upcoming, now: now) {
            onReminder?(event.title)
        }
    }
}
