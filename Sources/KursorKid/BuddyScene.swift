import AppKit
import KursorKidCore
import SpriteKit

/// SpriteKit scene hosting Kiki. Drives the BehaviorEngine from the render
/// loop, maps states to animations/movement, and handles direct interaction
/// (click = boop, drag = carry).
final class BuddyScene: SKScene {
    let engine = BehaviorEngine()

    /// Called when Kiki is booped (clicked). Wired to the quip coordinator.
    var onBoop: (() -> Void)?
    /// Called on every state transition with the previous state's duration.
    var onStateChange: ((BuddyState, BuddyState, TimeInterval) -> Void)?

    private let sprite = SKSpriteNode(texture: SpriteTextures.idle[.center]?.first)
    private let badge = SKSpriteNode()
    private var eyeDirection: KikiSprites.EyeDirection = .center
    private let bubble = SpeechBubble()
    private var lastAppliedState: BuddyState?
    private var stateEnteredAt: TimeInterval = 0
    private var spriteScale: CGFloat
    private let groundY: CGFloat = 4

    private var isDragging = false
    private var mouseDownPoint: CGPoint?

    private let walkSpeed: CGFloat = 50
    private let chaseSpeed: CGFloat = 150

    init(scale: Int) {
        spriteScale = CGFloat(scale)
        super.init(size: .zero)
        scaleMode = .resizeFill
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        sprite.setScale(spriteScale)
        sprite.position = CGPoint(x: size.width * 0.75, y: groundY)
        sprite.texture?.filteringMode = .nearest
        addChild(sprite)
        addChild(bubble)
        badge.isHidden = true
        addChild(badge)
    }

    private func isClaudeState(_ state: BuddyState) -> Bool {
        state == .claudeThinking || state == .claudeWorking || state == .claudeWaiting
    }

