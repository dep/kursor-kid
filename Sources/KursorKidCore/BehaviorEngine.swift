import Foundation

public enum BuddyState: Equatable {
    case idle
    /// Walk to a target x expressed as a 0...1 fraction of walkable screen width.
    case wander(targetX: CGFloat)
    case chaseCursor
    case dance
    case wave
    case startled
    case boop
    case sit
    case sleep
    case dragged
}

public enum BuddyEvent: Equatable {
    /// Periodic update. `cursorDistance` is the distance from cursor to the
    /// sprite's center; `cursorX` is the cursor's global x (used to detect
    /// cursor movement and as the chase target).
    case tick(now: TimeInterval, cursorDistance: CGFloat, cursorX: CGFloat)
    case keystroke(now: TimeInterval)
    case clicked(now: TimeInterval)
    case dragStarted
    case dragEnded(now: TimeInterval)
    /// The scene finished playing a one-shot animation or completed a walk.
    case animationFinished(now: TimeInterval)
}

/// Pure state machine driving Kiki's behavior. No AppKit/SpriteKit — fully
/// deterministic given an injected random source, so it's unit-testable.
public final class BehaviorEngine {
    public struct Config {
        public var waveDistance: CGFloat = 150
        public var startleDistance: CGFloat = 60
        public var startleCooldown: TimeInterval = 4
        public var typingKeysPerSecond = 4
        public var typingSustain: TimeInterval = 2
        public var danceLinger: TimeInterval = 3
        public var chaseDistance: CGFloat = 300
        public var chaseAfter: TimeInterval = 10
        public var sleepAfter: TimeInterval = 300
        public var wanderInterval: ClosedRange<CGFloat> = 5...20
        public var sitChance: CGFloat = 0.3
        public var sitDuration: TimeInterval = 10
        public init() {}
    }

    public private(set) var state: BuddyState = .idle
    public let config: Config

    private let random: (ClosedRange<CGFloat>) -> CGFloat

    private var keystrokes: [TimeInterval] = []
    private var typingSustainedSince: TimeInterval?
    private var lastKeyAt: TimeInterval = -.greatestFiniteMagnitude

    private var lastStartleAt: TimeInterval = -.greatestFiniteMagnitude
    private var lastActivityAt: TimeInterval?
    private var lastCursorX: CGFloat?
    private var lastCursorDistance: CGFloat = .greatestFiniteMagnitude
    private var farSince: TimeInterval?
    private var nextWanderAt: TimeInterval?
    private var sitUntil: TimeInterval = 0

    public init(
        config: Config = Config(),
        random: @escaping (ClosedRange<CGFloat>) -> CGFloat = { .random(in: $0) }
    ) {
        self.config = config
        self.random = random
    }

    @discardableResult
    public func handle(_ event: BuddyEvent) -> BuddyState {
        switch event {
        case let .tick(now, distance, cursorX):
            handleTick(now: now, distance: distance, cursorX: cursorX)
        case let .keystroke(now):
            handleKeystroke(now: now)
        case let .clicked(now):
            registerActivity(at: now)
            if state != .dragged { state = .boop }
        case .dragStarted:
            state = .dragged
        case let .dragEnded(now):
            registerActivity(at: now)
            state = .idle
            nextWanderAt = now + TimeInterval(random(config.wanderInterval))
        case let .animationFinished(now):
            handleAnimationFinished(now: now)
        }
        return state
    }

    // MARK: - Event handlers

    private func handleTick(now: TimeInterval, distance: CGFloat, cursorX: CGFloat) {
        lastCursorDistance = distance
        if lastActivityAt == nil { lastActivityAt = now }
        if nextWanderAt == nil { nextWanderAt = now + TimeInterval(random(config.wanderInterval)) }

        // Cursor movement counts as user activity (and a moving cursor is not "parked").
        let cursorMoved: Bool
        if let lastX = lastCursorX {
            cursorMoved = abs(cursorX - lastX) > 2
        } else {
            cursorMoved = false
        }
        lastCursorX = cursorX
        if cursorMoved {
            registerActivity(at: now)
            farSince = nil
        }

        // Track how long the cursor has been parked far away.
        if distance > config.chaseDistance {
            if farSince == nil { farSince = now }
        } else {
            farSince = nil
        }

        // Dance decays a few seconds after typing stops.
        if state == .dance {
            if now - lastKeyAt > config.danceLinger {
                state = .idle
                typingSustainedSince = nil
            } else {
                return
            }
        }

        // One-shot / override states don't transition on ticks.
        if state == .dragged || state == .boop || state == .startled { return }

        // Startle (close cursor) — one-shot with cooldown. Not while asleep.
        if distance < config.startleDistance,
           now - lastStartleAt >= config.startleCooldown,
           state != .sleep {
            lastStartleAt = now
            state = .startled
            return
        }

        // Wave band enter/exit.
        if distance < config.waveDistance {
            if state == .idle || state == .sit || state == .chaseCursor || isWander(state) {
                state = .wave
            }
            return
        } else if state == .wave {
            state = .idle
        }

        // Sleep after prolonged inactivity (only from calm states).
        if state == .idle || state == .sit,
           let lastActivity = lastActivityAt,
           now - lastActivity >= config.sleepAfter {
            state = .sleep
            return
        }
        if state == .sleep { return }

        // Sit ends after its duration (one transition per tick).
        if state == .sit {
            if now >= sitUntil { state = .idle }
            return
        }

        // Wander on the internal timer.
        if state == .idle, let wanderAt = nextWanderAt, now >= wanderAt {
            state = .wander(targetX: random(0...1))
            nextWanderAt = now + TimeInterval(random(config.wanderInterval))
            return
        }

        // Chase a cursor that's been parked far away for a while.
        if state == .idle, let far = farSince, now - far >= config.chaseAfter {
            farSince = nil
            state = .chaseCursor
        }
    }

    private func handleKeystroke(now: TimeInterval) {
        registerActivity(at: now)
        lastKeyAt = now
        keystrokes.append(now)
        keystrokes.removeAll { $0 <= now - 1 }

        if keystrokes.count >= config.typingKeysPerSecond {
            if let since = typingSustainedSince {
                if now - since >= config.typingSustain,
                   state != .dragged, state != .boop, state != .startled {
                    state = .dance
                }
            } else {
                typingSustainedSince = now
            }
        } else {
            typingSustainedSince = nil
        }

        if state == .sleep { state = .idle }
    }

    private func handleAnimationFinished(now: TimeInterval) {
        switch state {
        case .boop:
            state = .idle
        case .startled:
            state = lastCursorDistance < config.waveDistance ? .wave : .idle
        case .wander:
            if random(0...1) < config.sitChance {
                state = .sit
                sitUntil = now + config.sitDuration
            } else {
                state = .idle
            }
            nextWanderAt = now + TimeInterval(random(config.wanderInterval))
        case .chaseCursor:
            state = .idle
        default:
            break
        }
    }

    private func registerActivity(at now: TimeInterval) {
        lastActivityAt = now
        if state == .sleep { state = .idle }
    }

    private func isWander(_ state: BuddyState) -> Bool {
        if case .wander = state { return true }
        return false
    }
}
