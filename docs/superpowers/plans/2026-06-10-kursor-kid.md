# Kursor Kid Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build "Kursor Kid" — a signed, notarized macOS menu bar app with a pixel-art desktop buddy (Kiki) that walks the bottom of the screen, reacts to cursor/typing/clicks, and quips via Claude Haiku.

**Architecture:** SwiftPM executable + core library. `KursorKidCore` (pure Swift, unit-tested) holds the behavior state machine, quip client, prompt builder, canned lines, settings. `KursorKid` (executable) holds AppKit/SpriteKit UI: transparent overlay panel, sprite scene, input monitoring, menu bar, SwiftUI settings. A shell script assembles/signs/notarizes the .app.

**Tech Stack:** Swift 6 (v5 language mode), AppKit, SpriteKit, SwiftUI (settings only), URLSession, XCTest, codesign/notarytool. Zero third-party deps.

**Spec:** `docs/superpowers/specs/2026-06-10-kursor-kid-design.md`

---

### Task 1: SwiftPM scaffold

**Files:** Create `Package.swift`, `Sources/KursorKidCore/Placeholder.swift`, `Sources/KursorKid/main.swift`, `Tests/KursorKidCoreTests/SmokeTests.swift`

- [ ] Package.swift: macOS 14 platform, library target `KursorKidCore`, executable `KursorKid` (depends on core), test target. Swift language mode 5 to avoid strict-concurrency churn with AppKit.
- [ ] `swift build && swift test` pass.
- [ ] Commit `chore: scaffold SwiftPM project`.

### Task 2: SettingsStore (core)

**Files:** Create `Sources/KursorKidCore/SettingsStore.swift`, `Tests/KursorKidCoreTests/SettingsStoreTests.swift`

- [ ] Test: defaults (clickQuips=true, idleChatter=true, contextReactions=true, idleIntervalMinutes=15, muted=false, spriteScale=5, buddyVisible=true); round-trip persistence into an injected `UserDefaults(suiteName:)`.
- [ ] Implement `public final class SettingsStore` with `@objc`-free plain properties reading/writing UserDefaults, injected suite.
- [ ] Tests pass; commit `feat: settings store`.

### Task 3: BehaviorEngine (core)

**Files:** Create `Sources/KursorKidCore/BehaviorEngine.swift`, `Tests/KursorKidCoreTests/BehaviorEngineTests.swift`

Public surface:

```swift
public enum BuddyState: Equatable { case idle, wander(targetX: CGFloat), chaseCursor, dance, wave, startled, boop, sit, sleep, dragged }
public enum BuddyEvent: Equatable {
    case tick(now: TimeInterval, cursorDistance: CGFloat, cursorX: CGFloat)
    case keystroke(now: TimeInterval)
    case clicked(now: TimeInterval)
    case dragStarted, dragEnded(now: TimeInterval)
    case animationFinished(now: TimeInterval)   // for one-shot states: startled, boop, wave
}
public final class BehaviorEngine {
    public private(set) var state: BuddyState
    public init(random: @escaping (ClosedRange<CGFloat>) -> CGFloat = { .random(in: $0) })
    @discardableResult public func handle(_ event: BuddyEvent) -> BuddyState
}
```

Rules (constants public for tests): typing = ≥4 keys within trailing 1 s window sustained 2 s → dance; dance ends 3 s after last key. wave at distance <150, startled at <60 (4 s cooldown, one-shot → returns to prior tier). boop on click (one-shot). chase when cursor >300 away and idle >10 s, target = cursorX. wander from idle on internal 5–20 s timer (injected random). sleep after 300 s with no keystroke/click/drag and cursor distance unchanged-ish; any keystroke/click wakes. dragged overrides all; dragEnded → idle. Priorities: dragged > boop > startled > dance > wave > chase > wander > idle; sleep only from idle/sit.

- [ ] Write tests first: typing threshold triggers dance; sub-threshold doesn't; dance decays after 3 s; proximity bands; startled cooldown; boop one-shot returns to idle via animationFinished; sleep after 300 s idle; keystroke wakes; drag overrides dance; wander uses injected random target.
- [ ] Run tests, watch fail; implement; tests pass.
- [ ] Commit `feat: behavior engine state machine`.

