# Calendar Reminders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kiki reminds the user 2 minutes before calendar events via her speech bubble + an excited jump, with per-calendar selection in Settings.

**Architecture:** Pure decision logic (`ReminderScheduler`) lives in `KursorKidCore` and is unit-tested; an EventKit-facing `CalendarMonitor` in the app target polls every 30 seconds and delivers reminders through the existing `QuipCoordinator` → `BuddyScene` path. Spec: `docs/superpowers/specs/2026-06-11-calendar-reminders-design.md`.

**Tech Stack:** Swift 5.10 SwiftPM (no Xcode project), EventKit, SwiftUI settings form, XCTest. Build with `swift build`, test with `swift test`, app bundle via `scripts/build-app.sh`.

**House rules for the executor:**
- This is a SwiftPM repo. `KursorKidCore` must stay free of AppKit/EventKit imports.
- Run `swift test` from the repo root: `/Users/dep/Sites/kursor-kid`.
- Commit messages: conventional style (`feat:`, `test:`, `chore:`), each ending with the line `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Do not push to remote.

---

### Task 1: `ReminderScheduler` (pure core logic)

**Files:**
- Create: `Sources/KursorKidCore/ReminderScheduler.swift`
- Create: `Tests/KursorKidCoreTests/ReminderSchedulerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/KursorKidCoreTests/ReminderSchedulerTests.swift`:

```swift
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
        let later = scheduler.dueReminders(
            events: [event("a", startsIn: 90)], now: now.addingTimeInterval(86_400)
        )
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ReminderSchedulerTests 2>&1 | tail -5`
Expected: compile error — `UpcomingEvent` / `ReminderScheduler` not defined.

- [ ] **Step 3: Write the implementation**

Create `Sources/KursorKidCore/ReminderScheduler.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ReminderSchedulerTests 2>&1 | tail -3`
Expected: `Executed 9 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/KursorKidCore/ReminderScheduler.swift Tests/KursorKidCoreTests/ReminderSchedulerTests.swift
git commit -m "feat: pure ReminderScheduler for calendar event warnings

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Settings storage for calendar preferences

