import Foundation

/// Anthropic Messages API 스트리밍 클라이언트.
struct ClaudeClient {
    enum ClientError: LocalizedError {
        case http(status: Int, message: String)
        case stream(String)

        var errorDescription: String? {
            switch self {
            case let .http(status, message): "Claude API error (\(status)): \(message)"
            case let .stream(message): "Claude API stream error: \(message)"
            }
        }
    }

    struct Turn {
        let role: String
        let text: String
    }

    var apiKey = Secrets.anthropicAPIKey
    var model = "claude-sonnet-5-5"
    var maxTokens = 1024
    var systemPrompt = """
        You are Tuck, a friendly interior-design assistant inside a home-furnishing app. \
        Help the user choose furniture and decor for their room. Be concise and practical, \
        mention style, size and placement, and ask a short follow-up question when you need more detail. \
        Reply in the language the user writes in.
        """

    /// 응답 텍스트 조각을 도착하는 대로 흘려보낸다.
    func stream(_ turns: [Turn]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(turns)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw ClientError.http(status: http.statusCode, message: Self.errorMessage(in: body))
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:"),
                              let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces).data(using: .utf8),
                              let event = try? JSONDecoder().decode(StreamEvent.self, from: data)
                        else { continue }
                        switch event.type {
                        case "content_block_delta":
                            if let text = event.delta?.text { continuation.yield(text) }
                        case "error":
                            throw ClientError.stream(event.error?.message ?? "unknown")
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeRequest(_ turns: [Turn]) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let body = RequestBody(
            model: model,
            maxTokens: maxTokens,
            system: systemPrompt,
            stream: true,
            messages: turns.map { .init(role: $0.role, content: $0.text) }
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private static func errorMessage(in body: String) -> String {
        guard let data = body.data(using: .utf8),
              let event = try? JSONDecoder().decode(StreamEvent.self, from: data),
              let message = event.error?.message
        else { return body }
        return message
    }
}

private struct RequestBody: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let maxTokens: Int
    let system: String
    let stream: Bool
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model, system, stream, messages
        case maxTokens = "max_tokens"
    }
}

private struct StreamEvent: Decodable {
    struct Delta: Decodable { let text: String? }
    struct APIError: Decodable { let message: String }

    let type: String?
    let delta: Delta?
    let error: APIError?
}
