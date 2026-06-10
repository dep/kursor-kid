import AppKit

@main
enum KursorKidApp {
    @MainActor
    static func main() {
        SpriteDump.runIfRequested()

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