**Files:**
- Modify: `Sources/KursorKidCore/SettingsStore.swift`
- Modify: `Tests/KursorKidCoreTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

In `Tests/KursorKidCoreTests/SettingsStoreTests.swift`, add inside the class (it already builds a fresh `UserDefaults(suiteName:)` + `SettingsStore` in `setUp`):

```swift
    func testCalendarDefaults() {
        XCTAssertFalse(store.calendarRemindersEnabled)
        XCTAssertNil(store.enabledCalendarIDs, "nil means all calendars")
    }

    func testCalendarRoundTrip() {
        store.calendarRemindersEnabled = true
        store.enabledCalendarIDs = ["work-id", "home-id"]
        XCTAssertTrue(store.calendarRemindersEnabled)
        XCTAssertEqual(store.enabledCalendarIDs, ["work-id", "home-id"])
    }

    func testEnabledCalendarIDsCanResetToAll() {
        store.enabledCalendarIDs = ["work-id"]
        store.enabledCalendarIDs = nil
        XCTAssertNil(store.enabledCalendarIDs)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SettingsStoreTests 2>&1 | tail -5`
Expected: compile error — `calendarRemindersEnabled` not defined.

- [ ] **Step 3: Implement the properties**

In `Sources/KursorKidCore/SettingsStore.swift`, add to the `Key` enum:

```swift
        static let calendarReminders = "calendarRemindersEnabled"
        static let enabledCalendarIDs = "enabledCalendarIDs"
```

Add the properties after `buddyVisible` (before `private func bool`):

```swift
    public var calendarRemindersEnabled: Bool {
        get { bool(Key.calendarReminders, default: false) }
        set { defaults.set(newValue, forKey: Key.calendarReminders) }
    }

    /// Calendar IDs enabled for event reminders. `nil` means all calendars,
    /// so newly added calendars are included until the user curates the list.
    public var enabledCalendarIDs: Set<String>? {
        get { (defaults.array(forKey: Key.enabledCalendarIDs) as? [String]).map(Set.init) }
        set {
            if let newValue {
                defaults.set(Array(newValue).sorted(), forKey: Key.enabledCalendarIDs)
            } else {
                defaults.removeObject(forKey: Key.enabledCalendarIDs)
            }
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter SettingsStoreTests 2>&1 | tail -3`
Expected: all SettingsStoreTests pass, including the 3 new ones.

- [ ] **Step 5: Commit**

```bash
git add Sources/KursorKidCore/SettingsStore.swift Tests/KursorKidCoreTests/SettingsStoreTests.swift
git commit -m "feat: calendar reminder settings storage

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Excited alert jump in `BuddyScene`

The app target has no test target — verification for Tasks 3–6 is `swift build` plus the live check in Task 8.

**Files:**
- Modify: `Sources/KursorKid/BuddyScene.swift` (add next to `celebrate()`, which is around line 85)

- [ ] **Step 1: Add `alertJump()`**

In `Sources/KursorKid/BuddyScene.swift`, directly after the `celebrate()` method, add:

```swift
    /// Calendar reminder: an urgent double hop with hearts to catch the eye.
    /// Purely cosmetic — does not touch the behavior engine's state.
    func alertJump() {
        guard !isDragging else { return }
        spawnHearts()
        sprite.run(.sequence([
            .moveBy(x: 0, y: 26, duration: 0.12),
            .moveBy(x: 0, y: -26, duration: 0.16),
            .moveBy(x: 0, y: 16, duration: 0.1),
            .moveBy(x: 0, y: -16, duration: 0.14),
        ]), withKey: "celebrate")
    }
```

- [ ] **Step 2: Verify it builds**

Run: `swift build 2>&1 | tail -2`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/KursorKid/BuddyScene.swift
git commit -m "feat: alertJump animation for calendar reminders

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Reminder lines in `QuipCoordinator`

**Files:**
- Modify: `Sources/KursorKid/QuipCoordinator.swift`

- [ ] **Step 1: Add the local lines and trigger method**

In `Sources/KursorKid/QuipCoordinator.swift`, after the `claudeWaitingLines` array, add:

```swift
    /// Reminder templates — `%@` is the event title. Local and instant.
    private let calendarReminderLines = [
        "⏰ '%@' in 2 min!! go go go",
        "heads up — '%@' starts in 2 minutes 🏃‍♀️",
        "psst. '%@'. two minutes. don't be late!",
        "ding ding!! '%@' is about to start ⏰",
    ]
```

After the `claudeWaiting()` method, add:

```swift
    /// Calendar event starting in ~2 minutes. No cooldown: reminders are
    /// time-critical and must never be dropped. Respects mute.
    func calendarReminder(title: String) {
        guard !settings.muted else { return }
        let template = calendarReminderLines.randomElement()!
        scene?.showBubble(String(format: template, title))
        scene?.alertJump()
    }
```

- [ ] **Step 2: Verify it builds**

Run: `swift build 2>&1 | tail -2`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/KursorKid/QuipCoordinator.swift
git commit -m "feat: calendar reminder speech bubble lines

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: `CalendarMonitor` (EventKit adapter)

**Files:**
- Create: `Sources/KursorKid/CalendarMonitor.swift`

- [ ] **Step 1: Create the monitor**

Create `Sources/KursorKid/CalendarMonitor.swift`:

```swift
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
```

- [ ] **Step 2: Verify it builds**

Run: `swift build 2>&1 | tail -2`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/KursorKid/CalendarMonitor.swift
git commit -m "feat: CalendarMonitor polls EventKit for upcoming events

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Settings UI — Calendar section

**Files:**
- Modify: `Sources/KursorKid/SettingsView.swift`
- Modify: `Sources/KursorKid/AppDelegate.swift`

`SettingsView` gains a `calendarMonitor` dependency, threaded through `SettingsWindowController` from `AppDelegate`.

- [ ] **Step 1: Add the dependency and state to `SettingsView`**

In `Sources/KursorKid/SettingsView.swift` (no new imports needed — all EventKit access goes through `CalendarMonitor`):

Add a stored property right after `let settings: SettingsStore`:

```swift
    let calendarMonitor: CalendarMonitor
```

Add state vars next to the existing `@State` block:

```swift
    @State private var calendarReminders: Bool
    @State private var calendars: [CalendarMonitor.CalendarInfo] = []
    @State private var enabledIDs: Set<String>?
    @State private var hasCalendarAccess = false
    @State private var calendarAccessDenied = false
```

Replace the `init` with (one new parameter + two new `State(initialValue:)` lines):

```swift
    init(settings: SettingsStore, calendarMonitor: CalendarMonitor, onScaleChange: @escaping (Int) -> Void, onChatterChange: @escaping () -> Void) {
        self.settings = settings
        self.calendarMonitor = calendarMonitor
        self.onScaleChange = onScaleChange
        self.onChatterChange = onChatterChange
        _clickQuips = State(initialValue: settings.clickQuipsEnabled)
        _idleChatter = State(initialValue: settings.idleChatterEnabled)
        _contextReactions = State(initialValue: settings.contextReactionsEnabled)
        _idleInterval = State(initialValue: Double(settings.idleIntervalMinutes))
        _muted = State(initialValue: settings.muted)
        _scale = State(initialValue: settings.spriteScale)
        _calendarReminders = State(initialValue: settings.calendarRemindersEnabled)
        _enabledIDs = State(initialValue: settings.enabledCalendarIDs)
    }
```

- [ ] **Step 2: Add the Calendar section to the form**

In `body`, after the `Section("Chatter") { ... }` block and before `Section("Behavior")`, add:

```swift
            Section("Calendar") {
                Toggle("Remind me 2 min before events", isOn: $calendarReminders)
                    .onChange(of: calendarReminders) { _, v in
                        settings.calendarRemindersEnabled = v
                        if v { refreshCalendarAccess() }
                    }
                if calendarReminders {
                    if hasCalendarAccess {
                        calendarPicker
                    } else if calendarAccessDenied {
                        Label("Calendar access denied", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars")!)
                        }
                    } else {
                        Button("Grant Calendar Access") {
                            Task {
                                _ = await calendarMonitor.requestAccess()
                                refreshCalendarAccess()
                            }
                        }
                    }
                }
            }
```

- [ ] **Step 3: Add the picker view and helpers**

After the `body` property (before `private func testKey()`), add:

```swift
    /// Checkbox per calendar, grouped by account source.
    private var calendarPicker: some View {
        let grouped = Dictionary(grouping: calendars, by: \.source)
        return ForEach(grouped.keys.sorted(), id: \.self) { source in
            VStack(alignment: .leading, spacing: 4) {
                Text(source).font(.caption).foregroundStyle(.secondary)
                ForEach(grouped[source]!) { calendar in
                    Toggle(calendar.title, isOn: calendarBinding(calendar.id))
                }
            }
        }
    }

    private func calendarBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { enabledIDs?.contains(id) ?? true },
            set: { isOn in
                // First curation materializes the "all calendars" nil sentinel.
                var ids = enabledIDs ?? Set(calendars.map(\.id))
                if isOn { ids.insert(id) } else { ids.remove(id) }
                enabledIDs = ids
                settings.enabledCalendarIDs = ids
            }
        )
    }

    private func refreshCalendarAccess() {
        hasCalendarAccess = calendarMonitor.hasFullAccess
        calendarAccessDenied = calendarMonitor.accessDenied
        if hasCalendarAccess {
            calendars = calendarMonitor.calendars()
        }
    }
```

Then add an `.onAppear` modifier to the `Form`, right before `.formStyle(.grouped)`:

```swift
        .onAppear { refreshCalendarAccess() }
```

- [ ] **Step 4: Thread the monitor through `SettingsWindowController`**

Still in `SettingsView.swift`, update `SettingsWindowController`:

Add a stored property after `private let settings: SettingsStore`:

```swift
    private let calendarMonitor: CalendarMonitor
```

Replace its `init` with:

```swift
    init(settings: SettingsStore, calendarMonitor: CalendarMonitor, onScaleChange: @escaping (Int) -> Void, onChatterChange: @escaping () -> Void) {
        self.settings = settings
        self.calendarMonitor = calendarMonitor
        self.onScaleChange = onScaleChange
        self.onChatterChange = onChatterChange
    }
```

In `show()`, update the `SettingsView(...)` construction to pass it:

```swift
            let view = SettingsView(
                settings: settings,
                calendarMonitor: calendarMonitor,
                onScaleChange: onScaleChange,
                onChatterChange: onChatterChange
            )
```

- [ ] **Step 5: Wire up `AppDelegate`**

In `Sources/KursorKid/AppDelegate.swift`:

Add a stored property after `private var quips: QuipCoordinator!`:

```swift
    private var calendarMonitor: CalendarMonitor!
```

In `applicationDidFinishLaunching`, after the `quips = QuipCoordinator(...)` line, add:

```swift
        calendarMonitor = CalendarMonitor(settings: settings)
        calendarMonitor.onReminder = { [weak self] title in
            self?.quips.calendarReminder(title: title)
        }
        calendarMonitor.start()
```

In `openSettings()`, update the `SettingsWindowController` construction:

```swift
            settingsWindow = SettingsWindowController(
                settings: settings,
                calendarMonitor: calendarMonitor,
                onScaleChange: { [weak self] scale in self?.scene.setSpriteScale(scale) },
                onChatterChange: { [weak self] in self?.quips.scheduleIdleChatter() }
            )
```

- [ ] **Step 6: Build and run all tests**

Run: `swift build 2>&1 | tail -2 && swift test 2>&1 | tail -3`
Expected: `Build complete!` and 0 failures (50 tests: 38 existing + 9 scheduler + 3 settings).

- [ ] **Step 7: Commit**

```bash
git add Sources/KursorKid/SettingsView.swift Sources/KursorKid/AppDelegate.swift
git commit -m "feat: calendar picker in settings + reminder wiring

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Bundle plumbing (usage description + entitlement)

EventKit needs a usage-description string in Info.plist and, because the app signs with hardened runtime, the calendars entitlement.

**Files:**
- Modify: `scripts/build-app.sh`

- [ ] **Step 1: Add the usage description to the Info.plist heredoc**

In `scripts/build-app.sh`, inside the `cat > "$APP/Contents/Info.plist" <<PLIST` heredoc, add this line right after `<key>LSUIElement</key><true/>`:

```xml
    <key>NSCalendarsFullAccessUsageDescription</key><string>Kiki reads your upcoming events so she can remind you before they start.</string>
```

- [ ] **Step 2: Sign with the calendars entitlement**

In `scripts/build-app.sh`, replace the signing block:

```bash
echo "▸ Signing with hardened runtime"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
```

with:

```bash
echo "▸ Signing with hardened runtime"
ENTITLEMENTS="/tmp/kursorkid-entitlements.plist"
cat > "$ENTITLEMENTS" <<EPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.personal-information.calendars</key><true/>
</dict>
</plist>
EPLIST
codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
```

(Keep the `codesign --verify --strict "$APP"` line that follows.)

- [ ] **Step 3: Build the app bundle to verify the script works**

Run: `./scripts/build-app.sh 2>&1 | tail -3`
Expected: `✓ Signed app at dist/Kursor Kid.app`.

Then verify the entitlement landed:

Run: `codesign -d --entitlements - "dist/Kursor Kid.app" 2>/dev/null | grep -A1 calendars`
Expected: output contains `com.apple.security.personal-information.calendars`.

- [ ] **Step 4: Commit**

```bash
git add scripts/build-app.sh
git commit -m "chore: calendar usage description + entitlement in app bundle

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Live verification

No code in this task — prove it works end to end.

- [ ] **Step 1: Relaunch the freshly built app**

```bash
pkill -9 KursorKid || true; sleep 1
open "/Users/dep/Sites/kursor-kid/dist/Kursor Kid.app"
```

- [ ] **Step 2: Create a test event ~3 minutes out**

```bash
osascript <<'EOS'
set eventStart to (current date) + (3 * minutes)
set eventEnd to eventStart + (15 * minutes)
tell application "Calendar"
    tell calendar 1
        make new event with properties {summary:"Kiki test event", start date:eventStart, end date:eventEnd}
    end tell
end tell
EOS
```

(If osascript lacks Calendar automation permission, ask the user to create the event by hand instead.)

- [ ] **Step 3: Ask the user to verify**

Ask the user to:
1. Open Settings from the menu bar → enable "Remind me 2 min before events" → click "Grant Calendar Access" → approve the system prompt → confirm their calendars appear as checkboxes.
2. Wait ~1 minute: Kiki should do a double hop with hearts and say a bubble line naming "Kiki test event".
3. Delete the test event afterward.

Report the result honestly; if she doesn't fire, debug before marking this task complete.

---

## Final checks

- [ ] `swift test` — all green.
- [ ] `git log --oneline` shows one commit per task (7 commits).
- [ ] Do NOT push — leave that to the user.
