import Foundation
import KursorKidCore

/// Model-exploration variants of Kiki — different proportions, head shapes,
/// and art directions. All keep the blonde dutch braids. Dev-only, used by
/// --dump-variants.
enum KikiVariants {
    typealias Palette = [Character: PixelArt.RGBA]

    static var all: [(key: String, grid: [String], palette: Palette)] {
        let pal = KikiSprites.palette
        return [
            ("1-classic-chibi", KikiSprites.idle[0], pal),
            ("2-tall-lanky", tallLanky, pal),
            ("3-tiny-bean", tinyBean, pal),
            ("4-anime-eyes", animeEyes, pal),
            ("5-puffer", puffer, pal),
            ("6-edgy-bangs", edgyBangs, pal),
            ("7-8bit-retro", retro8bit, pal),
            ("8-kawaii-pastel", kawaii, kawaiiPalette),
        ]
    }

    /// 20×28 — realistic-ish proportions: small head, neck, long legs.
    static let tallLanky: [String] = [
        "",
        "......HHHHHHHH",
        ".....HHHHHHHHHH",
        "....hHHHHHHHHHHh",
        "....hHSSSSSSSSHh",
        "....hHSOWSSOWSHh",
        "....hhSSSSSSSShh",
        "....hh.SSOOSS.hh",
        "....hh..SSSS..hh",
        "....hh...SS...hh",
        "....hh.JJJJJJ.hh",
        "....hhJJJJJJJJhh",
        "....hhJPPJJPPJhh",
        "....hSJJJCCJJJSh",
        ".....SJJJCCJJJS",
        ".....PJJJJJJJJP",
        "......JJJJJJJJ",
        "......pppppppp",
        "......pppppppp",
        "......ppp..ppp",
        "......ppp..ppp",
        "......ppp..ppp",
        "......ppp..ppp",
        "......ppp..ppp",
        ".....PPPP..PPPP",
        ".....PCCP..PCCP",
        "",
        "",
    ]

    /// 16×16 — super-deformed smol bean, mostly head.
    static let tinyBean: [String] = [
        "......HHHH",
        "....HHHHHHHH",
        "...HHHHHHHHHH",
        "..hHHSSSSSSHHh",
        "..hHSOWSSOWSHh",
        "..hh.SSSSSS.hh",
        "..hh.SROORS.hh",
        "..hh..SSSS..hh",
        "..hP.JJJJJJ.Ph",
        "....JPJCCJPJ",
        "....JJJCCJJJ",
        ".....pppppp",
        ".....pp..pp",
        "....PPP..PPP",
        "....PCC..CCP",
        "",
    ]

    /// 24×24 — classic body but huge two-row sparkle anime eyes.
    static let animeEyes: [String] = [
        "",
        ".........HHHHHH",
        ".......HHHHHHHHHH",
        "......HHHHHHHHHHHH",
        ".....HHHHHHHHHHHHHH",
        ".....hHHSSSSSSSSHHh",
        "....hhHSOWOSSOWOSHhh",
        "....hh.SOOOSSOOOS.hh",
        "....hh.SRSSSSSSRS.hh",
        "....hh.SSSSOOSSSS.hh",
        ".....h..SSSSSSSS..h",
        "....hh.JJJJJJJJJJ.hh",
        "....hh.JPPJJJJPPJ.hh",
        "....hhSJJJJCCJJJJShh",
        "....hh.JJJJCCJJJJ.hh",
        ".....P..JJJJJJJJ..P",
        "........pppppppp",
        "........pppppppp",
        "........ppp..ppp",
        "........ppp..ppp",
        "........ppp..ppp",
        ".......PPPP..PPPP",
        ".......PCCP..PCCP",
        "",
    ]

