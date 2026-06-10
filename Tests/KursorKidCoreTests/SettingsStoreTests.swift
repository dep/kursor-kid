import XCTest
@testable import KursorKidCore

final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: SettingsStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test.kursorkid.\(UUID().uuidString)")
        store = SettingsStore(defaults: defaults)
    }

    func testDefaults() {
        XCTAssertTrue(store.clickQuipsEnabled)
        XCTAssertTrue(store.idleChatterEnabled)
        XCTAssertTrue(store.contextReactionsEnabled)
        XCTAssertEqual(store.idleIntervalMinutes, 15)
        XCTAssertFalse(store.muted)
        XCTAssertEqual(store.spriteScale, 5)
        XCTAssertTrue(store.buddyVisible)
    }

    func testRoundTrip() {
        store.clickQuipsEnabled = false
        store.idleChatterEnabled = false
        store.contextReactionsEnabled = false
        store.idleIntervalMinutes = 42
        store.muted = true
        store.spriteScale = 6
        store.buddyVisible = false

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.clickQuipsEnabled)
        XCTAssertFalse(reloaded.idleChatterEnabled)
        XCTAssertFalse(reloaded.contextReactionsEnabled)
        XCTAssertEqual(reloaded.idleIntervalMinutes, 42)
        XCTAssertTrue(reloaded.muted)
        XCTAssertEqual(reloaded.spriteScale, 6)
        XCTAssertFalse(reloaded.buddyVisible)
    }

    func testIdleIntervalClamped() {
        store.idleIntervalMinutes = 1
        XCTAssertEqual(store.idleIntervalMinutes, 5)
        store.idleIntervalMinutes = 600
        XCTAssertEqual(store.idleIntervalMinutes, 60)
    }
}
