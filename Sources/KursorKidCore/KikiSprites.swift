import Foundation

/// Kiki's pixel-art frames. 24×24 logical pixels, composed from shared row
/// blocks. Rows may be shorter than 24 — PixelArt pads the right edge with
/// transparency.
///
/// Palette characters:
///   H hair    h braid-shade   S skin   P neon pink   C cyan
///   J jacket  p pants         O outline/eyes         W white glint
///   R blush   . transparent
public enum KikiSprites {
    public static let width = 24
    public static let height = 24

    public static let palette: [Character: PixelArt.RGBA] = [
        "H": (242, 209, 107, 255), // blonde hair
        "h": (232, 184, 75, 255),  // braid shade
        "S": (255, 217, 179, 255), // skin
        "P": (255, 46, 136, 255),  // neon pink
        "C": (0, 240, 255, 255),   // cyan
        "J": (43, 43, 69, 255),    // jacket
        "p": (31, 31, 51, 255),    // pants
        "O": (26, 26, 46, 255),    // outline / eyes
        "W": (255, 255, 255, 255), // eye glint
        "R": (217, 106, 139, 255), // blush
    ]

    // MARK: - Shared blocks (each block is rows of the 24-wide canvas)

    static let blank = "........................"

    static let hairTop = [
        ".........HHHHHH",
        ".......HHHHHHHHHH",
        "......HHHHHHHHHHHH",
        ".....HHHHHHHHHHHHHH",
    ]

    // Face block rows 5-10. Eyes + mouth swap per expression. `handRow`
    // appends a raised hand beside the head (for waving).
    static func face(eyes: String, mouth: String, handRow: Int? = nil) -> [String] {
        var rows = [
            ".....hHHSSSSSSSSHHh",
            "....hhHSSSSSSSSSSHhh",
            "....hh.S" + eyes + "S.hh",   // eyes: 8 chars
            "....hh.SRSSSSSSRS.hh",
            "....hh.SS" + mouth + "SS.hh", // mouth: 6 chars
            ".....h..SSSSSSSS..h",
        ]
        if let handRow {
            rows[handRow] = rows[handRow].padding(toLength: 21, withPad: ".", startingAt: 0) + "SS"
        }
        return rows
    }

    static let eyesOpen = "OWSSSSOW"
    static let eyesClosed = "OOSSSSOO"
    static let mouthSmile = "SSOOSS"
    static let mouthOpen = "SOOOOS"
    static let mouthOh = "SSOOSS"

    // Torso block rows 11-15. Variants for arm poses.
    static let torsoArmsDown = [
        "....hh.JJJJJJJJJJ.hh",
        "....hh.JPPJJJJPPJ.hh",
        "....hhSJJJJCCJJJJShh",
        "....hh.JJJJCCJJJJ.hh",
        ".....P..JJJJJJJJ..P",
    ]

    // Arm raised on the right side connecting up toward the waving hand.
    static let torsoWaveArm = [
        "....hh.JJJJJJJJJJ.hhS",
        "....hh.JPPJJJJPPJ.hh",
        "....hhSJJJJCCJJJJ.hh",
        "....hh.JJJJCCJJJJ.hh",
        ".....P..JJJJJJJJ..P",
    ]

    // Both arms up (dance / startled).
    static let torsoArmsUp = [
        "...Shh.JJJJJJJJJJ.hhS",
        "....hhSJPPJJJJPPJShh",
        "....hh.JJJJCCJJJJ.hh",
        "....hh.JJJJCCJJJJ.hh",
        ".....P..JJJJJJJJ..P",
    ]

    // Legs blocks: rows 16-20 + shoes rows 21-22.
    static let legsStand = [
        "........pppppppp",
        "........pppppppp",
        "........ppp..ppp",
        "........ppp..ppp",
        "........ppp..ppp",
        ".......PPPP..PPPP",
        ".......PCCP..PCCP",
    ]

    static let legsSpread = [
        "........pppppppp",
        ".......ppppppppp",
        ".......ppp....ppp",
        "......ppp......ppp",
        "......ppp......ppp",
        ".....PPPP......PPPP",
        ".....PCCP......PCCP",
    ]

    static let legsKickLeft = [
        "........pppppppp",
        "........pppppppp",
        ".....ppppp...ppp",
        "....ppp......ppp",
        "..PPPP.......ppp",
        "..PCCP......PPPP",
        "............PCCP",
    ]