### Task 4: Canned quips + prompt builder (core)

**Files:** Create `Sources/KursorKidCore/Quips.swift`, `Tests/KursorKidCoreTests/QuipsTests.swift`

- [ ] `public enum QuipTrigger: String { case clicked, idle, typingMarathon = "typing_marathon", appSwitch = "app_switch", timeOfDay = "time_of_day" }`
- [ ] `CannedQuips.line(for: QuipTrigger, random:)` — ≥6 lines per trigger, in Kiki's voice.
- [ ] `QuipPrompt.requestBody(trigger:timeOfDay:frontmostApp:recentQuips:)` returns `[String: Any]` with model `claude-haiku-4-5`, `max_tokens: 100`, system prompt (Kiki persona, one line ≤120 chars, no surrounding quotes), single user message containing context JSON. Test: body fields, model id, trigger in message, recent quips included, app name omitted when nil.
- [ ] Tests pass; commit `feat: canned quips and Haiku prompt builder`.

### Task 5: QuipService (core)

**Files:** Create `Sources/KursorKidCore/QuipService.swift`, `Tests/KursorKidCoreTests/QuipServiceTests.swift`

- [ ] `public final class QuipService` — init with `apiKeyProvider: () -> String?`, `session: URLSession`; `func fetchQuip(trigger:context:) async -> String` (never throws — falls back to canned). Posts to `https://api.anthropic.com/v1/messages` with headers `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`. Parses `content[0].text`. One retry on 429/5xx honoring `retry-after` (cap 5 s in tests via injected sleep). Tracks `recentQuips` (last 5).
- [ ] Tests with `URLProtocol` mock: success parse; missing key → canned; 401 → canned; 429 then success → retried result; malformed JSON → canned.
- [ ] Tests pass; commit `feat: quip service with fallback`.

### Task 6: Pixel art (core image gen + app textures)

**Files:** Create `Sources/KursorKidCore/PixelArt.swift`, `Sources/KursorKid/Sprites.swift`, `Tests/KursorKidCoreTests/PixelArtTests.swift`

- [ ] `PixelArt.image(from grid: [String], palette: [Character: (r,g,b,a)]) -> CGImage` — each string row, each char a pixel, `.` = transparent. Test: dimensions match grid, sampled pixel colors correct, uneven rows padded.
- [ ] `Sprites.swift`: Kiki frames as grids (24 wide × 24 tall): idle×2, walk×4, dance×4, wave×2, startled×1, boop×1, sit×1, sleep×2, talk×2. Palette per spec. (Authored during implementation; reviewed visually in Task 11.)
- [ ] Commit `feat: pixel art renderer and Kiki frames`.

### Task 7: Overlay window + scene

**Files:** Create `Sources/KursorKid/OverlayWindow.swift`, `Sources/KursorKid/BuddyScene.swift`, `Sources/KursorKid/SpeechBubble.swift`

