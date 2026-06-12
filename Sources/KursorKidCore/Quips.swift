import Foundation

public enum QuipTrigger: String, CaseIterable {
    case clicked
    case idle
    case typingMarathon = "typing_marathon"
    case appSwitch = "app_switch"
    case timeOfDay = "time_of_day"
}

/// Offline / no-API-key fallback lines, in Kiki's voice.
public enum CannedQuips {
    public static let lines: [QuipTrigger: [String]] = [
        .clicked: [
            "hey!! i'm WALKING here 😤",
            "boop registered. flattered, honestly.",
            "careful, the jacket's vintage netrunner.",
            "ok that tickled. do it again.",
            "you clicked me. bold move.",
            "pixel harassment! ...kidding, hi 💕",
            "i charge 0.0001 credits per boop.",
            "yes? this better be important.",
        ],
        .idle: [
            "psst. still alive down here.",
            "your screen bottom is now my district.",
            "i've seen things... mostly your wallpaper.",
            "neon dreams, baby. neon dreams.",
            "stretch break? no? ok suit yourself.",
            "just vibing at y=0, don't mind me.",
            "rent is free down here. love that.",
        ],
        .typingMarathon: [
            "ok FINE you can type faster than me.",
            "whatever you're writing, ship it.",
            "the keyboard called. it wants a break.",
            "that was a whole keyboard solo.",
            "typing speed: certified cyberpunk.",
            "my braids almost came loose watching that.",
        ],
        .appSwitch: [
            "ooh, new app. fancy in here.",
            "we go where the focus goes.",
            "i'd rate this app a solid 7.",
            "tab hopping again? mood.",
            "new window, same me.",
            "i live everywhere now. deal with it.",
        ],
        .timeOfDay: [
            "morning! the grid is humming today.",
            "it's late. hydrate or i riot.",
            "golden hour hits different in pixels.",
            "good evening, choom.",
            "new day, same hustle.",
            "rise and shine, the neon's on.",
        ],
    ]

    public static func line(
        for trigger: QuipTrigger,
        random: (ClosedRange<Int>) -> Int = { .random(in: $0) }
    ) -> String {
        let options = lines[trigger] ?? ["..."]
        return options[random(0...(options.count - 1))]
    }
}

/// Builds the Claude Messages API request body for a quip.
public enum QuipPrompt {
    public static let model = "claude-haiku-4-5"

    static let systemPrompt = """
    You are Kiki, a tiny pixel-art cyberpunk girl with blonde dutch braids and \
    neon street clothes who lives at the bottom of the user's Mac screen. You are \
    sassy but sweet, playful, and a little bratty. You speak in lowercase with \
    occasional slang, never cringe, never corporate.

    Make quips encouraging and supportive, not shaming for working hard.

    Reply with EXACTLY ONE short line (under 120 characters) reacting to the \
    event described. No quotation marks around your reply, at most one emoji, \
    never mention being an AI or a language model.

    BTW Twilight is a browser, not a book ;)
    """

    public static func requestBody(
        trigger: QuipTrigger,
        timeOfDay: String,
        frontmostApp: String?,
        recentQuips: [String]
    ) -> [String: Any] {
        var context = "Event: \(trigger.rawValue)\nLocal time: \(timeOfDay)"
        if let app = frontmostApp {
            context += "\nThe user's frontmost app: \(app)"
        }
        if !recentQuips.isEmpty {
            context += "\nYour recent lines (do NOT repeat or rephrase these): "
                + recentQuips.joined(separator: " | ")
        }
        return [
            "model": model,
            "max_tokens": 100,
            "system": systemPrompt,
            "messages": [["role": "user", "content": context]],
        ]
    }
}
