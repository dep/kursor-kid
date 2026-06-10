# Kursor Kid — Design Spec

**Date:** 2026-06-10
**Status:** Approved (sections 1 approved by user; sections 2–6 finalized under delegated judgment — user granted full autonomy)

## What it is

A macOS menu bar app that puts **Kiki** — a cute retro pixel-art cyberpunk girl with blonde dutch braids and street clothes — on your screen. She walks along the bottom edge of the display, reacts to your cursor, dances when you type, reacts when clicked, and says funny things powered by Claude Haiku. Distributed as a signed + notarized .app.

## Decisions locked during brainstorming

| Question | Decision |
|---|---|
| Art style | Retro pixel art (option A) — chunky pixels, code-drawn frames |
| Placement | Ground walker along the bottom screen edge (option A) |
| Quip triggers | All three: on click, random idle chatter, context reactions |
| Distribution | Shareable: Developer ID signed + notarized (cert `Danny Peck (299R8V27FZ)`, notary creds in `.env`) |
| Tech | Swift + AppKit + SpriteKit, zero third-party dependencies |

## Architecture

Native Swift app, `LSUIElement = true` (no dock icon). Built as a SwiftPM executable, assembled into a `.app` bundle by a build script (`scripts/build-app.sh`) which also signs and notarizes.

```
MenuBarController (NSStatusItem)
  ├─ Show/Hide Kiki
  ├─ Mute chatter
  ├─ Settings…
  └─ Quit

OverlayWindow (borderless transparent NSPanel)
  ├─ level: .statusBar, joins all Spaces, ignores window cycling
  ├─ strip along bottom of main screen (height ~200pt, full width)
  ├─ click-through everywhere EXCEPT the sprite (ignoresMouseEvents
  │   toggled dynamically based on cursor-over-sprite hit test)
  └─ SKView → BuddyScene (SpriteKit)
       ├─ BuddySprite (SKSpriteNode, pixel-art textures)
       └─ SpeechBubble (SKNode: pixel-style bubble + SKLabelNode)

BehaviorEngine (pure Swift state machine — unit tested)
InputMonitor (cursor polling + global key-down monitor)
QuipService (Claude Haiku via URLSession — unit tested)
SettingsStore (UserDefaults) + KeychainStore (API key)
SettingsWindow (SwiftUI)
```

### Module layout (SwiftPM)

- `Sources/KursorKidCore/` — library target: `BehaviorEngine`, `QuipService`, `QuipPrompt`, `CannedQuips`, `SettingsStore` (testable, no AppKit window dependencies)
- `Sources/KursorKid/` — executable target: AppDelegate, MenuBarController, OverlayWindow, BuddyScene, SpriteFactory, InputMonitor, KeychainStore, SettingsWindow
- `Tests/KursorKidCoreTests/` — XCTest for the core library

## Pixel art

- Each animation frame is a pixel grid defined in Swift source (strings of palette characters → `CGImage` → `SKTexture` with `.nearest` filtering).
- Canvas: **24×24 logical pixels**, rendered at 5× (~120pt tall on screen). Chunky retro look per option A.
- Character: blonde dutch braids (two braids falling past shoulders), neon-pink cropped jacket with cyan trim, dark pants, pink/cyan glowy sneakers, tiny cyan eye-glint.
- Animations (frames): idle (2: stand + blink), walk (4-frame cycle, flipped horizontally for direction), run (reuse walk at higher rate + lean), dance (4), wave (2), startled (1 hop), boop (1 squash + hearts), sit (1), sleep (2: zzz toggle), talk (2: mouth open/closed).
- Palette: `#f2d16b` hair, `#e8b84b` braid shade, `#ffd9b3` skin, `#ff2e88` neon pink, `#00f0ff` cyan, `#2b2b45` jacket dark, `#1f1f33` pants, `#1a1a2e` outline/eyes.

## Behavior engine

A pure state machine: `(state, event, time) → (state, actions)`. Events are fed by InputMonitor, click handling, and timers; actions (play animation, move, show bubble, request quip) are executed by BuddyScene.

**States:** `idle`, `wander`, `chaseCursor`, `dance`, `wave`, `startled`, `boop`, `talk`, `sit`, `sleep`, `dragged`

**Transition rules:**