- [ ] `OverlayWindow`: borderless `NSPanel`, `.statusBar` level, clear/transparent, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`, `ignoresCycle`, non-activating, frame = bottom strip (full width × 220 pt) of `NSScreen.main`; repositions on `didChangeScreenParametersNotification`.
- [ ] Click-through: window starts `ignoresMouseEvents = true`; on each scene update, hit-test global cursor against sprite frame and toggle.
- [ ] `BuddyScene` (SKScene): clear background, sprite node with `.nearest` textures, drives `BehaviorEngine` from `update(_:)` (cursor distance via `NSEvent.mouseLocation`), maps states → `SKAction` animations + horizontal movement, ground y constant, flips xScale for direction, drag via mouseDown/mouseDragged/mouseUp, floating pixel hearts on boop.
- [ ] `SpeechBubble`: SKShapeNode rounded rect + wrapped SKLabelNode (monospaced, pixel-ish), tail, clamped to screen, fades after 6 s.
- [ ] Build passes; commit `feat: overlay window and buddy scene`.

### Task 8: Input monitor + quip orchestration

**Files:** Create `Sources/KursorKid/InputMonitor.swift`, `Sources/KursorKid/QuipCoordinator.swift`

- [ ] `InputMonitor`: global keyDown monitor (count only) feeding engine `keystroke`; `AXIsProcessTrustedWithOptions` prompt on first run; exposes `isTrusted`. Tracks last-input time for sleep. Watches `NSWorkspace` frontmost app changes.
- [ ] `QuipCoordinator`: owns `QuipService` + cooldown clocks; methods `boopQuip()`, `maybeIdleChatter()`, `typingMarathonEnded()`, `appSwitched(name:)`, `timeOfDayGreeting()`; respects SettingsStore toggles + mute; delivers line to scene's bubble. Idle timer = interval ±25% jitter.
- [ ] Build passes; commit `feat: input monitoring and quip coordination`.

### Task 9: Menu bar, app delegate, Keychain

**Files:** Create `Sources/KursorKid/MenuBarController.swift`, `Sources/KursurKid/AppDelegate.swift` → (correct path `Sources/KursorKid/AppDelegate.swift`), `Sources/KursorKid/KeychainStore.swift`, rewrite `Sources/KursorKid/main.swift`

- [ ] `KeychainStore`: `kSecClassGenericPassword`, service `com.dannypeck.kursorkid`, account `anthropic-api-key`; get/set/delete.
- [ ] `MenuBarController`: status item (sparkle/pixel emoji or template glyph), menu: Show/Hide Kiki, Mute Chatter (checkmark), Enable Typing Detection… (only when untrusted), Settings…, Quit.
- [ ] `AppDelegate`: builds window/scene/monitor/coordinator, `NSApp.setActivationPolicy(.accessory)`.
- [ ] App runs from `swift run` showing sprite; commit `feat: menu bar app wiring`.

### Task 10: Settings window

**Files:** Create `Sources/KursorKid/SettingsView.swift`, `Sources/KursorKid/SettingsWindowController.swift`

- [ ] SwiftUI form: SecureField for API key (loads/saves Keychain) + Test button (live tiny request → ✓/✗), chatter toggles, idle interval slider 5–60 min, sprite scale picker (4/5/6×), Launch at Login toggle (`SMAppService.mainApp`).
- [ ] Commit `feat: settings window`.

### Task 11: Build, sign, notarize script + verification

**Files:** Create `scripts/build-app.sh`, `Resources/Info.plist` (template), `Resources/AppIcon` (pixel icon via PixelArt at runtime is fine for status item; .icns generated from a 1024 px render of Kiki face via `iconutil`).

- [ ] Script: `swift build -c release` → assemble `dist/Kursor Kid.app` (Contents/MacOS binary, Info.plist: CFBundleIdentifier `com.dannypeck.kursorkid`, LSUIElement true, CFBundleShortVersionString 1.0.0, NSAppleEventsUsageDescription not needed; icon), `codesign --force --options runtime --sign "Developer ID Application: Danny Peck (299R8V27FZ)"`, `ditto -c -k` zip, `xcrun notarytool submit --apple-id $APPLE_EMAIL --password $APPLE_APP_PASSWORD --team-id 299R8V27FZ --wait`, `xcrun stapler staple`.
- [ ] Run unsigned-assemble + launch locally; verify sprite walks, dances on typing, waves near cursor, boops on click, bubble shows canned line without key. Screenshot.
- [ ] Run full sign + notarize. `spctl -a -vv` accepts.
- [ ] Commit `feat: build and notarization script`; final commit/tag v1.0.0.

---

## Self-review

- Spec coverage: every spec section maps to a task (settings→2/10, behavior→3, quips→4/5, art→6, window/scene→7, input/privacy→8, menu/keychain→9, signing→11, error handling embedded in 5/8/9, testing across 2–6). ✓
- Placeholders: pixel-grid authoring deferred to Task 6 implementation by design (visual content, reviewed in Task 11) — everything else concrete. ✓
- Type consistency: `BuddyState`/`BuddyEvent`/`QuipTrigger` names used consistently across tasks 3–8. ✓ (Fixed Task 9 path typo inline.)
