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

    // MARK: - Eyes (two-row anime style, 10 chars per row)

    public enum EyeDirection: CaseIterable, Sendable {
        case left, center, right
    }

    /// Big two-row sparkle eyes. Gaze direction = the whole eye block shifted
    /// one pixel within the face.
    static func eyeRows(_ direction: EyeDirection) -> (top: String, bottom: String) {
        switch direction {
        case .center: ("SOWOSSOWOS", "SOOOSSOOOS")
        case .left: ("OWOSSOWOSS", "OOOSSOOOSS")
        case .right: ("SSOWOSSOWO", "SSOOOSSOOO")
        }
    }

    static let eyesClosed = (top: "SSSSSSSSSS", bottom: "SOOOSSOOOS")

    static let mouthSmile = "SSOOSS"
    static let mouthOpen = "SOOOOS"

    // Face block rows 5-10: hairline, eye top (with hair edges), eye bottom,
    // blush, mouth, chin. `handRow` appends a raised hand beside the head.
    static func face(eyes: (top: String, bottom: String), mouth: String, handRow: Int? = nil) -> [String] {
        var rows = [
            ".....hHHSSSSSSSSHHh",
            "....hhH" + eyes.top + "Hhh",
            "....hh." + eyes.bottom + ".hh",
            "....hh.SRSSSSSSRS.hh",
            "....hh.SS" + mouth + "SS.hh", // mouth: 6 chars
            ".....h..SSSSSSSS..h",
        ]
        if let handRow {
            rows[handRow] = rows[handRow].padding(toLength: 21, withPad: ".", startingAt: 0) + "SS"
        }
        return rows
    }

    // Torso block rows 11-15. Variants for arm poses.
    static let torsoArmsDown = [
        "....hh.JJJJJJJJJJ.hh",
        "....hh.JPPJJJJPPJ.hh",
        "....hhSJJJJCCJJJJShh",
        "....hh.JJJJCCJJJJ.hh",
        ".....P..JJJJJJJJ..P",
    ]

    // Arms crossed (impatient waiting pose).
    static let torsoArmsCrossed = [
        "....hh.JJJJJJJJJJ.hh",
        "....hh.JPPJJJJPPJ.hh",
        "....hh.JSSSSSSSSJ.hh",
        "....hh.JJJJJJJJJJ.hh",
        ".....P..JJJJJJJJ..P",
    ]

    // Foot-tap variant of standing legs: right heel raised.
    static let legsTap = [
        "........pppppppp",
        "........pppppppp",
        "........ppp..ppp",
        "........ppp..ppp",
        "........ppp..PPPP",
        ".......PPPP..PCCP",
        ".......PCCP",
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

    static func standing(eyes: (top: String, bottom: String), mouth: String, torso: [String], legs: [String], handRow: Int? = nil) -> [String] {
        [blank] + hairTop + face(eyes: eyes, mouth: mouth, handRow: handRow) + torso + legs + [blank]
    }

    /// Sitting pose: body dropped four rows, legs folded in front.
    static func sitting(eyes: (top: String, bottom: String), mouth: String) -> [String] {
        [
            blank, blank, blank, blank,
            ".........HHHHHH",
            ".......HHHHHHHHHH",
            "......HHHHHHHHHHHH",
            ".....HHHHHHHHHHHHHH",
            ".....hHHSSSSSSSSHHh",
            "....hhH" + eyes.top + "Hhh",
            "....hh." + eyes.bottom + ".hh",
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

    /// Stationary animations come in three gaze directions so Kiki's eyes can
    /// follow the cursor. Moving animations always look straight ahead.

    public static func idleFrames(_ direction: EyeDirection) -> [[String]] {
        [
            standing(eyes: eyeRows(direction), mouth: mouthSmile, torso: torsoArmsDown, legs: legsStand),
            standing(eyes: eyesClosed, mouth: mouthSmile, torso: torsoArmsDown, legs: legsStand),
        ]
    }

    public static func waveFrames(_ direction: EyeDirection) -> [[String]] {
        [
            standing(eyes: eyeRows(direction), mouth: mouthSmile, torso: torsoWaveArm, legs: legsStand, handRow: 1),
            standing(eyes: eyeRows(direction), mouth: mouthOpen, torso: torsoWaveArm, legs: legsStand, handRow: 3),
        ]
    }

    public static func sitFrames(_ direction: EyeDirection) -> [[String]] {
        [sitting(eyes: eyeRows(direction), mouth: mouthSmile)]
    }

    public static func talkFrames(_ direction: EyeDirection) -> [[String]] {
        [
            standing(eyes: eyeRows(direction), mouth: mouthOpen, torso: torsoArmsDown, legs: legsStand),
            standing(eyes: eyeRows(direction), mouth: mouthSmile, torso: torsoArmsDown, legs: legsStand),
        ]
    }

    public static let idle = idleFrames(.center)
    public static let wave = waveFrames(.center)
    public static let sit = sitFrames(.center)
    public static let talk = talkFrames(.center)

    public static let walk: [[String]] = [
        standing(eyes: eyeRows(.center), mouth: mouthSmile, torso: torsoArmsDown, legs: legsSpread),
        standing(eyes: eyeRows(.center), mouth: mouthSmile, torso: torsoArmsDown, legs: legsStand),
        standing(eyes: eyeRows(.center), mouth: mouthSmile, torso: torsoArmsDown, legs: legsSpread),
        standing(eyes: eyesClosed, mouth: mouthSmile, torso: torsoArmsDown, legs: legsStand),
    ]

    public static let dance: [[String]] = [
        standing(eyes: eyeRows(.center), mouth: mouthOpen, torso: torsoArmsUp, legs: legsKickLeft),
        standing(eyes: eyesClosed, mouth: mouthSmile, torso: torsoArmsDown, legs: legsStand),
        standing(eyes: eyeRows(.center), mouth: mouthOpen, torso: torsoArmsUp, legs: legsKickRight),
        standing(eyes: eyesClosed, mouth: mouthSmile, torso: torsoArmsDown, legs: legsSpread),
    ]

    public static let startled: [[String]] = [
        standing(eyes: eyeRows(.center), mouth: mouthOpen, torso: torsoArmsUp, legs: legsSpread),
    ]

    public static let boop: [[String]] = [
        standing(eyes: eyesClosed, mouth: mouthOpen, torso: torsoArmsDown, legs: legsStand),
    ]

    public static let sleep: [[String]] = [
        sitting(eyes: eyesClosed, mouth: mouthSmile),
        sitting(eyes: eyesClosed, mouth: mouthOpen),
    ]

    // MARK: - Claude Code activity poses

    /// VR visor "eyes": a glowing cyan band with a white glint that sweeps
    /// across frame to frame, like data streaming past.
    static func visorRows(glint: Int) -> (top: String, bottom: String) {
        var top = Array("OCCCCCCCCO")
        top[glint] = "W"
        return (String(top), "OCCCCCCCCO")
    }

    /// Jacked in: VR headset on, hands grabbing at holograms.
    public static let claudeThinking: [[String]] = [
        standing(eyes: visorRows(glint: 2), mouth: mouthSmile, torso: torsoArmsUp, legs: legsStand),
        standing(eyes: visorRows(glint: 4), mouth: mouthOpen, torso: torsoWaveArm, legs: legsStand, handRow: 1),
        standing(eyes: visorRows(glint: 6), mouth: mouthSmile, torso: torsoArmsUp, legs: legsSpread),
        standing(eyes: visorRows(glint: 7), mouth: mouthOpen, torso: torsoWaveArm, legs: legsStand, handRow: 3),
    ]

    /// Heads-down on a tiny laptop (we see the glowing lid from behind).
    public static let claudeWorking: [[String]] = [
        workingFrame(lid: "......OCCCCCCCCCCCCO"),
        workingFrame(lid: "......OCCWCCCCCCWCCO"),
    ]

    private static func workingFrame(lid: String) -> [String] {
        var frame = sitting(eyes: eyeRows(.center), mouth: mouthSmile)
        frame[18] = lid
        return frame
    }

    /// Arms crossed, foot tapping. Where ARE you?
    public static let claudeWaiting: [[String]] = [
        standing(eyes: eyeRows(.center), mouth: mouthSmile, torso: torsoArmsCrossed, legs: legsStand),
        standing(eyes: eyeRows(.left), mouth: mouthSmile, torso: torsoArmsCrossed, legs: legsTap),
    ]

    /// Badge sprites shown above her head during Claude activity.
    public static let thoughtDots = ["WW..WW..WW", "WW..WW..WW"]
    public static let exclaim = ["PP", "PP", "PP", "PP", "..", "PP"]

    public static let allAnimations: [String: [[String]]] = {
        var animations: [String: [[String]]] = [
            "walk": walk, "dance": dance, "startled": startled,
            "boop": boop, "sleep": sleep,
            "claude-thinking": claudeThinking,
            "claude-working": claudeWorking,
            "claude-waiting": claudeWaiting,
        ]
        for direction in EyeDirection.allCases {
            animations["idle-\(direction)"] = idleFrames(direction)
            animations["wave-\(direction)"] = waveFrames(direction)
            animations["sit-\(direction)"] = sitFrames(direction)
            animations["talk-\(direction)"] = talkFrames(direction)
        }
        return animations
    }()
}
