import Foundation

/// Reads `data/TUCK_Product_Catalog.csv` and formats it for the AI system prompt.
/// This is the source of truth for furniture recommendations.
struct ProductCatalog {
    static let fileName = "TUCK_Product_Catalog"

    /// Include only columns the AI needs; omit image URLs and other fields to save tokens.
    private static let promptColumns = [
        "id", "name", "brand", "category", "description", "price_cents", "currency", "availability",
        "width_in", "depth_in", "height_in", "seat_height_in", "color_name", "color_family",
        "style_tags", "upholstery_material", "frame_material",
    ]

    let rows: [[String: String]]

    var ids: Set<String> { Set(rows.compactMap { $0["id"] }) }

    func row(id: String) -> [String: String]? { rows.first { $0["id"] == id } }

    /// Decodes columns stored as arrays such as `["a","b"]`.
    static func list(_ value: String?) -> [String] {
        guard let data = value?.data(using: .utf8),
              let items = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return items
    }

    init(url: URL? = Bundle.main.url(forResource: Self.fileName, withExtension: "csv")) throws {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        rows = Self.parse(try String(contentsOf: url, encoding: .utf8))
    }

    /// Encodes one product per JSON Lines row, omitting empty or `null` fields.
    var promptText: String {
        rows.map { row in
            let fields = Self.promptColumns.compactMap { column -> String? in
                guard let value = row[column], !value.isEmpty, value != "null", value != "[]" else { return nil }
                return "\(Self.quote(column)):\(Self.quote(value))"
            }
            return "{" + fields.joined(separator: ",") + "}"
        }.joined(separator: "\n")
    }

    private static func quote(_ text: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [text], options: [.fragmentsAllowed])
        let array = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }

    /// Minimal CSV parser that handles quoted fields and line breaks.
    private static func parse(_ text: String) -> [[String: String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending = iterator.next()

        while let char = pending {
            pending = iterator.next()
            if inQuotes {
                if char == "\"" {
                    if pending == "\"" { field.append("\""); pending = iterator.next() } else { inQuotes = false }
                } else {
                    field.append(char)
                }
            } else {
                switch char {
                case "\"": inQuotes = true
                case ",": record.append(field); field = ""
                case "\n", "\r\n":
                    record.append(field); field = ""
                    records.append(record); record = []
                default: field.append(char)
                }
            }
        }
        if !field.isEmpty || !record.isEmpty { record.append(field); records.append(record) }

        guard let header = records.first else { return [] }
        return records.dropFirst().filter { $0.count == header.count }.map { Dictionary(uniqueKeysWithValues: zip(header, $0)) }
    }
}

/// A furniture item selected by the AI. The UI looks up its values in the catalog by `id`.
struct ProductPick: Equatable, Decodable {
    let id: String
    let keywords: [String]

    init(id: String, keywords: [String] = []) {
        self.id = id
        self.keywords = keywords
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        keywords = (try? container.decode([String].self, forKey: .keywords)) ?? []
    }

    private enum CodingKeys: String, CodingKey { case id, keywords }
}

/// One segment of a response. Text, furniture picks, and purchase intents may alternate.
enum ReplySegment: Equatable {
    case text(String)
    case products([ProductPick])
    case buy(BuyIntent)
}

/// Splits the raw response into text, furniture-pick, and purchase-intent segments.
/// The model inserts a ```tuck-products block (`{"products":[{"id","keywords"}]}`) where it mentions furniture,
/// and a ```tuck-buy block (`{"quantity":1,"budget_usd":200}`) when the user wants to buy placed furniture.
enum ReplyParser {
    static let fence = "```tuck-products"
    static let buyFence = "```tuck-buy"
    static let maxProducts = 5

    static func parse(_ raw: String) -> [ReplySegment] {
        var segments: [ReplySegment] = []
        var seen = Set<String>()
        var rest = Substring(raw)

        func appendText(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { segments.append(.text(trimmed)) }
        }

        while let (start, isBuy) = earliestFence(in: rest) {
            appendText(String(rest[..<start.lowerBound]))
            let body = rest[start.upperBound...]
            // During streaming, stop if the block has not closed yet.
            guard let end = body.range(of: "```") else { return segments }
            let json = String(body[..<end.lowerBound])
            if isBuy {
                // Accept only one purchase intent.
                if let intent = decode(BuyIntent.self, from: json),
                   !segments.contains(where: { if case .buy = $0 { true } else { false } }) {
                    segments.append(.buy(intent))
                }
            } else {
                let picks = picks(in: json).filter { seen.insert($0.id).inserted && seen.count <= maxProducts }
                if !picks.isEmpty { segments.append(.products(picks)) }
            }
            rest = body[end.upperBound...]
        }
        appendText(visibleText(String(rest)))
        return segments
    }

    /// Returns the value from a closed purchase block in the response, if present.
    static func buyIntent(in raw: String) -> BuyIntent? {
        for case let .buy(intent) in parse(raw) { return intent }
        return nil
    }

    private static func earliestFence(in text: Substring) -> (range: Range<Substring.Index>, isBuy: Bool)? {
        switch (text.range(of: fence), text.range(of: buyFence)) {
        case let (products?, buy?): products.lowerBound <= buy.lowerBound ? (products, false) : (buy, true)
        case let (products?, nil): (products, false)
        case let (nil, buy?): (buy, true)
        case (nil, nil): nil
        }
    }

    /// Hides an incomplete trailing fence (such as "`" or "```tuck-pro") while streaming.
    private static func visibleText(_ raw: String) -> String {
        let longest = [fence, buyFence].map { fence in
            stride(from: min(fence.count - 1, raw.count), through: 1, by: -1)
                .first { fence.hasPrefix(String(raw.suffix($0))) } ?? 0
        }.max() ?? 0
        return String(raw.dropLast(longest))
    }

    private struct Payload: Decodable { let products: [ProductPick] }

    private static func decode<T: Decodable>(_ type: T.Type, from json: String) -> T? {
        json.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func picks(in json: String) -> [ProductPick] {
        decode(Payload.self, from: json)?.products ?? []
    }
}
