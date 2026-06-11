import Foundation

/// A calendar event the scheduler can reason about. Built by the app target
/// from EKEvents; Core never imports EventKit.
public struct UpcomingEvent: Equatable, Sendable {
    public let id: String
    public let title: String
    public let startDate: Date

    public init(id: String, title: String, startDate: Date) {
        self.id = id
        self.title = title
        self.startDate = startDate
    }
}

/// Decides which events are due for a "starting soon" reminder. Pure and
/// deterministic given inputs (same pattern as BehaviorEngine): the caller
/// supplies the event window and the current time.
///
/// Each event fires exactly once. Fired IDs are pruned to the IDs present in
/// the current input window, so the set can't grow forever — once an event
/// drops out of the caller's fetch window it is forgotten.
public final class ReminderScheduler {
    public let leadTime: TimeInterval
    private var firedIDs: Set<String> = []

    public init(leadTime: TimeInterval = 120) {
        self.leadTime = leadTime
    }

    /// Events starting within `leadTime` of `now` that haven't started and
    /// haven't already been reminded about.
    public func dueReminders(events: [UpcomingEvent], now: Date) -> [UpcomingEvent] {
        firedIDs.formIntersection(Set(events.map(\.id)))
        let due = events.filter { event in
            let untilStart = event.startDate.timeIntervalSince(now)
            return untilStart > 0 && untilStart <= leadTime && !firedIDs.contains(event.id)
        }
        firedIDs.formUnion(due.map(\.id))
        return due
    }
}
