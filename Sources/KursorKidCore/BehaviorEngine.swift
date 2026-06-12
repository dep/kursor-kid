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
    /// Eyes closed, still standing (30s idle). Fighting it.
    case drowsy
    /// Eyes closed with Z's floating (60s idle).
    case dozing
    case sleep
    case dragged
    case tossed
    case dizzy
    /// Claude Code activity states (driven by hook events via URL scheme).
    case claudeThinking
    case claudeWorking
    case claudeWaiting
}

/// What Claude Code is up to, as reported by its hooks.
public enum ClaudeStatus: String, Equatable, Sendable {
    case thinking, working, waiting
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
    /// Kiki has been thrown (velocity above threshold). Scene drives physics.
    case tossed
    /// Kiki hit the floor after being tossed.
    case landed(now: TimeInterval)
    /// The scene finished playing a one-shot animation or completed a walk.
    case animationFinished(now: TimeInterval)
    /// Something urgent (a calendar reminder) — wakes any drowsiness stage.
    case awaken(now: TimeInterval)
    /// Claude Code hook event. `nil` clears (done / session end).
    case claudeStatus(ClaudeStatus?, now: TimeInterval)
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
        public var drowsyAfter: TimeInterval = 30
        public var dozeAfter: TimeInterval = 60
        public var sleepAfter: TimeInterval = 90
        public var wanderInterval: ClosedRange<CGFloat> = 5...20
        public var sitChance: CGFloat = 0.3
        public var sitDuration: TimeInterval = 10
        /// A Claude status with no refresh for this long is considered stale.
        public var claudeStatusTimeout: TimeInterval = 180
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
    private var dizzyUntil: TimeInterval = 0
    public private(set) var claudeStatus: ClaudeStatus?
    private var claudeStatusAt: TimeInterval = 0

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
            state = restingState()
            nextWanderAt = now + TimeInterval(random(config.wanderInterval))
        case let .animationFinished(now):
            handleAnimationFinished(now: now)
        case let .awaken(now):
            registerActivity(at: now)
            if state == .sleep {
                state = .idle
                nextWanderAt = now + TimeInterval(random(config.wanderInterval))
                farSince = nil
            }
        case .tossed:
            state = .tossed
        case let .landed(now):
            dizzyUntil = now + 1.5
            state = .dizzy
        case let .claudeStatus(status, now):
            handleClaudeStatus(status, now: now)
        }
        return state
    }

    private func handleClaudeStatus(_ status: ClaudeStatus?, now: TimeInterval) {
        claudeStatus = status
        claudeStatusAt = now
        guard state != .dragged, state != .boop else { return }
        switch status {
        case .thinking: state = .claudeThinking
        case .working: state = .claudeWorking
        case .waiting: state = .claudeWaiting
        case nil:
            if isClaudeState(state) { state = .idle }
        }
    }

    private func isClaudeState(_ state: BuddyState) -> Bool {
        state == .claudeThinking || state == .claudeWorking || state == .claudeWaiting
    }

    // MARK: - Event handlers

    private func handleTick(now: TimeInterval, distance: CGFloat, cursorX: CGFloat) {
        if state == .tossed { return }
        if state == .dizzy {
            if now >= dizzyUntil { state = .idle }
            return
        }
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

        // Claude activity pins her state until cleared, refreshed, or stale.
        if isClaudeState(state) {
            if now - claudeStatusAt > config.claudeStatusTimeout {
                claudeStatus = nil
                state = .idle
            }
            return
        }

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
                   state != .dragged, state != .boop, state != .startled,
                   !isClaudeState(state) {
                    state = .dance
                }
            } else {
                typingSustainedSince = now
            }
        } else {
            typingSustainedSince = nil
        }

        if state == .sleep {
            state = .idle
            // Reset timers so she doesn't immediately wander or chase after waking.
            nextWanderAt = now + TimeInterval(random(config.wanderInterval))
            farSince = nil
        }
    }

    private func handleAnimationFinished(now: TimeInterval) {
        switch state {
        case .boop:
            state = restingState()
            // Waking from boop (possibly from deep sleep): reset the wander
            // timer so she doesn't immediately wander after the interaction.
            nextWanderAt = now + TimeInterval(random(config.wanderInterval))
            farSince = nil
        case .startled:
            if claudeStatus != nil {
                state = restingState()
            } else {
                state = lastCursorDistance < config.waveDistance ? .wave : .idle
            }
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
        // Any activity rouses a drowsy/dozing Kiki. Deep sleep is NOT ended
        // here — cursor movement also routes through this method, and the
        // mouse must not wake her. Keystroke/boop/awaken wake explicitly.
        if state == .drowsy || state == .dozing {
            state = .idle
            // Reset the wander timer so she doesn't immediately wander after waking.
            nextWanderAt = now + TimeInterval(random(config.wanderInterval))
            // Clear stale far-cursor accrual so she doesn't instantly bolt on the next tick.
            farSince = nil
        }
    }

    /// Where she settles after an interruption: back to Claude duty if a
    /// status is active, otherwise plain idle.
    private func restingState() -> BuddyState {
        switch claudeStatus {
        case .thinking: .claudeThinking
        case .working: .claudeWorking
        case .waiting: .claudeWaiting
        case nil: .idle
        }
    }

    private func isCalm(_ state: BuddyState) -> Bool {
        state == .idle || state == .sit || state == .drowsy || state == .dozing
    }

    private func isWander(_ state: BuddyState) -> Bool {
        if case .wander = state { return true }
        return false
    }
}