    static let legsKickRight = [
        "........pppppppp",
        "........pppppppp",
        "........ppp...ppppp",
        "........ppp......ppp",
        "........ppp.......PPPP",
        ".......PPPP.......PCCP",
        ".......PCCP",
    ]

    // MARK: - Frame assembly

    static func standing(eyes: String, mouth: String, torso: [String], legs: [String], handRow: Int? = nil) -> [String] {
        [blank] + hairTop + face(eyes: eyes, mouth: mouth, handRow: handRow) + torso + legs + [blank]
    }

    /// Sitting pose: body dropped four rows, legs folded in front.
    static func sitting(eyes: String, mouth: String) -> [String] {
        [
            blank, blank, blank, blank,
            ".........HHHHHH",
            ".......HHHHHHHHHH",
            "......HHHHHHHHHHHH",
            ".....HHHHHHHHHHHHHH",
            ".....hHHSSSSSSSSHHh",
            "....hhHSSSSSSSSSSHhh",
            "....hh.S" + eyes + "S.hh",
            "....hh.SRSSSSSSRS.hh",
            "....hh.SS" + mouth + "SS.hh",
            ".....h..SSSSSSSS..h",
            "....hh.JJJJJJJJJJ.hh",
            "....hh.JPPJJJJPPJ.hh",
            "....hhSJJJJCCJJJJShh",
            ".....P.JJJJCCJJJJ.P",
            ".......pppppppppp",
            "......pppppppppppp",
            ".....PPPppppppppPPP",
            ".....PCCP......PCCP",
            blank, blank,
        ]
    }

    // MARK: - Animations

    public static let idle: [[String]] = [
        standing(eyes: eyesOpen, mouth: mouthSmile, torso: torsoArmsDown, legs: legsStand),
        standing(eyes: eyesClosed, mouth: mouthSmile, torso: torsoArmsDown, legs: legsStand),
    ]

    public static let walk: [[String]] = [
        standing(eyes: eyesOpen, mouth: mouthSmile, torso: torsoArmsDown, legs: legsSpread),
        standing(eyes: eyesOpen, mouth: mouthSmile, torso: torsoArmsDown, legs: legsStand),
        standing(eyes: eyesOpen, mouth: mouthSmile, torso: torsoArmsDown, legs: legsSpread),
        standing(eyes: eyesClosed, mouth: mouthSmile, torso: torsoArmsDown, legs: legsStand),
    ]

    public static let dance: [[String]] = [
        standing(eyes: eyesOpen, mouth: mouthOpen, torso: torsoArmsUp, legs: legsKickLeft),
        standing(eyes: eyesClosed, mouth: mouthSmile, torso: torsoArmsDown, legs: legsStand),
        standing(eyes: eyesOpen, mouth: mouthOpen, torso: torsoArmsUp, legs: legsKickRight),
        standing(eyes: eyesClosed, mouth: mouthSmile, torso: torsoArmsDown, legs: legsSpread),
    ]

    public static let wave: [[String]] = [
        standing(eyes: eyesOpen, mouth: mouthSmile, torso: torsoWaveArm, legs: legsStand, handRow: 1),
        standing(eyes: eyesOpen, mouth: mouthOpen, torso: torsoWaveArm, legs: legsStand, handRow: 3),
    ]

    public static let startled: [[String]] = [
        standing(eyes: eyesOpen, mouth: mouthOh, torso: torsoArmsUp, legs: legsSpread),
    ]

    public static let boop: [[String]] = [
        standing(eyes: eyesClosed, mouth: mouthOpen, torso: torsoArmsDown, legs: legsStand),
    ]

    public static let sit: [[String]] = [
        sitting(eyes: eyesOpen, mouth: mouthSmile),
    ]

    public static let sleep: [[String]] = [
        sitting(eyes: eyesClosed, mouth: mouthSmile),
        sitting(eyes: eyesClosed, mouth: mouthOpen),
    ]

    public static let talk: [[String]] = [
        standing(eyes: eyesOpen, mouth: mouthOpen, torso: torsoArmsDown, legs: legsStand),
        standing(eyes: eyesOpen, mouth: mouthSmile, torso: torsoArmsDown, legs: legsStand),
    ]

    public static let allAnimations: [String: [[String]]] = [
        "idle": idle, "walk": walk, "dance": dance, "wave": wave,
        "startled": startled, "boop": boop, "sit": sit, "sleep": sleep, "talk": talk,
    ]
}
