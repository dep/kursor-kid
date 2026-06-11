import KursorKidCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let settings: SettingsStore
    let calendarMonitor: CalendarMonitor
    var onScaleChange: (Int) -> Void
    var onChatterChange: () -> Void

    @State private var apiKey: String = KeychainStore.apiKey() ?? ""
    @State private var keyTestState: KeyTestState = .idle
    @State private var clickQuips: Bool
    @State private var idleChatter: Bool
    @State private var contextReactions: Bool
    @State private var idleInterval: Double
    @State private var muted: Bool
    @State private var scale: Int
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var calendarReminders: Bool
    @State private var calendars: [CalendarMonitor.CalendarInfo] = []
    @State private var enabledIDs: Set<String>?
    @State private var hasCalendarAccess = false
    @State private var calendarAccessDenied = false

    enum KeyTestState: Equatable {
        case idle, testing, success, failure(String)
    }

    init(settings: SettingsStore, calendarMonitor: CalendarMonitor, onScaleChange: @escaping (Int) -> Void, onChatterChange: @escaping () -> Void) {
        self.settings = settings
        self.calendarMonitor = calendarMonitor
        self.onScaleChange = onScaleChange
        self.onChatterChange = onChatterChange
        _clickQuips = State(initialValue: settings.clickQuipsEnabled)
        _idleChatter = State(initialValue: settings.idleChatterEnabled)
        _contextReactions = State(initialValue: settings.contextReactionsEnabled)
        _idleInterval = State(initialValue: Double(settings.idleIntervalMinutes))
        _muted = State(initialValue: settings.muted)
        _scale = State(initialValue: settings.spriteScale)
        _calendarReminders = State(initialValue: settings.calendarRemindersEnabled)
        _enabledIDs = State(initialValue: settings.enabledCalendarIDs)
    }

    var body: some View {
        Form {
            Section("Claude API") {
                SecureField("Anthropic API key", text: $apiKey)
                    .onChange(of: apiKey) { _, newValue in
                        KeychainStore.setAPIKey(newValue)
                        keyTestState = .idle
                    }
                HStack {
                    Button("Test Key") { testKey() }
                        .disabled(apiKey.isEmpty || keyTestState == .testing)
                    switch keyTestState {
                    case .idle: EmptyView()
                    case .testing: ProgressView().controlSize(.small)
                    case .success: Label("Key works! Kiki is online 💖", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failure(let message): Label(message, systemImage: "xmark.circle.fill").foregroundStyle(.red)
                    }
                }
                Text("Stored in your Keychain. Without a key, Kiki uses built-in lines.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Chatter") {
                Toggle("Mute everything", isOn: $muted)
                    .onChange(of: muted) { _, v in settings.muted = v }
                Toggle("Quip when clicked", isOn: $clickQuips)
                    .onChange(of: clickQuips) { _, v in settings.clickQuipsEnabled = v }
                Toggle("Random idle chatter", isOn: $idleChatter)
                    .onChange(of: idleChatter) { _, v in
                        settings.idleChatterEnabled = v
                        onChatterChange()
                    }
                Toggle("React to context (apps, typing, time of day)", isOn: $contextReactions)
                    .onChange(of: contextReactions) { _, v in settings.contextReactionsEnabled = v }
                if idleChatter {
                    VStack(alignment: .leading) {
                        Slider(value: $idleInterval, in: 5...60, step: 5) {
                            Text("Idle chatter every \(Int(idleInterval)) min")
                        }
                        .onChange(of: idleInterval) { _, v in
                            settings.idleIntervalMinutes = Int(v)
                            onChatterChange()
                        }
                    }
                }
            }

            Section("Calendar") {
                Toggle("Remind me 2 min before events", isOn: $calendarReminders)
                    .onChange(of: calendarReminders) { _, v in
                        settings.calendarRemindersEnabled = v
                        if v { refreshCalendarAccess() }
                    }
                if calendarReminders {
                    if hasCalendarAccess {
                        calendarPicker
                    } else if calendarAccessDenied {
                        Label("Calendar access denied", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars")!)
                        }
                    } else {
                        Button("Grant Calendar Access") {
                            Task {
                                _ = await calendarMonitor.requestAccess()
                                refreshCalendarAccess()
                            }
                        }
                    }
                }
            }

            Section("Behavior") {
                Picker("Kiki's size", selection: $scale) {
                    Text("Tiny (2×)").tag(2)
                    Text("Small (4×)").tag(4)
                    Text("Medium (5×)").tag(5)
                    Text("Large (6×)").tag(6)
                }
                .onChange(of: scale) { _, v in
                    settings.spriteScale = v
                    onScaleChange(v)
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enable in
                        do {
                            if enable {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .onAppear { refreshCalendarAccess() }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Checkbox per calendar, grouped by account source.
    private var calendarPicker: some View {
        let grouped = Dictionary(grouping: calendars, by: \.source)
        return ForEach(grouped.keys.sorted(), id: \.self) { source in
            VStack(alignment: .leading, spacing: 4) {
                Text(source).font(.caption).foregroundStyle(.secondary)
                ForEach(grouped[source]!) { calendar in
                    Toggle(calendar.title, isOn: calendarBinding(calendar.id))
                }
            }
        }
    }

    private func calendarBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { enabledIDs?.contains(id) ?? true },
            set: { isOn in
                // First curation materializes the "all calendars" nil sentinel.
                var ids = enabledIDs ?? Set(calendars.map(\.id))
                if isOn { ids.insert(id) } else { ids.remove(id) }
                enabledIDs = ids
                settings.enabledCalendarIDs = ids
            }
        )
    }

    private func refreshCalendarAccess() {
        hasCalendarAccess = calendarMonitor.hasFullAccess
        calendarAccessDenied = calendarMonitor.accessDenied
        if hasCalendarAccess {
            calendars = calendarMonitor.calendars()
        }
    }

    private func testKey() {
        keyTestState = .testing
        let service = QuipService(apiKeyProvider: { apiKey })
        Task {
            // fetchQuip never throws; distinguish success by doing a raw probe.
            let probe = await Self.probeKey(apiKey)
            await MainActor.run {
                keyTestState = probe == nil ? .success : .failure(probe!)
            }
            _ = service // keep alive
        }
    }

    /// Minimal direct call so auth failures are distinguishable from fallbacks.
    static func probeKey(_ key: String) async -> String? {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": QuipPrompt.model,
            "max_tokens": 8,
            "messages": [["role": "user", "content": "hi"]],
        ])
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "No response" }
            switch http.statusCode {
            case 200: return nil
            case 401: return "Invalid key"
            case 429: return nil // rate limited means the key itself works
            default: return "API error \(http.statusCode)"
            }
        } catch {
            return "Network error"
        }
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: SettingsStore
    private let calendarMonitor: CalendarMonitor
    private let onScaleChange: (Int) -> Void
    private let onChatterChange: () -> Void

    init(settings: SettingsStore, calendarMonitor: CalendarMonitor, onScaleChange: @escaping (Int) -> Void, onChatterChange: @escaping () -> Void) {
        self.settings = settings
        self.calendarMonitor = calendarMonitor
        self.onScaleChange = onScaleChange
        self.onChatterChange = onChatterChange
    }

    func show() {
        if window == nil {
            let view = SettingsView(
                settings: settings,
                calendarMonitor: calendarMonitor,
                onScaleChange: onScaleChange,
                onChatterChange: onChatterChange
            )
            let hosting = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: hosting)
            win.title = "Kursor Kid Settings"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            window = win
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