    /// 24×24 — round silhouette, oversized puffer jacket wider than her head.
    static let puffer: [String] = [
        "",
        ".........HHHHHH",
        ".......HHHHHHHHHH",
        "......HHHHHHHHHHHH",
        ".....HHHHHHHHHHHHHH",
        ".....hHHSSSSSSSSHHh",
        "....hhHSSSSSSSSSSHhh",
        "....hh.SOWSSSSOWS.hh",
        "....hh.SRSSSSSSRS.hh",
        "....hh.SSSSOOSSSS.hh",
        ".....h..SSSSSSSS..h",
        "....hhJJJJJJJJJJJJhh",
        "....hhJJPPJJJJPPJJhh",
        "...hSJJJJJJCCJJJJJSh",
        "...h.JJJJJJCCJJJJJ.h",
        "....PJJJJJJJJJJJJP",
        ".....JJJJJJJJJJJJ",
        "........pppppppp",
        "........ppp..ppp",
        "........ppp..ppp",
        "........ppp..ppp",
        ".......PPPP..PPPP",
        ".......PCCP..PCCP",
        "",
    ]

    /// 24×24 — long swoop bangs covering one eye, smirk. Attitude.
    static let edgyBangs: [String] = [
        "",
        ".........HHHHHH",
        ".......HHHHHHHHHH",
        "......HHHHHHHHHHHH",
        ".....HHHHHHHHHHHHHH",
        ".....hHHSSSSSHHHHHh",
        "....hhHSSSSSSHHHHHhh",
        "....hh.SOWSSSHHHS.hh",
        "....hh.SRSSSSSHRS.hh",
        "....hh.SSSOOSSSSS.hh",
        ".....h..SSSSSSSS..h",
        "....hh.JJJJJJJJJJ.hh",
        "....hh.JPPJJJJPPJ.hh",
        "....hhSJJJJCCJJJJShh",
        "....hh.JJJJCCJJJJ.hh",
        ".....P..JJJJJJJJ..P",
        "........pppppppp",
        "........pppppppp",
        "........ppp..ppp",
        "........ppp..ppp",
        "........ppp..ppp",
        ".......PPPP..PPPP",
        ".......PCCP..PCCP",
        "",
    ]

    /// 16×16 — chunky NES-era look with hard dark outlines everywhere.
    static let retro8bit: [String] = [
        "....OOOOOOOO",
        "...OHHHHHHHHO",
        "..OHHHHHHHHHHO",
        ".OhOHHHHHHHHOhO",
        ".OhOSSSSSSSSOhO",
        ".OhOSWOSSWOSOhO",
        ".OhOSSSSSSSSOhO",
        ".OhOSSOOOOSSOhO",
        ".OOOOJJJJJJOOOO",
        "..OJJPPJJPPJJO",
        "..OJJJJCCJJJJO",
        "...OppppppppO",
        "...OppOOOOppO",
        "...OppO..OppO",
        "..OPPPO..OPPPO",
        "..OOOOO..OOOOO",
    ]

    /// 24×24 — classic structure, pastel palette, double blush, tiny mouth.
    static let kawaii: [String] = [
        "",
        ".........HHHHHH",
        ".......HHHHHHHHHH",
        "......HHHHHHHHHHHH",
        ".....HHHHHHHHHHHHHH",
        ".....hHHSSSSSSSSHHh",
        "....hhHSSSSSSSSSSHhh",
        "....hh.SOWSSSSOWS.hh",
        "....hh.RRSSSSSSRR.hh",
        "....hh.SSSSSOSSSS.hh",
        ".....h..SSSSSSSS..h",
        "....hh.JJJJJJJJJJ.hh",
        "....hh.JPPJJJJPPJ.hh",
        "....hhSJJJJCCJJJJShh",
        "....hh.JJJJCCJJJJ.hh",
        ".....P..JJJJJJJJ..P",
        "........pppppppp",
        "........pppppppp",
        "........ppp..ppp",
        "........ppp..ppp",
        "........ppp..ppp",
        ".......PPPP..PPPP",
        ".......PCCP..PCCP",
        "",
    ]

    static var kawaiiPalette: Palette {
        var p = KikiSprites.palette
        p["H"] = (250, 226, 156, 255) // softer gold
        p["h"] = (238, 205, 122, 255)
        p["P"] = (255, 160, 200, 255) // pastel pink
        p["C"] = (165, 255, 222, 255) // mint
        p["J"] = (122, 110, 160, 255) // soft lavender
        p["p"] = (96, 86, 130, 255)
        p["R"] = (255, 150, 170, 255) // stronger blush
        return p
    }
}