- **Wander:** from idle, every 5–20 s (random), walk to a random x along the bottom; occasionally sit for a bit.
- **Cursor proximity:** cursor within 150 pt of sprite → face cursor and `wave`; within 60 pt → `startled` hop (cooldown 4 s so she doesn't spaz). Cursor parked far away >10 s → maybe `chaseCursor`: run to below the cursor's x position, then idle.
- **Typing:** ≥4 keydowns/s sustained for 2 s → `dance`; keep dancing while typing continues; stop 3 s after last key.
- **Click on sprite:** `boop` (squash animation + floating pixel hearts) and trigger a click quip.
- **Drag:** mouse-down + move on sprite lets you drag her horizontally along the ground; release → idle at new spot.
- **Sleep:** no user input (global) for 5 min → `sit` then `sleep` (zzz bubble); any input wakes her.
- **Talk:** speech bubble visible ~6 s while current animation continues; bubble pinned above her head and clamped to screen edges.
- Priorities: boop/drag > startled > dance > wave > chase > wander/idle. Sleep only from idle.

## Input monitoring

- **Cursor:** poll `NSEvent.mouseLocation` on the scene update loop (no permissions needed).
- **Typing:** `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` — requires Accessibility trust. On first launch, prompt via `AXIsProcessTrustedWithOptions` with a friendly explanation. If not granted: everything works except typing-dance; menu shows a "Enable typing detection…" item.
- **Privacy:** key events are only counted (timestamps), never inspected or stored. Frontmost app *name* (via `NSWorkspace.shared.frontmostApplication`) is the only context shared with the API, and only when context reactions are enabled.

## Quips (Claude Haiku)

- Endpoint: `POST https://api.anthropic.com/v1/messages` via `URLSession` (no Swift SDK exists; raw HTTP is the documented path).
- Headers: `x-api-key` (from Keychain), `anthropic-version: 2023-06-01`, `content-type: application/json`.
- Model: **`claude-haiku-4-5`**, `max_tokens: 100`.
- System prompt: Kiki's persona — sassy-but-sweet cyberpunk pixel girl living on the user's screen; replies are a single line ≤ 120 chars, no emoji spam, no quotes around the line.
- User message carries context JSON: trigger (`clicked` / `idle` / `typing_marathon` / `app_switch` / `time_of_day`), local time, frontmost app name (if enabled), and the last 5 quips (to avoid repetition).
- **Triggers & cooldowns:**
  - Click quip: on boop, 10 s cooldown.
  - Idle chatter: every N minutes (default 15, slider 5–60) ± 25% jitter.
  - Context reactions: typing marathon ends (>2 min of sustained typing), frontmost app changes (10 min cooldown), time-of-day greeting (first launch of morning/evening).
- **Fallbacks:** no API key, network error, or rate limit → pick from ~30 canned lines per trigger category. API errors are logged via `os.Logger`, never surfaced as dialogs. One retry on 429/5xx (respecting `retry-after`), then canned.
- Responses parsed from `content[0].text`; `stop_reason` ignored beyond logging.
- Mute toggle (menu bar + settings) silences everything.

## Settings

SwiftUI window (opened from menu bar):

- **Anthropic API key** — secure field, stored in Keychain (service `com.dannypeck.kursorkid`), "Test" button fires a tiny live request and shows ✓/✗.
- **Chatter:** toggles for click quips / idle chatter / context reactions; idle interval slider (5–60 min).
- **Behavior:** sprite scale (4×/5×/6×), launch at login (`SMAppService.mainApp`).
- Settings persist in `UserDefaults` (except the key, which is Keychain-only).

## Error handling

- QuipService failures → canned lines (silent, logged).
- Missing Accessibility permission → degrade gracefully (no typing dance), menu item to re-prompt / open System Settings.
- Screen parameter changes (resolution, display add/remove) → reposition window via `NSApplication.didChangeScreenParametersNotification`.
- Keychain read failure → treated as "no key" (canned mode).

## Build, signing, distribution

- `swift build -c release` → `scripts/build-app.sh` assembles `dist/Kursor Kid.app` (Info.plist with `LSUIElement`, `NSHumanReadableCopyright`, bundle id `com.dannypeck.kursorkid`), codesigns with hardened runtime using `Developer ID Application: Danny Peck (299R8V27FZ)`, zips, submits to notarytool using `APPLE_EMAIL` / `APPLE_APP_PASSWORD` from `.env` + team id `299R8V27FZ`, staples the ticket.
- No sandbox (Developer ID distribution; Accessibility monitoring is fine outside the App Store).

## Testing

- **Unit (XCTest, `swift test`):** BehaviorEngine transitions (typing thresholds, proximity bands, cooldowns, sleep timing, priorities) using injected clocks; QuipService request construction, response parsing, fallback-to-canned on every failure mode (mock `URLProtocol`); SettingsStore defaults.
- **Manual/verification:** build + launch the real app, confirm sprite renders, walks, reacts to cursor, bubble shows; screenshot for the record.

## Out of scope (v1)

- Window-top climbing (placement option C), multiple buddies, custom skins, App Store distribution, auto-update.
