import KursorKidCore
import SpriteKit

/// Converts KikiSprites pixel grids into crisp (nearest-filtered) SKTextures.
enum SpriteTextures {
    static let idle = textures(KikiSprites.idle)
    static let walk = textures(KikiSprites.walk)
    static let dance = textures(KikiSprites.dance)
    static let wave = textures(KikiSprites.wave)
    static let startled = textures(KikiSprites.startled)
    static let boop = textures(KikiSprites.boop)
    static let sit = textures(KikiSprites.sit)
    static let sleep = textures(KikiSprites.sleep)
    static let talk = textures(KikiSprites.talk)

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
