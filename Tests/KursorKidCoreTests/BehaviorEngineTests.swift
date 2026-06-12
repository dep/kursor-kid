import XCTest
@testable import KursorKidCore

final class BehaviorEngineTests: XCTestCase {
    /// random stub: sit-roll range (0...1) returns `sitRoll`; everything else returns upperBound.
    private func makeEngine(sitRoll: CGFloat = 1.0) -> BehaviorEngine {
        BehaviorEngine(random: { range in
            range == 0...1 ? sitRoll : range.upperBound
        })
    }

    private let far: CGFloat = 1000

    /// Convenience: a tick with the cursor far away and not moving.
    private func tick(_ engine: BehaviorEngine, at now: TimeInterval, distance: CGFloat = 1000, cursorX: CGFloat = 2000) {
        engine.handle(.tick(now: now, cursorDistance: distance, cursorX: cursorX))
    }

    // MARK: Typing → dance

    func testFastTypingTriggersDance() {
        let engine = makeEngine()
        tick(engine, at: 0)
        var t: TimeInterval = 0
        while t <= 4.0 {
            engine.handle(.keystroke(now: t))
            t += 0.2 // 5 keys/sec
        }
        XCTAssertEqual(engine.state, .dance)
    }

    func testSlowTypingDoesNotTriggerDance() {
        let engine = makeEngine()
        tick(engine, at: 0)
        var t: TimeInterval = 0
        while t <= 4.0 {
            engine.handle(.keystroke(now: t))
            t += 0.5 // 2 keys/sec
        }
        XCTAssertNotEqual(engine.state, .dance)
    }

    func testDanceEndsAfterTypingStops() {
        let engine = makeEngine()
        tick(engine, at: 0)
        var t: TimeInterval = 0
        while t <= 4.0 {
            engine.handle(.keystroke(now: t))
            t += 0.2
        }
        XCTAssertEqual(engine.state, .dance)
        tick(engine, at: 4.0 + 3.1) // 3.1s after last key
        XCTAssertEqual(engine.state, .idle)
    }

    // MARK: Cursor proximity

    func testWaveWhenCursorNear() {
        let engine = makeEngine()
        tick(engine, at: 0)
        tick(engine, at: 1, distance: 100, cursorX: 100)
        XCTAssertEqual(engine.state, .wave)
        tick(engine, at: 2, distance: 400, cursorX: 400)
        XCTAssertEqual(engine.state, .idle)
    }

    func testStartledWhenVeryCloseWithCooldown() {
        let engine = makeEngine()
        tick(engine, at: 0)
        tick(engine, at: 1, distance: 50, cursorX: 50)
        XCTAssertEqual(engine.state, .startled)
        engine.handle(.animationFinished(now: 1.5))
        XCTAssertEqual(engine.state, .wave) // still within wave band
        tick(engine, at: 2, distance: 50, cursorX: 55) // within 4s cooldown
        XCTAssertEqual(engine.state, .wave)
        tick(engine, at: 5.5, distance: 50, cursorX: 60) // cooldown elapsed
        XCTAssertEqual(engine.state, .startled)
    }

    // MARK: Click → boop

    func testClickBoopsThenReturnsToIdle() {
        let engine = makeEngine()
        tick(engine, at: 0)
        engine.handle(.clicked(now: 1))
        XCTAssertEqual(engine.state, .boop)
        engine.handle(.animationFinished(now: 2))
        XCTAssertEqual(engine.state, .idle)
    }

    // MARK: Sleep

    func testSleepsAfterInactivityAndWakesOnKeystroke() {
        let engine = makeEngine()
        var t: TimeInterval = 0
        while t <= 301 {
            tick(engine, at: t)
            if case .wander = engine.state {
                engine.handle(.animationFinished(now: t))
            } else if engine.state == .chaseCursor {
                engine.handle(.animationFinished(now: t))
            }
            t += 1
        }
        XCTAssertEqual(engine.state, .sleep)
        engine.handle(.keystroke(now: 302))
        XCTAssertNotEqual(engine.state, .sleep)
    }

    func testCursorMovementPreventsSleep() {
        let engine = makeEngine()
        var t: TimeInterval = 0
        var x: CGFloat = 2000
        while t <= 301 {
            x += 10 // cursor keeps moving
            tick(engine, at: t, distance: 1000, cursorX: x)
            if case .wander = engine.state {
                engine.handle(.animationFinished(now: t))
            }
            t += 1
        }
        XCTAssertNotEqual(engine.state, .sleep)
    }

