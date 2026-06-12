# Staged Drowsiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Kiki's single 5-minute sleep with a staged wind-down — eyes close at 30s idle, floating Z's at 60s, tip-over deep sleep at 90s that only a keystroke or a click on her ends.

**Architecture:** All timing/wake decisions live in the pure `BehaviorEngine` (KursorKidCore, unit-tested): two new states (`.drowsy`, `.dozing`), re-staged `.sleep`, and a new `.awaken` event for calendar reminders. The app target gets new standing-asleep frames + a "Zz" badge sprite, a badge-anchor refactor in `BuddyScene` (fixes a pre-existing bug where `update()` stomps badge movement animations), the tip-over rotation, and idle-chatter suppression while she's winding down. Spec: `docs/superpowers/specs/2026-06-12-staged-drowsiness-design.md`.

**Tech Stack:** Swift 5.10 SwiftPM, SpriteKit, XCTest. Build `swift build`, test `swift test`, app bundle `scripts/build-app.sh`.

**House rules for the executor:**
- `KursorKidCore` must stay free of AppKit/SpriteKit imports.
- Run commands from the repo root `/Users/dep/Sites/kursor-kid`.
- Commit messages: conventional style, each ending with the line `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Commit directly to `main` (user-approved). Do not push.
- A Claude Code hook may rewrite bash commands through an `rtk` proxy — expected and transparent; trust the output.

---

### Task 1: Engine — staged states, wake rules, `.awaken` event

**Files:**
- Modify: `Sources/KursorKidCore/BehaviorEngine.swift`
- Modify: `Tests/KursorKidCoreTests/BehaviorEngineTests.swift`

- [ ] **Step 1: Write the failing tests**

In `Tests/KursorKidCoreTests/BehaviorEngineTests.swift`, add inside the class (note: the file already has `makeEngine(sitRoll:)` and `tick(_:at:distance:cursorX:)` helpers — reuse them):

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter BehaviorEngineTests 2>&1 | tail -5`
Expected: compile error — `.drowsy`, `.dozing`, `.awaken` not defined.

- [ ] **Step 3: Implement the engine changes**

In `Sources/KursorKidCore/BehaviorEngine.swift`, five edits:

(a) Add the two states to `BuddyState`, after `case sit`:

```swift
    /// Eyes closed, still standing (30s idle). Fighting it.
    case drowsy
    /// Eyes closed with Z's floating (60s idle).
    case dozing
```

(b) Add the event to `BuddyEvent`, after `case animationFinished(now: TimeInterval)`:

```swift
    /// Something urgent (a calendar reminder) — wakes any drowsiness stage.
    case awaken(now: TimeInterval)
```

(c) In `Config`, replace `public var sleepAfter: TimeInterval = 300` with:

```swift
        public var drowsyAfter: TimeInterval = 30
        public var dozeAfter: TimeInterval = 60
        public var sleepAfter: TimeInterval = 90
```

(d) In `handle(_:)`, add a case before `case let .claudeStatus(...)`:

```swift
        case let .awaken(now):
            registerActivity(at: now)
            if state == .sleep { state = .idle }
```

(e) In `handleTick`, replace this block:

```swift
        // Sleep after prolonged inactivity (only from calm states).
        if state == .idle || state == .sit,
           let lastActivity = lastActivityAt,
           now - lastActivity >= config.sleepAfter {
            state = .sleep
            return
        }
        if state == .sleep { return }
```

with:

```swift
        // Staged wind-down after inactivity, from calm states only. Deep
        // sleep is sticky: ticks (and the cursor) never end it — only a
        // keystroke, a boop, or an awaken does (see registerActivity).
        if state == .sleep { return }
        if isCalm(state), let lastActivity = lastActivityAt {
            let idleFor = now - lastActivity
            if idleFor >= config.sleepAfter {
                state = .sleep
            } else if idleFor >= config.dozeAfter {
                state = .dozing
            } else if idleFor >= config.drowsyAfter {
                state = .drowsy
            }
            if state == .drowsy || state == .dozing || state == .sleep { return }
        }
```

(f) Replace `registerActivity` with:

```swift
    private func registerActivity(at now: TimeInterval) {
        lastActivityAt = now
        // Any activity rouses a drowsy/dozing Kiki. Deep sleep is NOT ended
        // here — cursor movement also routes through this method, and the
        // mouse must not wake her. Keystroke/boop/awaken wake explicitly.
        if state == .drowsy || state == .dozing { state = .idle }
    }
```

and in `handleKeystroke`, the existing `if state == .sleep { state = .idle }` line stays — it is now the only keystroke path out of deep sleep.

(g) Add the helper next to `isWander(_:)`:

