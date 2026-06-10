import SpriteKit

/// Pixel-styled speech bubble that floats above Kiki's head.
final class SpeechBubble: SKNode {
    private var currentBubble: SKNode?

    func show(_ text: String, screenWidth: CGFloat, buddyX: CGFloat) {
        currentBubble?.removeAllActions()
        currentBubble?.removeFromParent()

        let label = SKLabelNode(text: text)
        label.fontName = "Menlo-Bold"
        label.fontSize = 13
        label.fontColor = NSColor(red: 0.10, green: 0.10, blue: 0.18, alpha: 1)
        label.numberOfLines = 0
        label.preferredMaxLayoutWidth = 240
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center

        let padding: CGFloat = 10
        let size = label.calculateAccumulatedFrame().size
        let rect = CGRect(
            x: -size.width / 2 - padding,
            y: -size.height / 2 - padding,
            width: size.width + padding * 2,
            height: size.height + padding * 2
        )
        let background = SKShapeNode(rect: rect, cornerRadius: 4)
        background.fillColor = NSColor(red: 0.96, green: 0.96, blue: 1.0, alpha: 0.97)
        background.strokeColor = NSColor(red: 1.0, green: 0.18, blue: 0.53, alpha: 1)
        background.lineWidth = 2

        let tail = SKShapeNode(path: {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -6, y: rect.minY + 1))
            path.addLine(to: CGPoint(x: 6, y: rect.minY + 1))
            path.addLine(to: CGPoint(x: 0, y: rect.minY - 8))
            path.closeSubpath()
            return path
        }())
        tail.fillColor = background.fillColor
        tail.strokeColor = background.strokeColor
        tail.lineWidth = 2

        let bubble = SKNode()
        bubble.addChild(background)
        bubble.addChild(tail)
        bubble.addChild(label)

        // Clamp horizontally so the bubble never runs off-screen. The bubble
        // node itself stays anchored above Kiki; offset its content instead.
        let halfWidth = rect.width / 2
        var offsetX: CGFloat = 0
        if buddyX - halfWidth < 8 { offsetX = halfWidth - buddyX + 8 }
        if buddyX + halfWidth > screenWidth - 8 { offsetX = (screenWidth - 8) - buddyX - halfWidth }
        // Shift content up so the node's origin is the TAIL TIP — the bubble
        // then grows upward and never covers Kiki, however many lines it has.
        let offsetY = 8 - rect.minY
        background.position = CGPoint(x: offsetX, y: offsetY)
        label.position = CGPoint(x: offsetX, y: offsetY)
        tail.position.y = offsetY

        bubble.alpha = 0
        bubble.setScale(0.6)
        addChild(bubble)
        currentBubble = bubble

        bubble.run(.sequence([
            .group([.fadeIn(withDuration: 0.15), .scale(to: 1.0, duration: 0.15)]),
            .wait(forDuration: 6.0),
            .fadeOut(withDuration: 0.3),
            .removeFromParent(),
        ]))
    }
}
