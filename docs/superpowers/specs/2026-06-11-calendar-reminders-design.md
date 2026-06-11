# Calendar Reminders — Design

**Date:** 2026-06-11
**Status:** Approved (approach A — simple poller)

## Goal

Kiki reminds the user 2 minutes before any upcoming calendar event, via her
speech bubble plus an excited animation. The user picks which calendars count
in Settings.

## Source

EventKit (`EKEventStore`) — covers every account synced to macOS Calendar
(iCloud, Google, Exchange). Requires full-access calendar permission
(macOS 14+ `requestFullAccessToEvents`).

## Architecture

Follows the existing pure-core / AppKit-shell split (`BehaviorEngine` pattern).

### `ReminderScheduler` (KursorKidCore — pure, unit-tested)

- Input: `[UpcomingEvent]` (`id`, `title`, `startDate`) and `now`.
- Output: events due for a reminder — `startDate - now <= 120s` and event has
  not started yet (`startDate > now`).
- Tracks fired event IDs so each event reminds exactly once, surviving
  re-fetches. Fired-ID set is pruned to events still in the input window so it
  doesn't grow forever.
- All-day events are excluded upstream (CalendarMonitor's fetch predicate);
  the scheduler also ignores events whose start has already passed.
- No EventKit/AppKit imports. Deterministic given inputs.

### `CalendarMonitor` (app target)

- Wraps `EKEventStore`.
- `requestAccess()` — triggers the permission prompt; exposes current
  authorization status.
- `calendars()` — list of (id, title, account source title, color) for the
  Settings UI.
- Polls every 30 seconds: fetch the next hour of non-all-day events from
  enabled calendars, feed the scheduler with `Date()`, and for each due
  reminder call `QuipCoordinator.calendarReminder(title:)` and
  `BuddyScene.alertJump()`.
- 30s polling makes sleep/wake, calendar edits, and timezone changes
  self-healing — every tick re-reads reality. No per-event timers.

### Reminder delivery

- `QuipCoordinator.calendarReminder(title:)` — local templated lines
  (instant, no API), e.g. `"⏰ '<title>' in 2 min!! go go go"`. Respects
  `muted`; bypasses the Claude-line cooldown (reminders must not be dropped).
- `BuddyScene` excited moment: the existing startled jump + `celebrate()`
  hearts, reused — no new sprite art.

## Settings

### `SettingsStore` (KursorKidCore)

- `calendarRemindersEnabled: Bool` — default `false`.
- `enabledCalendarIDs: Set<String>?` — `nil` means "all calendars" (so newly
  added calendars are included by default until the user curates).

### `SettingsView` — new "Calendar" section

- Master toggle "Remind me before events".
- If authorization not granted: "Grant Calendar Access" button (and a hint to
  open System Settings if previously denied).
- Once granted: checkbox per calendar, grouped by account source.
  Toggling writes `enabledCalendarIDs` (first toggle materializes the `nil`
  "all" sentinel into an explicit set).

## Plumbing

- `build-app.sh` Info.plist heredoc: add `NSCalendarsFullAccessUsageDescription`.
- Signing entitlements: add `com.apple.security.personal-information.calendars`.
- EventKit permission requires a real app bundle — live testing goes through
  `build-app.sh`, not the bare debug binary.

## Testing

- **Unit (`ReminderSchedulerTests`):** fires at ≤2min; never fires twice for
  the same event; doesn't fire for events already started; fired-set pruning;
  works when the same event appears in successive fetches.
- **Live:** build + relaunch, grant permission, create a calendar event ~3
  minutes out, watch Kiki jump and announce it; verify a disabled calendar's
  event stays silent.

## Out of scope (YAGNI)

- Configurable lead time (fixed at 2 minutes).
- All-day event reminders.
- Snooze / acknowledge interactions.
- AI-generated reminder lines.
