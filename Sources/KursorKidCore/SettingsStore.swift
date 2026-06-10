import Foundation

/// User-tweakable settings, persisted in UserDefaults. The API key is NOT
/// stored here — it lives in the Keychain (see KeychainStore in the app target).
public final class SettingsStore {
    private let defaults: UserDefaults

    private enum Key {
        static let clickQuips = "clickQuipsEnabled"
        static let idleChatter = "idleChatterEnabled"
        static let contextReactions = "contextReactionsEnabled"
        static let idleInterval = "idleIntervalMinutes"
        static let muted = "muted"
        static let spriteScale = "spriteScale"
        static let buddyVisible = "buddyVisible"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var clickQuipsEnabled: Bool {
        get { bool(Key.clickQuips, default: true) }
        set { defaults.set(newValue, forKey: Key.clickQuips) }
    }

    public var idleChatterEnabled: Bool {
        get { bool(Key.idleChatter, default: true) }
        set { defaults.set(newValue, forKey: Key.idleChatter) }
    }

    public var contextReactionsEnabled: Bool {
        get { bool(Key.contextReactions, default: true) }
        set { defaults.set(newValue, forKey: Key.contextReactions) }
    }

    /// Minutes between idle chatter quips. Clamped to 5...60.
    public var idleIntervalMinutes: Int {
        get {
            let value = defaults.object(forKey: Key.idleInterval) as? Int ?? 15
            return min(max(value, 5), 60)
        }
        set { defaults.set(min(max(newValue, 5), 60), forKey: Key.idleInterval) }
    }

    public var muted: Bool {
        get { bool(Key.muted, default: false) }
        set { defaults.set(newValue, forKey: Key.muted) }
    }

    /// Integer pixel-art scale factor (4, 5, or 6).
    public var spriteScale: Int {
        get { defaults.object(forKey: Key.spriteScale) as? Int ?? 5 }
        set { defaults.set(newValue, forKey: Key.spriteScale) }
    }

    public var buddyVisible: Bool {
        get { bool(Key.buddyVisible, default: true) }
        set { defaults.set(newValue, forKey: Key.buddyVisible) }
    }

    private func bool(_ key: String, default defaultValue: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }
}
