import XCTest
@testable import KursorKidCore

final class QuipsTests: XCTestCase {
    func testCannedQuipsExistForEveryTrigger() {
        for trigger in QuipTrigger.allCases {
            XCTAssertGreaterThanOrEqual(CannedQuips.lines[trigger]?.count ?? 0, 6,
                                        "need ≥6 canned lines for \(trigger)")
        }
    }

    func testCannedLinePicksFromCategory() {
        let line = CannedQuips.line(for: .clicked) { range in range.lowerBound }
        XCTAssertEqual(line, CannedQuips.lines[.clicked]?.first)
    }

    func testRequestBodyShape() throws {
        let body = QuipPrompt.requestBody(
            trigger: .clicked,
            timeOfDay: "14:30 on a Tuesday",
            frontmostApp: "Xcode",
            recentQuips: ["hi there", "boop received"]
        )
        XCTAssertEqual(body["model"] as? String, "claude-haiku-4-5")
        XCTAssertEqual(body["max_tokens"] as? Int, 100)
        let system = try XCTUnwrap(body["system"] as? String)
        XCTAssertTrue(system.contains("Kiki"))
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        let content = try XCTUnwrap(messages[0]["content"] as? String)
        XCTAssertTrue(content.contains("clicked"))
        XCTAssertTrue(content.contains("Xcode"))
        XCTAssertTrue(content.contains("boop received"))
        // Body must be valid JSON
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    func testRequestBodyOmitsAppWhenNil() throws {
        let body = QuipPrompt.requestBody(trigger: .idle, timeOfDay: "09:00", frontmostApp: nil, recentQuips: [])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages[0]["content"] as? String)
        XCTAssertFalse(content.contains("frontmost app"))
    }
}
