import XCTest
@testable import KursorKidCore

final class SmokeTests: XCTestCase {
    func testVersionInfo() {
        XCTAssertEqual(KursorKidInfo.buddyName, "Kiki")
        XCTAssertFalse(KursorKidInfo.version.isEmpty)
    }
}
