import XCTest
@testable import KursorKidCore

final class PixelArtTests: XCTestCase {
    func testImageDimensionsMatchGrid() throws {
        let image = try XCTUnwrap(PixelArt.image(from: ["PP", "P.", ".P"], palette: ["P": (255, 0, 0, 255)]))
        XCTAssertEqual(image.width, 2)
        XCTAssertEqual(image.height, 3)
    }

    func testUnevenRowsArePadded() throws {
        let image = try XCTUnwrap(PixelArt.image(from: ["PPPP", "P"], palette: ["P": (255, 0, 0, 255)]))
        XCTAssertEqual(image.width, 4)
        XCTAssertEqual(image.height, 2)
    }

    func testPixelColors() throws {
        let image = try XCTUnwrap(PixelArt.image(from: ["P."], palette: ["P": (255, 46, 136, 255)]))
        let data = try XCTUnwrap(image.dataProvider?.data as Data?)
        // RGBA premultiplied-last, 4 bytes per pixel
        XCTAssertEqual([UInt8](data.prefix(4)), [255, 46, 136, 255])
        XCTAssertEqual(data[7], 0, "second pixel must be transparent")
    }

    func testAllKikiFramesAreConsistent() {
        for (name, frames) in KikiSprites.allAnimations {
            XCTAssertFalse(frames.isEmpty, "\(name) has no frames")
            for (i, frame) in frames.enumerated() {
                XCTAssertEqual(frame.count, KikiSprites.height, "\(name)[\(i)] wrong height")
                for row in frame {
                    XCTAssertLessThanOrEqual(row.count, KikiSprites.width, "\(name)[\(i)] row too wide")
                    for ch in row where ch != "." {
                        XCTAssertNotNil(KikiSprites.palette[ch], "\(name)[\(i)] unknown palette char '\(ch)'")
                    }
                }
                XCTAssertNotNil(PixelArt.image(from: frame, palette: KikiSprites.palette), "\(name)[\(i)] failed to render")
            }
        }
    }

    func testClaudeThinkingFramesAreDistinct() {
        let frames = KikiSprites.claudeThinking.map { $0.joined(separator: "\n") }
        XCTAssertEqual(Set(frames).count, frames.count, "duplicate frames make the animation look frozen")
    }

    func testSleepFramesAreStandingAndDistinct() {
        let frames = KikiSprites.sleep.map { $0.joined(separator: "\n") }
        XCTAssertEqual(Set(frames).count, frames.count, "breathing loop needs distinct frames")
        // Standing pose: shoes reach row 22; the sitting pose ends in blank rows there.
        XCTAssertTrue(KikiSprites.sleep[0][22].contains("P"), "expected standing shoes on row 22")
    }

    func testZzzBadgeRenders() {
        XCTAssertNotNil(PixelArt.image(from: KikiSprites.zzz, palette: KikiSprites.palette))
    }
}
