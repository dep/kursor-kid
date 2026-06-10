import AppKit
import ApplicationServices

/// Watches global input. Keystrokes are COUNTED only — key codes and
/// characters are never read or stored. Requires Accessibility trust for the
/// global key-down monitor; everything else degrades gracefully without it.
final class InputMonitor {
    var onKeystroke: (() -> Void)?
    var onFrontmostAppChange: ((String) -> Void)?

    private var keyMonitor: Any?
    private var appObserver: NSObjectProtocol?

    var isTrusted: Bool { AXIsProcessTrusted() }

    func start() {
        startKeyMonitorIfPossible()

        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let name = app.localizedName,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            self?.onFrontmostAppChange?(name)
        }
    }

    /// Shows the system Accessibility prompt (no-op if already trusted).
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Re-attach the key monitor (e.g. after the user grants Accessibility).
    func startKeyMonitorIfPossible() {
        guard keyMonitor == nil, isTrusted else { return }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.onKeystroke?()
        }
    }

    var frontmostAppName: String? {
        let app = NSWorkspace.shared.frontmostApplication
        guard app?.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return app?.localizedName
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
    }
}