    // MARK: Drag

    func testDragOverridesDanceAndEndsIdle() {
        let engine = makeEngine()
        tick(engine, at: 0)
        var t: TimeInterval = 0
        while t <= 4.0 {
            engine.handle(.keystroke(now: t))
            t += 0.2
        }
        XCTAssertEqual(engine.state, .dance)
        engine.handle(.dragStarted)
        XCTAssertEqual(engine.state, .dragged)
        engine.handle(.keystroke(now: 4.1)) // typing while dragged: no dance
        XCTAssertEqual(engine.state, .dragged)
        engine.handle(.dragEnded(now: 5))
        XCTAssertEqual(engine.state, .idle)
    }

    // MARK: Wander

    func testWandersAfterIdleInterval() {
        let engine = makeEngine() // wander interval = upperBound = 20s
        tick(engine, at: 0)
        tick(engine, at: 21)
        guard case .wander(let targetX) = engine.state else {
            return XCTFail("expected wander, got \(engine.state)")
        }
        XCTAssertEqual(targetX, 1.0) // random stub returns upperBound of 0...1
        engine.handle(.animationFinished(now: 22))
        XCTAssertEqual(engine.state, .idle)
    }

    func testSitAfterWanderWhenRollIsLow() {
        let engine = makeEngine(sitRoll: 0.1)
        tick(engine, at: 0)
        // Move the cursor at t=21 (when wander fires) to reset the activity
        // clock; this keeps the wind-down timer well under 30s at t=33.
        tick(engine, at: 21, cursorX: 2010)
        // sit-roll stub also makes wander targetX = 0.1; state is wander
        engine.handle(.animationFinished(now: 22))
        XCTAssertEqual(engine.state, .sit)
        tick(engine, at: 33) // sit duration (10s) elapsed, idleFor=12 < drowsyAfter
        XCTAssertEqual(engine.state, .idle)
    }

    // MARK: Staged drowsiness

    /// Ticks an idle engine (cursor far, parked) once per second through
    /// `range`, finishing any wander/chase walks so she returns to calm states.
    private func idle(_ engine: BehaviorEngine, through range: ClosedRange<TimeInterval>) {
        var t = range.lowerBound
        while t <= range.upperBound {
            tick(engine, at: t)
            if case .wander = engine.state {
                engine.handle(.animationFinished(now: t))
            } else if engine.state == .chaseCursor {
                engine.handle(.animationFinished(now: t))
            }
            t += 1
        }
    }

    func testDrowsyAtThirtySeconds() {
        let engine = makeEngine()
        idle(engine, through: 0...31)
        XCTAssertEqual(engine.state, .drowsy)
    }

    func testDozingAtSixtySeconds() {
        let engine = makeEngine()
        idle(engine, through: 0...61)
        XCTAssertEqual(engine.state, .dozing)
    }

    func testDeepSleepAtNinetySeconds() {
        let engine = makeEngine()
        idle(engine, through: 0...91)
        XCTAssertEqual(engine.state, .sleep)
    }

    func testCursorMovementWakesDrowsyAndResetsTimer() {
        let engine = makeEngine()
        idle(engine, through: 0...35)
        XCTAssertEqual(engine.state, .drowsy)
        tick(engine, at: 36, cursorX: 2400) // cursor moved
        XCTAssertEqual(engine.state, .idle)
        idle(engine, through: 37...50) // 36+30=66, so no drowsiness yet
        XCTAssertNotEqual(engine.state, .drowsy)
    }

    func testCursorMovementWakesDozing() {
        let engine = makeEngine()
        idle(engine, through: 0...65)
        XCTAssertEqual(engine.state, .dozing)
        tick(engine, at: 66, cursorX: 2400)
        XCTAssertEqual(engine.state, .idle)
    }

    func testCursorMovementDoesNotWakeDeepSleep() {
        let engine = makeEngine()
        idle(engine, through: 0...95)
        XCTAssertEqual(engine.state, .sleep)
        tick(engine, at: 96, cursorX: 2400) // cursor moved
        XCTAssertEqual(engine.state, .sleep, "deep sleep ignores the mouse")
        tick(engine, at: 97, cursorX: 2400)
        XCTAssertEqual(engine.state, .sleep, "and stays asleep on later ticks")
    }