```swift
    private func isCalm(_ state: BuddyState) -> Bool {
        state == .idle || state == .sit || state == .drowsy || state == .dozing
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter BehaviorEngineTests 2>&1 | tail -3`
Expected: all pass (18 existing + 11 new = 29 tests). The two existing sleep
tests (`testSleepsAfterInactivityAndWakesOnKeystroke`, `testCursorMovementPreventsSleep`)
must still pass unchanged — they tick to 301s, well past the new 90s threshold.

Then run the full suite: `swift test 2>&1 | grep Executed | tail -1`
Expected: `Executed 62 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/KursorKidCore/BehaviorEngine.swift Tests/KursorKidCoreTests/BehaviorEngineTests.swift
git commit -m "feat: staged drowsiness in BehaviorEngine (30s/60s/90s)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Sprites — standing sleep frames + Zz badge

**Files:**
- Modify: `Sources/KursorKidCore/KikiSprites.swift`
- Modify: `Tests/KursorKidCoreTests/PixelArtTests.swift`

- [ ] **Step 1: Write the failing test**

In `Tests/KursorKidCoreTests/PixelArtTests.swift`, add next to `testClaudeThinkingFramesAreDistinct`:

```swift
    func testSleepFramesAreStandingAndDistinct() {
        let frames = KikiSprites.sleep.map { $0.joined(separator: "\n") }
        XCTAssertEqual(Set(frames).count, frames.count, "breathing loop needs distinct frames")
        // Standing pose: shoes reach row 22; the sitting pose ends in blank rows there.
        XCTAssertTrue(KikiSprites.sleep[0][22].contains("P"), "expected standing shoes on row 22")
    }

    func testZzzBadgeRenders() {
        XCTAssertNotNil(PixelArt.image(from: KikiSprites.zzz, palette: KikiSprites.palette))
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter PixelArtTests 2>&1 | tail -5`
Expected: FAIL — `testSleepFramesAreStandingAndDistinct` fails on the standing-shoes assert (current frames are the sitting pose), and `zzz` doesn't exist (compile error).

- [ ] **Step 3: Implement**

In `Sources/KursorKidCore/KikiSprites.swift`, replace:

```swift
    public static let sleep: [[String]] = [
        sitting(eyes: eyesClosed, mouth: mouthSmile),
        sitting(eyes: eyesClosed, mouth: mouthOpen),
    ]
```

with:

```swift
    /// Standing, eyes closed, breathing slowly. Used by all three drowsiness
    /// stages — the scene tips the sprite over for deep sleep.
    public static let sleep: [[String]] = [
        standing(eyes: eyesClosed, mouth: mouthSmile, torso: torsoArmsDown, legs: legsStand),
        standing(eyes: eyesClosed, mouth: mouthOpen, torso: torsoArmsDown, legs: legsStand),
    ]
```

Next to `thoughtDots`/`exclaim`, add:

```swift
    /// Floating Z's for dozing/deep sleep: a big Z above a small z.
    public static let zzz = [
        ".....WWWWW",
        "........W.",
        ".......W..",
        "......W...",
        ".....WWWWW",
        "WWW.......",
        "..W.......",
        ".W........",
        "WWW.......",
    ]
```

(`allAnimations["sleep"]` already points at `sleep`, so the consistency test picks up the new frames automatically. The `zzz` badge is not an animation — like `thoughtDots`, it isn't added to `allAnimations`.)

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter PixelArtTests 2>&1 | tail -3`
Expected: all pass (7 tests).

- [ ] **Step 5: Visual check**

Run: `swift build 2>&1 | tail -1 && .build/debug/KursorKid --dump-sprites /tmp/kiki-sprites | tail -1`
Then view `/tmp/kiki-sprites/sleep-0.png` and `sleep-1.png` with the Read tool — expect a standing Kiki with closed eyes (no white eye glints), mouth differing between frames.

- [ ] **Step 6: Commit**

```bash
git add Sources/KursorKidCore/KikiSprites.swift Tests/KursorKidCoreTests/PixelArtTests.swift
git commit -m "feat: standing sleep frames and zzz badge sprite

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Scene — badge anchor refactor, drowsiness animations, tip-over

The app target has no tests; verification is `swift build` + the live check in Task 5.

**Files:**
- Modify: `Sources/KursorKid/BuddyScene.swift`
- Modify: `Sources/KursorKid/SpriteTextures.swift`

- [ ] **Step 1: Expose the zzz texture**

In `Sources/KursorKid/SpriteTextures.swift`, next to `static let exclaim = texture(KikiSprites.exclaim)`, add:

```swift
    static let zzz = texture(KikiSprites.zzz)
```

- [ ] **Step 2: Badge anchor refactor in `BuddyScene`**

Currently `update()` sets `badge.position` absolutely every frame, which stomps any `moveBy`-based badge action (the `!` badge's bob is effectively invisible today). Fix: position a container node each frame; animate the badge within it.

In `Sources/KursorKid/BuddyScene.swift`:

Replace the property `private let badge = SKSpriteNode()` with:

```swift
    /// `badgeAnchor` is positioned every frame; `badge` animates within it so
    /// movement actions aren't stomped by the per-frame repositioning.
    private let badgeAnchor = SKNode()
    private let badge = SKSpriteNode()
```

In `didMove(to:)`, replace:

```swift
        badge.isHidden = true
        addChild(badge)
```

with:

```swift
        badge.isHidden = true
        badgeAnchor.addChild(badge)
        addChild(badgeAnchor)
```

In `update(_:)`, replace the badge positioning line:

```swift
        badge.position = CGPoint(x: sprite.position.x + spriteHeight * 0.45, y: sprite.position.y + spriteHeight + 14)
```

with:

```swift
        badgeAnchor.position = CGPoint(x: sprite.position.x + spriteHeight * 0.45, y: sprite.position.y + spriteHeight + 14)
```

Replace `showBadge(_:pulse:)` and `hideBadge()` with:

```swift
    private enum BadgeAnimation {
        case pulse  // fade in/out in place (thinking dots)
        case bob    // small vertical hop (exclaim)
        case drift  // rise and fade, looping (sleepy Z's)
    }

    private func showBadge(_ texture: SKTexture, animation: BadgeAnimation) {
        badge.texture = texture
        badge.size = texture.size()
        badge.setScale(3)
        badge.isHidden = false
        badge.removeAllActions()
        badge.position = .zero
        badge.alpha = 1
        switch animation {
        case .pulse:
            badge.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.25, duration: 0.7),
                .fadeAlpha(to: 1.0, duration: 0.7),
            ])))
        case .bob:
            badge.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: 8, duration: 0.25),
                .moveBy(x: 0, y: -8, duration: 0.35),
                .wait(forDuration: 0.6),
            ])))
        case .drift:
            badge.run(.repeatForever(.sequence([
                .group([
                    .moveBy(x: 0, y: 16, duration: 1.6),
                    .sequence([.wait(forDuration: 0.8), .fadeAlpha(to: 0.0, duration: 0.8)]),
                ]),
                .moveBy(x: 0, y: -16, duration: 0),
                .fadeAlpha(to: 1.0, duration: 0),
            ])))
        }
    }

    private func hideBadge() {
        badge.isHidden = true
        badge.removeAllActions()
        badge.position = .zero
        badge.alpha = 1
    }