    private func showBadge(_ texture: SKTexture, pulse: Bool) {
        badge.texture = texture
        badge.size = texture.size()
        badge.setScale(3)
        badge.isHidden = false
        badge.removeAllActions()
        if pulse {
            badge.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.25, duration: 0.7),
                .fadeAlpha(to: 1.0, duration: 0.7),
            ])))
        } else {
            badge.alpha = 1
            badge.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: 8, duration: 0.25),
                .moveBy(x: 0, y: -8, duration: 0.35),
                .wait(forDuration: 0.6),
            ])))
        }
    }

    private func hideBadge() {
        badge.isHidden = true
        badge.removeAllActions()
    }

    /// Claude finished: a happy jump with extra hearts.
    func celebrate() {
        guard !isDragging else { return }
        spawnHearts()
        sprite.run(.sequence([
            .moveBy(x: 0, y: 30, duration: 0.15),
            .moveBy(x: 0, y: -30, duration: 0.2),
            .moveBy(x: 0, y: 18, duration: 0.12),
            .moveBy(x: 0, y: -18, duration: 0.16),
        ]), withKey: "celebrate")
    }

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

    func setSpriteScale(_ scale: Int) {
        spriteScale = CGFloat(scale)
        sprite.setScale(spriteScale)
    }

    // MARK: - Render loop

    override func update(_ currentTime: TimeInterval) {
        let cursor = NSEvent.mouseLocation
        let spriteCenter = spriteCenterInScreen()
        let distance = hypot(cursor.x - spriteCenter.x, cursor.y - spriteCenter.y)

        if !isDragging {
            engine.handle(.tick(now: currentTime, cursorDistance: distance, cursorX: cursor.x))
        }
        syncState(now: currentTime)
        updateEyeDirection(cursorX: cursor.x, spriteX: spriteCenter.x)
        updateClickThrough(cursor: cursor)
        bubble.position = CGPoint(x: sprite.position.x, y: sprite.position.y + spriteHeight + 4)
        badge.position = CGPoint(x: sprite.position.x + spriteHeight * 0.45, y: sprite.position.y + spriteHeight + 14)

        if isDragging {
            let local = convertFromScreen(cursor)
            sprite.position.x = min(max(local.x, walkableMinX), walkableMaxX)
            sprite.position.y = max(groundY, local.y - spriteHeight / 2)
        }
    }

    // MARK: - State → animation

    private func syncState(now: TimeInterval) {
        let state = engine.state
        guard state != lastAppliedState else { return }
        let previous = lastAppliedState ?? .idle
        let duration = now - stateEnteredAt
        lastAppliedState = state
        stateEnteredAt = now

        sprite.removeAction(forKey: "move")
        sprite.removeAction(forKey: "anim")
        sprite.removeAction(forKey: "bounce")

        switch state {
        case .idle:
            loop(SpriteTextures.idle[eyeDirection]!, timePerFrame: 0.6)
        case let .wander(targetX):
            let target = walkableMinX + targetX * (walkableMaxX - walkableMinX)
            walk(to: target, speed: walkSpeed, textures: SpriteTextures.walk, timePerFrame: 0.18, now: now)
        case .chaseCursor:
            let cursorX = NSEvent.mouseLocation.x - (view?.window?.frame.minX ?? 0)
            let target = min(max(cursorX, walkableMinX), walkableMaxX)
            walk(to: target, speed: chaseSpeed, textures: SpriteTextures.walk, timePerFrame: 0.09, now: now)
        case .dance:
            loop(SpriteTextures.dance, timePerFrame: 0.16)
            sprite.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: 6, duration: 0.16),
                .moveBy(x: 0, y: -6, duration: 0.16),
            ])), withKey: "bounce")
        case .wave:
            // Front-facing art: her eyes (not a body flip) track the cursor.
            loop(SpriteTextures.wave[eyeDirection]!, timePerFrame: 0.25)
        case .startled:
            sprite.texture = SpriteTextures.startled[0]
            sprite.run(.sequence([
                .moveBy(x: 0, y: 24, duration: 0.12),
                .moveBy(x: 0, y: -24, duration: 0.16),
                .run { [weak self] in self?.finishOneShot() },
            ]), withKey: "move")
        case .boop:
            sprite.texture = SpriteTextures.boop[0]
            spawnHearts()
            sprite.run(.sequence([
                .scaleY(to: spriteScale * 0.82, duration: 0.08),
                .scaleY(to: spriteScale, duration: 0.14),
                .wait(forDuration: 0.5),
                .run { [weak self] in self?.finishOneShot() },
            ]), withKey: "move")
        case .sit:
            sprite.texture = SpriteTextures.sit[eyeDirection]![0]
        case .sleep:
            loop(SpriteTextures.sleep, timePerFrame: 0.9)
        case .dragged:
            sprite.texture = SpriteTextures.startled[0]
        case .claudeThinking:
            loop(SpriteTextures.claudeThinking, timePerFrame: 0.3)
            showBadge(SpriteTextures.thoughtDots, pulse: true)
        case .claudeWorking:
            loop(SpriteTextures.claudeWorking, timePerFrame: 0.3)
        case .claudeWaiting:
            loop(SpriteTextures.claudeWaiting, timePerFrame: 0.45)
            showBadge(SpriteTextures.exclaim, pulse: false)
        }

        if !isClaudeState(state) { hideBadge() }

        // Landing after a drag: drop her back to the ground.
        if previous == .dragged, state != .dragged, sprite.position.y > groundY {
            sprite.run(.sequence([
                .moveTo(y: groundY, duration: 0.25),
                .scaleY(to: spriteScale * 0.9, duration: 0.06),
                .scaleY(to: spriteScale, duration: 0.1),
            ]), withKey: "move")
        }

        onStateChange?(previous, state, duration)
    }

    private func loop(_ textures: [SKTexture], timePerFrame: TimeInterval) {
        sprite.run(.repeatForever(.animate(with: textures, timePerFrame: timePerFrame)), withKey: "anim")
    }

    // MARK: - Cursor-following eyes

    private func updateEyeDirection(cursorX: CGFloat, spriteX: CGFloat) {
        let dx = cursorX - spriteX
        let newDirection: KikiSprites.EyeDirection = dx < -28 ? .left : (dx > 28 ? .right : .center)
        guard newDirection != eyeDirection else { return }
        eyeDirection = newDirection

        // Refresh the current animation only for stationary, eyes-open states.
        switch engine.state {
        case .idle:
            loop(SpriteTextures.idle[eyeDirection]!, timePerFrame: 0.6)
        case .wave:
            loop(SpriteTextures.wave[eyeDirection]!, timePerFrame: 0.25)
        case .sit:
            sprite.texture = SpriteTextures.sit[eyeDirection]![0]
        default:
            break
        }
    }

    private func walk(to targetX: CGFloat, speed: CGFloat, textures: [SKTexture], timePerFrame: TimeInterval, now: TimeInterval) {
        face(towards: view?.window.map { $0.frame.minX + targetX } ?? targetX)
        sprite.xScale = targetX < sprite.position.x ? -spriteScale : spriteScale
        let distance = abs(targetX - sprite.position.x)
        loop(textures, timePerFrame: timePerFrame)
        sprite.run(.sequence([
            .moveTo(x: targetX, duration: TimeInterval(distance / speed)),
            .run { [weak self] in self?.finishOneShot() },
        ]), withKey: "move")
    }

    private func face(towards screenX: CGFloat) {
        let spriteScreenX = spriteCenterInScreen().x
        sprite.xScale = screenX < spriteScreenX ? -spriteScale : spriteScale
    }

    private func finishOneShot() {
        sprite.xScale = abs(sprite.xScale)
        engine.handle(.animationFinished(now: CACurrentMediaTime()))
        syncState(now: CACurrentMediaTime())
    }

    private func spawnHearts() {
        for i in 0..<3 {
            let heart = SKSpriteNode(texture: SpriteTextures.heart)
            heart.setScale(3)
            heart.position = CGPoint(
                x: sprite.position.x + CGFloat([-18, 0, 18][i]),
                y: sprite.position.y + spriteHeight * 0.8
            )
            heart.alpha = 0
            addChild(heart)
            heart.run(.sequence([
                .wait(forDuration: Double(i) * 0.1),
                .group([
                    .fadeIn(withDuration: 0.1),
                    .moveBy(x: 0, y: 36, duration: 0.8),
                ]),
                .fadeOut(withDuration: 0.25),
                .removeFromParent(),
            ]))
        }
    }

    // MARK: - Interaction

    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)
        guard spriteFrame().insetBy(dx: -8, dy: -8).contains(location) else { return }
        mouseDownPoint = location
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let location = event.location(in: self)
        if !isDragging, hypot(location.x - start.x, location.y - start.y) > 6 {
            isDragging = true
            sprite.removeAction(forKey: "move")
            sprite.removeAction(forKey: "anim")
            sprite.removeAction(forKey: "bounce")
            engine.handle(.dragStarted)
            syncState(now: CACurrentMediaTime())
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil }
        if isDragging {
            isDragging = false
            engine.handle(.dragEnded(now: CACurrentMediaTime()))
            syncState(now: CACurrentMediaTime())
        } else if mouseDownPoint != nil {
            engine.handle(.clicked(now: CACurrentMediaTime()))
            syncState(now: CACurrentMediaTime())
            // A click on a pending reminder acknowledges it instead of quipping.
            if bubble.isSticky {
                bubble.dismiss()
            } else {
                onBoop?()
            }
        }
    }

    // MARK: - Speech

    func showBubble(_ text: String, sticky: Bool = false) {
        bubble.show(text, screenWidth: size.width, buddyX: sprite.position.x, sticky: sticky)
        if engine.state == .idle {
            sprite.run(.sequence([
                .repeat(.animate(with: SpriteTextures.talk[eyeDirection]!, timePerFrame: 0.22), count: 4),
                .run { [weak self] in
                    guard let self, self.engine.state == .idle else { return }
                    self.loop(SpriteTextures.idle[self.eyeDirection]!, timePerFrame: 0.6)
                },
            ]), withKey: "anim")
        }
    }

    // MARK: - Geometry helpers

    /// Kiki lives in the right half of the screen only.
    private var walkableMinX: CGFloat { size.width * 0.5 + 16 }
    private var walkableMaxX: CGFloat { size.width - 24 }

    private var spriteHeight: CGFloat { CGFloat(KikiSprites.height) * spriteScale }

    private func spriteFrame() -> CGRect {
        CGRect(
            x: sprite.position.x - CGFloat(KikiSprites.width) * spriteScale / 2,
            y: sprite.position.y,
            width: CGFloat(KikiSprites.width) * spriteScale,
            height: spriteHeight
        )
    }

    private func spriteCenterInScreen() -> CGPoint {
        let origin = view?.window?.frame.origin ?? .zero
        return CGPoint(
            x: origin.x + sprite.position.x,
            y: origin.y + sprite.position.y + spriteHeight / 2
        )
    }

    private func convertFromScreen(_ point: CGPoint) -> CGPoint {
        let origin = view?.window?.frame.origin ?? .zero
        return CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    private func updateClickThrough(cursor: CGPoint) {
        guard let window = view?.window else { return }
        let origin = window.frame.origin
        let hitArea = spriteFrame()
            .insetBy(dx: -10, dy: -10)
            .offsetBy(dx: origin.x, dy: origin.y)
        let shouldReceive = isDragging || hitArea.contains(cursor)
        if window.ignoresMouseEvents == shouldReceive {
            window.ignoresMouseEvents = !shouldReceive
        }
    }
}