    func testKeystrokeWakesDeepSleep() {
        let engine = makeEngine()
        idle(engine, through: 0...95)
        engine.handle(.keystroke(now: 96))
        XCTAssertEqual(engine.state, .idle)
    }

    func testClickWakesDeepSleepViaBoop() {
        let engine = makeEngine()
        idle(engine, through: 0...95)
        engine.handle(.clicked(now: 96))
        XCTAssertEqual(engine.state, .boop)
        engine.handle(.animationFinished(now: 97))
        XCTAssertEqual(engine.state, .idle)
        tick(engine, at: 98)
        XCTAssertEqual(engine.state, .idle, "activity reset the wind-down timer")
    }

    func testAwakenWakesEveryStage() {
        for threshold: TimeInterval in [31, 61, 91] {
            let engine = makeEngine()
            idle(engine, through: 0...threshold)
            engine.handle(.awaken(now: threshold + 1))
            XCTAssertEqual(engine.state, .idle, "awaken failed at t=\(threshold)")
        }
    }

    func testNoDrowsinessWhileClaudeIsActive() {
        let engine = makeEngine()
        engine.handle(.claudeStatus(.working, now: 0))
        idle(engine, through: 0...120) // under the 180s staleness timeout
        XCTAssertEqual(engine.state, .claudeWorking)
    }

    func testSittingStillWindsDown() {
        let engine = makeEngine(sitRoll: 0.0) // wander always ends in a sit
        idle(engine, through: 0...35)
        XCTAssertEqual(engine.state, .drowsy, "sit is a calm state; the wind-down continues")
    }

    // MARK: Chase

    func testChasesParkedFarCursor() {
        let engine = makeEngine()
        var t: TimeInterval = 0
        while t <= 11 {
            tick(engine, at: t, distance: 400, cursorX: 400)
            t += 1
        }
        XCTAssertEqual(engine.state, .chaseCursor)
        engine.handle(.animationFinished(now: 12))
        XCTAssertEqual(engine.state, .idle)
    }
}

// MARK: - Claude Code status

extension BehaviorEngineTests {
    private func freshEngine() -> BehaviorEngine {
        BehaviorEngine(random: { $0.upperBound })
    }

    func testClaudeStatusPinsState() {
        let engine = freshEngine()
        engine.handle(.tick(now: 0, cursorDistance: 1000, cursorX: 2000))
        engine.handle(.claudeStatus(.working, now: 1))
        XCTAssertEqual(engine.state, .claudeWorking)
        // Ticks don't wander/sleep/chase away from claude states.
        engine.handle(.tick(now: 30, cursorDistance: 1000, cursorX: 2000))
        XCTAssertEqual(engine.state, .claudeWorking)
    }

    func testClaudeStatusSuppressesTypingDance() {
        let engine = freshEngine()
        engine.handle(.claudeStatus(.thinking, now: 0))
        var t: TimeInterval = 0
        while t <= 4 {
            engine.handle(.keystroke(now: t))
            t += 0.2
        }
        XCTAssertEqual(engine.state, .claudeThinking)
    }

    func testBoopReturnsToClaudeState() {
        let engine = freshEngine()
        engine.handle(.claudeStatus(.waiting, now: 0))
        engine.handle(.clicked(now: 1))
        XCTAssertEqual(engine.state, .boop)
        engine.handle(.animationFinished(now: 2))
        XCTAssertEqual(engine.state, .claudeWaiting)
    }

    func testClearReturnsToIdle() {
        let engine = freshEngine()
        engine.handle(.claudeStatus(.working, now: 0))
        engine.handle(.claudeStatus(nil, now: 5))
        XCTAssertEqual(engine.state, .idle)
    }

    func testStaleClaudeStatusTimesOut() {
        let engine = freshEngine()
        engine.handle(.claudeStatus(.working, now: 0))
        engine.handle(.tick(now: 200, cursorDistance: 1000, cursorX: 2000))
        XCTAssertEqual(engine.state, .idle)
        XCTAssertNil(engine.claudeStatus)
    }

    func testStatusTransitions() {
        let engine = freshEngine()
        engine.handle(.claudeStatus(.thinking, now: 0))
        XCTAssertEqual(engine.state, .claudeThinking)
        engine.handle(.claudeStatus(.working, now: 1))
        XCTAssertEqual(engine.state, .claudeWorking)
        engine.handle(.claudeStatus(.waiting, now: 2))
        XCTAssertEqual(engine.state, .claudeWaiting)
    }
}