```

Update the two existing call sites in `syncState`:
- `.claudeThinking`: `showBadge(SpriteTextures.thoughtDots, pulse: true)` → `showBadge(SpriteTextures.thoughtDots, animation: .pulse)`
- `.claudeWaiting`: `showBadge(SpriteTextures.exclaim, pulse: false)` → `showBadge(SpriteTextures.exclaim, animation: .bob)`

- [ ] **Step 3: Drowsiness states in `syncState`**

In `syncState`, the action-removal block at the top gains the tip-over cleanup. Replace:

```swift
        sprite.removeAction(forKey: "move")
        sprite.removeAction(forKey: "anim")
        sprite.removeAction(forKey: "bounce")
```

with:

```swift
        sprite.removeAction(forKey: "move")
        sprite.removeAction(forKey: "anim")
        sprite.removeAction(forKey: "bounce")
        sprite.removeAction(forKey: "tipover")
        if previous == .sleep, state != .sleep {
            // She was lying down — pop upright before the new state animates.
            sprite.zRotation = 0
            sprite.position.y = groundY
        }
```

Replace the `.sleep` case:

```swift
        case .sleep:
            loop(SpriteTextures.sleep, timePerFrame: 0.9)
```

with:

```swift
        case .drowsy:
            loop(SpriteTextures.sleep, timePerFrame: 0.9)
        case .dozing:
            loop(SpriteTextures.sleep, timePerFrame: 0.9)
            showBadge(SpriteTextures.zzz, animation: .drift)
        case .sleep:
            loop(SpriteTextures.sleep, timePerFrame: 0.9)
            showBadge(SpriteTextures.zzz, animation: .drift)
            // Tip over: rotating about the bottom-center anchor lays the body
            // along the ground; raise her half a body-thickness so the lying
            // sprite isn't clipped below the window.
            let lyingY = groundY + CGFloat(KikiSprites.width) * spriteScale / 2
            sprite.run(.sequence([
                .wait(forDuration: 0.5),
                .group([
                    .rotate(toAngle: -.pi / 2, duration: 0.35, shortestUnitArc: true),
                    .moveTo(y: lyingY, duration: 0.35),
                ]),
            ]), withKey: "tipover")
