# Kiki Toss Interaction — Design Spec

**Date:** 2026-06-12
**Status:** Approved

---

## Overview

The user can grab Kiki and physically fling her across the screen. The throw direction and speed are determined by mouse velocity at release. She follows a parabolic arc, spins mid-air, then lands with a squish and staggers around dizzily before recovering.

---

## Gesture & Input

- **Grab:** Click and drag Kiki (existing `dragged` state, no change).
- **Throw:** On `mouseUp`, sample the last N mouse-move deltas (target: last 5 events, max 80ms window) to compute a velocity vector `(vx, vy)`.
- **Threshold:** If the magnitude of that velocity is below a minimum (e.g. 80 pt/s), treat it as a normal drop — no throw.
- **Result:** Above threshold, transition to the new `.tossed` state with the computed velocity.

Velocity sampling lives entirely in `BuddyScene` — a small ring buffer of `(CGPoint, TimeInterval)` tuples accumulated during `mouseDragged`. On `mouseUp`, average the deltas across the window to get a stable launch vector.

---

## Physics (BuddyScene)

Physics runs frame-by-frame in `BuddyScene.update(_:)` while in the `.tossed` state. The behavior engine holds the state; the scene owns all trajectory math.

- **Position update:** `pos += velocity * dt`
- **Gravity:** `velocity.y -= gravity * dt` (gravity constant ~600 pt/s²)
- **Horizontal bounds:** Kiki is not constrained horizontally during flight — she can cross the full window width.
- **Floor collision:** When `pos.y <= groundY`, trigger landing.
- **No wall bouncing** (ricochet was not selected — she flies until she hits the floor).

---

## New BehaviorEngine States

Two new states added to `BuddyState`:

### `.tossed`
- Entered from `.dragged` on release above velocity threshold.
- No input handling while airborne (cursor-distance ticks ignored).
- Exits to `.dizzy` when `BuddyScene` reports floor contact via a new event `.landed`.

### `.dizzy`
- Entered on landing.
- Duration: ~1.5 seconds.
- Exits to `.idle` automatically via a `.wait` timer in the engine (same pattern as `.startled`).

---

## Animations

### Mid-air (`.tossed`)
- Sprite rotates continuously — `SKAction.repeatForever(.rotate(byAngle:duration:))`.
- Rotation direction matches throw direction (clockwise for rightward throw, counter-clockwise for left).
- Speed lines: 3 small white/yellow pixel lines spawned as child nodes trailing behind her position, fading out over ~0.15s each.

### Landing squish
- On floor contact: `scaleY` compress to `spriteScale * 0.7` over 0.08s, spring back to `spriteScale` over 0.18s (same pattern as the existing boop squish).
- Rotation snaps to 0 on landing.

### Dizzy (`.dizzy`)
- Looped animation using existing `SpriteTextures.idle` frames (or a new `dizzy` frame set if art is available — use idle as fallback).
- Spinning stars badge above her head: reuse the existing `badge` infrastructure with a new `stars` texture and the `.pulse` animation.
- Small left-right wobble: `moveBy(x: ±4, duration: 0.2)` repeating.

### Recovery
- On `.dizzy` → `.idle` transition: hide badge, stop wobble, resume normal idle.

---

## File-by-File Changes

| File | Change |
|---|---|
| `BehaviorEngine.swift` | Add `.tossed` and `.dizzy` cases to `BuddyState`; handle `.landed` event; auto-timer for dizzy→idle |
| `BuddyScene.swift` | Velocity ring buffer in `mouseDragged`; physics update in `update(_:)` for `.tossed`; floor collision → send `.landed` event; squish action on landing; dizzy badge + wobble in `syncState` |
| `SpriteTextures.swift` | Add `stars` badge texture (can reuse/adapt existing pixel art) |
| `KikiSprites.swift` | Add `dizzy` sprite frames if new art is created; otherwise no change |
| `QuipCoordinator.swift` | No change — quips are suppressed in non-idle states already |

---

## Edge Cases

- **Throw while sleeping:** Kiki is not interactable while asleep (existing click-through logic) — no change needed.
- **Throw off the bottom of the window:** Floor is clamped to `groundY`; the window covers the full screen height, so this shouldn't occur in practice.
- **Multiple rapid throws:** Dizzy state accepts a new drag — the user can grab her mid-dizzy. This resets cleanly since `.dragged` is already handled from any state.
- **Celebrate / alertJump during toss:** Both guard `!isDragging`; add the same guard for `!isTossed` (a new flag mirroring `isDragging`).

---

## Out of Scope

- Wall bouncing / ricochet (not selected)
- Aim guide arc while dragging (not selected)
- Angry reaction or speech bubble on landing (B selected: dizzy stagger, not C: scowl/quip)
- Persistent physics (she doesn't slide or roll after landing)
