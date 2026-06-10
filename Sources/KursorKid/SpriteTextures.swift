import KursorKidCore
import SpriteKit

/// Converts KikiSprites pixel grids into crisp (nearest-filtered) SKTextures.
/// Stationary animations are keyed by gaze direction for cursor-following eyes.
enum SpriteTextures {
    typealias EyeDirection = KikiSprites.EyeDirection

    static let idle = directional(KikiSprites.idleFrames)
    static let wave = directional(KikiSprites.waveFrames)
    static let sit = directional(KikiSprites.sitFrames)
    static let talk = directional(KikiSprites.talkFrames)

    static let walk = textures(KikiSprites.walk)
    static let dance = textures(KikiSprites.dance)
    static let startled = textures(KikiSprites.startled)
    static let boop = textures(KikiSprites.boop)
    static let sleep = textures(KikiSprites.sleep)

    static let claudeThinking = textures(KikiSprites.claudeThinking)
    static let claudeWorking = textures(KikiSprites.claudeWorking)
    static let claudeWaiting = textures(KikiSprites.claudeWaiting)
    static let thoughtDots = texture(KikiSprites.thoughtDots)
    static let exclaim = texture(KikiSprites.exclaim)

    /// A tiny pink heart used for boop particles.
    static let heart: SKTexture = {
        let grid = [
            ".P.P.",
            "PPPPP",
            "PPPPP",
            ".PPP.",
            "..P..",
        ]
        return texture(grid)
    }()

    private static func directional(
        _ builder: (EyeDirection) -> [[String]]
    ) -> [EyeDirection: [SKTexture]] {
        Dictionary(uniqueKeysWithValues: EyeDirection.allCases.map { ($0, textures(builder($0))) })
    }

    private static func textures(_ frames: [[String]]) -> [SKTexture] {
        frames.map(texture)
    }

    private static func texture(_ grid: [String]) -> SKTexture {
        guard let image = PixelArt.image(from: grid, palette: KikiSprites.palette) else {
            return SKTexture()
        }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return texture
    }
}
