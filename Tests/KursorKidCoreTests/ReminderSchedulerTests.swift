import XCTest
@testable import KursorKidCore

final class ReminderSchedulerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func event(_ id: String, startsIn seconds: TimeInterval) -> UpcomingEvent {
        UpcomingEvent(id: id, title: "Event \(id)", startDate: now.addingTimeInterval(seconds))
    }

    func testFiresForEventWithinLeadTime() {
        let scheduler = ReminderScheduler()
        let due = scheduler.dueReminders(events: [event("a", startsIn: 90)], now: now)
        XCTAssertEqual(due.map(\.id), ["a"])
    }

    func testFiresExactlyAtLeadTimeBoundary() {
        let scheduler = ReminderScheduler()
        let due = scheduler.dueReminders(events: [event("a", startsIn: 120)], now: now)
        XCTAssertEqual(due.map(\.id), ["a"])
    }

    func testDoesNotFireForEventBeyondLeadTime() {
        let scheduler = ReminderScheduler()
        let due = scheduler.dueReminders(events: [event("a", startsIn: 300)], now: now)
        XCTAssertTrue(due.isEmpty)
    }

    func testDoesNotFireForEventAlreadyStarted() {
        let scheduler = ReminderScheduler()
        let due = scheduler.dueReminders(events: [event("a", startsIn: -30)], now: now)
        XCTAssertTrue(due.isEmpty)
    }

    func testNeverFiresTwiceForSameEvent() {
        let scheduler = ReminderScheduler()
        _ = scheduler.dueReminders(events: [event("a", startsIn: 90)], now: now)
        let again = scheduler.dueReminders(
            events: [event("a", startsIn: 60)], now: now.addingTimeInterval(30)
        )
        XCTAssertTrue(again.isEmpty)
    }

    func testFiredEventStaysSuppressedWhileStillInFetchWindow() {
        let scheduler = ReminderScheduler()
        _ = scheduler.dueReminders(events: [event("a", startsIn: 110)], now: now)
        // Event is now ongoing (started 10s ago) but still appears in the
        // fetch window — must stay suppressed.
        let during = scheduler.dueReminders(
            events: [event("a", startsIn: -10)], now: now
        )
        XCTAssertTrue(during.isEmpty)
    }

    func testFiredSetPrunesEventsThatLeftTheWindow() {
        let scheduler = ReminderScheduler()
        _ = scheduler.dueReminders(events: [event("a", startsIn: 90)], now: now)
        // Event disappears from the window (ended or cancelled) ...
        _ = scheduler.dueReminders(events: [], now: now.addingTimeInterval(600))
        // ... then an event reusing the same ID (e.g. restored) may fire again.
        // The new occurrence starts 90s from the later "now", not from self.now.
        let laterNow = now.addingTimeInterval(86_400)
        let restoredEvent = UpcomingEvent(id: "a", title: "Event a", startDate: laterNow.addingTimeInterval(90))
        let later = scheduler.dueReminders(events: [restoredEvent], now: laterNow)
        XCTAssertEqual(later.map(\.id), ["a"])
    }

    func testMultipleEventsFireIndependently() {
        let scheduler = ReminderScheduler()
        let due = scheduler.dueReminders(
            events: [event("a", startsIn: 90), event("b", startsIn: 600), event("c", startsIn: 30)],
            now: now
        )
        XCTAssertEqual(Set(due.map(\.id)), ["a", "c"])
    }

    func testCustomLeadTime() {
        let scheduler = ReminderScheduler(leadTime: 300)
        let due = scheduler.dueReminders(events: [event("a", startsIn: 240)], now: now)
        XCTAssertEqual(due.map(\.id), ["a"])
    }
}