```

Update the badge-hiding line after the switch. Replace:

```swift
        if !isClaudeState(state) { hideBadge() }
```

with:

```swift
        if !isClaudeState(state), state != .dozing, state != .sleep { hideBadge() }
```

- [ ] **Step 4: Rotation-aware hit testing + `awaken()`**

A lying Kiki must still be clickable along her whole body. In `spriteFrame()`, replace the body:

```swift
    private func spriteFrame() -> CGRect {
        CGRect(
            x: sprite.position.x - CGFloat(KikiSprites.width) * spriteScale / 2,
            y: sprite.position.y,
            width: CGFloat(KikiSprites.width) * spriteScale,
            height: spriteHeight
        )
    }
```

with:

```swift
    private func spriteFrame() -> CGRect {
        // Accumulated frame accounts for the tip-over rotation, so a lying
        // Kiki is clickable along her whole body.
        sprite.calculateAccumulatedFrame()
    }
```

Add next to `showBubble`:

```swift
    /// Wake her for something urgent (a calendar reminder).
    func awaken() {
        engine.handle(.awaken(now: CACurrentMediaTime()))
    }
```

- [ ] **Step 5: Build**

Run: `swift build 2>&1 | tail -1`
Expected: build complete, no warnings about the removed `pulse:` parameter remaining anywhere (`grep -rn "pulse:" Sources/` should only match the `BadgeAnimation` enum comment, if anything).

- [ ] **Step 6: Commit**

```bash
git add Sources/KursorKid/BuddyScene.swift Sources/KursorKid/SpriteTextures.swift
git commit -m "feat: drowsiness animations, drifting Z badge, tip-over sleep

Badge actions now run inside an anchor node positioned per-frame, fixing
the pre-existing stomp of moveBy-based badge animations.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Chatter — no talking in her sleep, reminders wake her

**Files:**
- Modify: `Sources/KursorKid/QuipCoordinator.swift`

- [ ] **Step 1: Suppress idle chatter while winding down**

In `Sources/KursorKid/QuipCoordinator.swift`, add a helper after the `showClaudeLine` method:

```swift
    /// True while she's in any drowsiness stage — a sleepy girl doesn't quip.
    private var isDrowsing: Bool {
        switch scene?.engine.state {
        case .drowsy, .dozing, .sleep: true
        default: false
        }
    }
```

In `scheduleIdleChatter()`, replace:

```swift
                if self.settings.idleChatterEnabled, !self.settings.muted {
                    self.deliver(trigger: .idle)
                }
```

with:

```swift
                if self.settings.idleChatterEnabled, !self.settings.muted, !self.isDrowsing {
                    self.deliver(trigger: .idle)
                }
```

- [ ] **Step 2: Calendar reminders wake her first**

In `calendarReminder(title:)`, add the awaken call before the bubble:

```swift
    func calendarReminder(title: String) {
        guard !settings.muted else { return }
        scene?.awaken() // meetings outrank naps — never hop while lying down
        let template = calendarReminderLines.randomElement()!
        scene?.showBubble(String(format: template, title), sticky: true)
        scene?.alertJump()
    }
```

- [ ] **Step 3: Build + full tests**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | grep Executed | tail -1`
Expected: build complete, `Executed 64 tests, with 0 failures` (51 before this feature + 11 engine + 2 sprite).

- [ ] **Step 4: Commit**

```bash
git add Sources/KursorKid/QuipCoordinator.swift
git commit -m "feat: suppress idle chatter while asleep; reminders wake her

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Rebuild, relaunch, live verification

No code — prove it works.

- [ ] **Step 1: Rebuild the signed app and relaunch**

```bash
./scripts/build-app.sh 2>&1 | tail -1
pkill -9 KursorKid || true; sleep 1
open "/Users/dep/Sites/kursor-kid/dist/Kursor Kid.app" && sleep 2 && pgrep -x KursorKid
```

Expected: `✓ Signed app at dist/Kursor Kid.app`, then a PID.

- [ ] **Step 2: Ask the user to verify**

Ask the user to keep hands off keyboard/mouse and watch:
1. ~30s: her eyes close (standing).
2. ~60s: Z's float up beside her head.
3. ~90s: she tips over sideways and lies on the ground, Z's continuing.
4. Wiggle the mouse: she stays asleep.
5. Type a key: she pops upright awake.
6. Repeat to 90s, then click her: boop + awake.
7. Optional: with a calendar reminder pending, confirm she wakes, hops, and shows the sticky bubble.

Report results honestly; if a stage misbehaves, debug before marking complete.

---

## Final checks

- [ ] `swift test` — 64 tests, 0 failures.
- [ ] `git log --oneline` — one commit per task (4 code commits).
- [ ] Do NOT push.
