# Staged Drowsiness — Design

**Date:** 2026-06-12
**Status:** Approved (tip-over sleep art)

## Goal

Replace the single 5-minute sleep with a three-stage wind-down: 30 seconds of
idleness closes Kiki's eyes, 60 seconds adds floating Z's, 90 seconds tips her
over into a deep sleep that only a keystroke or a click on her can end.

## States (`BehaviorEngine`)

`.sleep` is re-staged into three states:

| Stage | Enters at | Pose | Badge |
|---|---|---|---|
| `.drowsy` | 30s idle | standing, eyes closed, slow breathing loop | none |
| `.dozing` | 60s idle | same | floating "Zz" |
| `.sleep` | 90s idle | tipped over 90°, resting on the ground | floating "Zz" |

Config: `drowsyAfter = 30`, `dozeAfter = 60`, `sleepAfter = 90` (replaces
`sleepAfter = 300`).

### Progression

Stages advance on ticks from calm states only: `idle`, `sit`, `drowsy`,
`dozing` — keyed off `now - lastActivityAt` crossing each threshold. Claude
activity states, wave, dance, drag, startle, and boop are untouched (they are
not calm states, and Claude states already pin her). Wander and cursor-chase
cannot start while drowsy or beyond (they only fire from `.idle`).

Entering a stage from `.sit` pops her to the standing drowsy pose — accepted
simplification; one art path for all three stages.

Known pre-existing quirk, unchanged: a cursor parked inside the wave band
keeps her waving and she never winds down (same as the old 5-minute sleep).

### Wake rules

- `drowsy` / `dozing`: ANY activity (keystroke, click, drag, cursor movement)
  resets her to `.idle` and resets the timer.
- `.sleep`: ONLY a keystroke or a click on her wakes her. Cursor movement
  still updates `lastActivityAt` but does NOT change her state —
  `registerActivity` wakes drowsy/dozing but not sleep; the keystroke handler
  and the click→boop path wake sleep explicitly (boop already does via
  `restingState()`).
- New engine event `.awaken(now:)` — registers activity and wakes any
  drowsiness stage. Used by calendar reminders: a reminder must wake her
  (meetings outrank naps) so she isn't hopping and speaking while rotated
  sideways.

## Art (`KikiSprites` / `BuddyScene`)

- `KikiSprites.sleep` (currently 2 sitting frames) is REPLACED by 2 standing
  eyes-closed breathing frames (mouth smile / mouth open alternating, ~0.9s
  per frame). All three stages use these textures; `allAnimations["sleep"]`
  points at the new frames so existing sprite-consistency tests cover them.
- `KikiSprites.zzz` — new badge grid (a large Z beside a small z, white
  pixels, same style as `thoughtDots`/`exclaim`).
- `BuddyScene`:
  - `.drowsy` / `.dozing`: loop the new frames; `.dozing` shows the zzz badge
    with a new "drift" badge animation (rise + fade loop, classic cartoon Z's).
  - `.sleep`: same loop plus a tip-over — animate `zRotation` to −90° with a
    small bounce, offsetting position so she rests on the ground (with the
    bottom-center anchor, the rotated body extends sideways at ground level;
    the scene adds the half-thickness y-offset so she isn't clipped).
  - On leaving `.sleep`: rotation and offset reset instantly before the next
    state's animation applies (she pops upright; the existing landing bounce
    path is not reused).
  - Badge hiding logic extends to cover the new states (badge shows only for
    `.dozing`, `.sleep`, and the existing Claude states).

## Chatter interactions (`QuipCoordinator`)

- Idle chatter is suppressed while she is in any drowsiness stage (the timer
  checks `scene?.engine.state` before delivering) — no talking in her sleep.
  The timer keeps running; she just skips that delivery.
- Calendar reminders are NOT suppressed: `calendarReminder` first sends
  `.awaken`, then shows the sticky bubble and alert-jumps as today.
- Boop quips: clicking a sleeping Kiki wakes her (boop state); the normal
  click-quip flow may comment. No change needed.

## Testing

`BehaviorEngine` is pure — unit tests in `BehaviorEngineTests`:

- Tick timeline: idle → drowsy at 30s → dozing at 60s → sleep at 90s.
- Cursor movement at 45s (drowsy) wakes to idle and resets the timer.
- Cursor movement at 95s (sleep) does NOT wake her.
- Keystroke at 95s wakes her to idle.
- Click at 95s boops her, and she settles to idle (not back to sleep).
- `.awaken` wakes every stage and registers activity.
- No drowsiness progression while a Claude status is active.
- Sit at 28s + continued idleness still reaches the stages.

Sprite checks ride on the existing `allAnimations` consistency test plus
`--dump-sprites` visual review. Live check: leave the machine idle and watch
the 30/60/90 sequence; wiggle the mouse at each stage; type to wake her.

## Out of scope (YAGNI)

- Configurable stage timings in Settings.
- Custom lying-down art (tip-over rotation chosen instead).
- Snoring sounds, dream bubbles.
- Waking on cursor *proximity* (only keystroke / click wake deep sleep).
