import Foundation
import os

/// Talks to the Claude API (Haiku) for Kiki's one-liners. Never throws —
/// every failure path falls back to a canned line so the buddy keeps working
/// offline / keyless.
public final class QuipService {
    private let apiKeyProvider: () -> String?
    private let session: URLSession
    private let retryDelay: (TimeInterval) async -> Void
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let logger = Logger(subsystem: KursorKidInfo.bundleIdentifier, category: "quips")

    private var recentQuips: [String] = []

    public init(
        apiKeyProvider: @escaping () -> String?,
        session: URLSession = .shared,
        retryDelay: @escaping (TimeInterval) async -> Void = {
            try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
        }
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.session = session
        self.retryDelay = retryDelay
    }

    public func fetchQuip(
        trigger: QuipTrigger,
        timeOfDay: String,
        frontmostApp: String?
    ) async -> String {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            return canned(trigger)
        }

        let body = QuipPrompt.requestBody(
            trigger: trigger,
            timeOfDay: timeOfDay,
            frontmostApp: frontmostApp,
            recentQuips: recentQuips
        )
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return canned(trigger)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 15

        for attempt in 0..<2 {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { break }
                if http.statusCode == 200 {
                    if let text = parseText(from: data) {
                        remember(text)
                        return text
                    }
                    logger.error("quip response parse failure")
                    break
                }
                if attempt == 0, http.statusCode == 429 || http.statusCode >= 500 {
                    let retryAfter = Double(http.value(forHTTPHeaderField: "retry-after") ?? "") ?? 1
                    logger.info("quip API \(http.statusCode), retrying in \(retryAfter)s")
                    await retryDelay(min(retryAfter, 30))
                    continue
                }
                logger.error("quip API error \(http.statusCode)")
                break
            } catch {
                logger.error("quip network error: \(error.localizedDescription)")
                break
            }
        }
        return canned(trigger)
    }

    private func parseText(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String
        else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func remember(_ quip: String) {
        recentQuips.append(quip)
        if recentQuips.count > 5 { recentQuips.removeFirst() }
    }

    private func canned(_ trigger: QuipTrigger) -> String {
        CannedQuips.line(for: trigger)
    }
}
