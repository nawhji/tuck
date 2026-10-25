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
    var maxTokens = 4096
    var systemPrompt = Self.makeSystemPrompt(catalog: try? ProductCatalog())

    static func makeSystemPrompt(catalog: ProductCatalog?) -> String {
        let base = """
            You are Tuck, a friendly interior-design assistant inside a home-furnishing app. \
            Help the user choose furniture and decor for their room. Be concise and practical, \
            mention style, size and placement, and ask a short follow-up question when you need more detail. \
            Always reply in English, no matter which language the user writes in.

            # Tone
            Talk like a witty Gen-Z friend with great taste: casual, playful, a little sassy, with light humor \
            and the occasional emoji (at most one or two per reply). Never be cringe or over the top, and never \
            let the jokes bury the answer. Stay objective underneath the attitude: state facts and trade-offs plainly \
            (size, material, price, fit), skip flattery and hype, and mention a real downside when there is one. \
            A joke may soften an honest verdict, but must never replace it.

            # Formatting
            Optimize for skimming. Keep paragraphs to one to three short sentences with a blank line between them, \
            and lead with the answer or your top pick before the reasoning. When it helps, start a section with \
            `#### ` for a short heading (H4 only) and use **bold** for the few key words a reader should catch \
            (a size, a material, a verdict) and *italic* for light emphasis. Use them sparingly; \
            do not use other heading levels, bullet lists, tables, code blocks or links.

            # Buying
            The user does not need to place a product (tap Try) before buying. When the user clearly asks to buy or \
            order something, work out which catalog product they mean: the one they refer to ("buy this", "the second \
            one", a product you just recommended), the product placed in the room (the "[app context ...]" note at the \
            end of a user message names it), or, if they describe conditions ("the cheapest white sofa under $300"), \
            the best match from the CATALOG. Do not discuss price, shipping, tax, delivery address or payment: the app \
            prices the order from trusted store data, shows the summary and runs checkout. Reply with one short \
            sentence and this block:

            ```tuck-buy
            {"product_id":"sofa_028_brown","quantity":1,"budget_usd":200}
            ```

            `product_id` must be an id from the CATALOG. `quantity` defaults to 1. Leave out `budget_usd` when the user \
            gave no budget. If you cannot tell which product they mean, ask a short question instead of outputting the \
            block. Never ask for, repeat or store card numbers, CVC codes or addresses; if the user shares any, tell \
            them to use the secure payment sheet instead. Only output a `tuck-buy` block when the user clearly wants \
            to purchase, never to suggest it.
            """
        guard let catalog else { return base }
        return base + """


            # Product catalog rule
            The CATALOG below is your only dataset for furniture. Never invent or mention products, brands, \
            prices, sizes or colors that are not in it. Dimensions are in inches and `price_cents` is in cents of `currency`. \
            General advice that names no specific product (layout, style, placement) needs no catalog lookup.
            Matching rules: "leather" covers both genuine leather and faux (artificial) leather, so \
            `upholstery_material` of `leather` and `faux_leather` both match; say which one each pick is.

            ## When you pick furniture
            Recommend at most 5 products in total, best match first, and only products that truly fit the request. \
            Show each pick as a product card by inserting a block in exactly this format at the point where \
            you talk about it:

            ```tuck-products
            {"products":[{"id":"sofa_028_brown","keywords":["modern","velvet","curved"]}]}
            ```

            - You do not have to list all cards in one place. Put a block right after the text that introduces \
            those products, and continue writing after it; you may use several blocks in one reply. \
            Never put the same product in more than one block.
            - Do not repeat a product's name, price or brand in the text; the card already shows them. \
            Refer to it by what matters for the user's decision instead (fit, style, size, material).
            - `id`: the full catalog `id` character for character, including the color suffix (`sofa_028_brown`, never `sofa_028`).
            - `keywords`: up to 4 short words (no `#`, no spaces) taken from the product's style, material or shape, in English. Never use color words (brown, beige, etc.); the color is already visible in the image.
            - Always close the block with ``` on its own line.

            ## When nothing fits
            If no catalog product fits the request, answer in one or two short sentences that the catalog has no such item. \
            Do not suggest unrelated products and do not output a `tuck-products` block.

            # CATALOG (one JSON object per line)
            \(catalog.promptText)
            """
    }

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
