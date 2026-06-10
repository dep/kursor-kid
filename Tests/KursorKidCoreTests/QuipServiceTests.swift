import XCTest
@testable import KursorKidCore

/// URLProtocol mock: queue of (status, body) responses, or an error.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [(status: Int, body: String)] = []
    nonisolated(unsafe) static var error: Error?
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []
    nonisolated(unsafe) static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.capturedRequests.append(request)
        let error = Self.error
        let response = Self.responses.isEmpty ? nil : Self.responses.removeFirst()
        Self.lock.unlock()

        if let error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let (status, body) = response ?? (200, "{}")
        let httpResponse = HTTPURLResponse(
            url: request.url!, statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: status == 429 ? ["retry-after": "0"] : nil
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body.data(using: .utf8)!)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        lock.lock()
        responses = []
        error = nil
        capturedRequests = []
        lock.unlock()
    }
}

final class QuipServiceTests: XCTestCase {
    private var service: QuipService!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        service = QuipService(
            apiKeyProvider: { "sk-test-key" },
            session: URLSession(configuration: config),
            retryDelay: { _ in } // no sleeping in tests
        )
    }

    private func successBody(_ text: String) -> String {
        #"{"content":[{"type":"text","text":"\#(text)"}],"stop_reason":"end_turn"}"#
    }

    func testSuccessfulQuip() async {
        MockURLProtocol.responses = [(200, successBody("boop received, choom"))]
        let quip = await service.fetchQuip(trigger: .clicked, timeOfDay: "14:00", frontmostApp: nil)
        XCTAssertEqual(quip, "boop received, choom")
        let request = MockURLProtocol.capturedRequests.first
        XCTAssertEqual(request?.value(forHTTPHeaderField: "x-api-key"), "sk-test-key")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request?.url?.absoluteString, "https://api.anthropic.com/v1/messages")
    }

    func testMissingKeyFallsBackToCanned() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let keyless = QuipService(apiKeyProvider: { nil },
                                  session: URLSession(configuration: config),
                                  retryDelay: { _ in })
        let quip = await keyless.fetchQuip(trigger: .idle, timeOfDay: "09:00", frontmostApp: nil)
        XCTAssertTrue(CannedQuips.lines[.idle]!.contains(quip))
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty, "no network call without a key")
    }

    func testAuthErrorFallsBackToCanned() async {
        MockURLProtocol.responses = [(401, #"{"type":"error","error":{"type":"authentication_error"}}"#)]
        let quip = await service.fetchQuip(trigger: .clicked, timeOfDay: "14:00", frontmostApp: nil)
        XCTAssertTrue(CannedQuips.lines[.clicked]!.contains(quip))
    }

    func testRateLimitRetriesOnce() async {
        MockURLProtocol.responses = [
            (429, #"{"type":"error","error":{"type":"rate_limit_error"}}"#),
            (200, successBody("second try worked")),
        ]
        let quip = await service.fetchQuip(trigger: .idle, timeOfDay: "14:00", frontmostApp: nil)
        XCTAssertEqual(quip, "second try worked")
        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 2)
    }

    func testNetworkErrorFallsBackToCanned() async {
        MockURLProtocol.error = URLError(.notConnectedToInternet)
        let quip = await service.fetchQuip(trigger: .timeOfDay, timeOfDay: "07:00", frontmostApp: nil)
        XCTAssertTrue(CannedQuips.lines[.timeOfDay]!.contains(quip))
    }

    func testMalformedJSONFallsBackToCanned() async {
        MockURLProtocol.responses = [(200, "not even json")]
        let quip = await service.fetchQuip(trigger: .appSwitch, timeOfDay: "14:00", frontmostApp: "Safari")
        XCTAssertTrue(CannedQuips.lines[.appSwitch]!.contains(quip))
    }

    func testRecentQuipsAreTracked() async {
        MockURLProtocol.responses = [
            (200, successBody("line one")),
            (200, successBody("line two")),
        ]
        _ = await service.fetchQuip(trigger: .idle, timeOfDay: "14:00", frontmostApp: nil)
        _ = await service.fetchQuip(trigger: .idle, timeOfDay: "14:05", frontmostApp: nil)
        let secondRequest = MockURLProtocol.capturedRequests[1]
        let body = secondRequest.httpBody ?? secondRequest.bodyStreamData() ?? Data()
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("line one"), "second request should carry first quip in recent list")
    }
}

private extension URLRequest {
    /// URLSession turns httpBody into a stream by the time URLProtocol sees it.
    func bodyStreamData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
