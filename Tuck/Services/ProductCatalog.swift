import Foundation

/// `data/TUCK_Product_Catalog - 시트1.csv`를 읽어 AI 시스템 프롬프트용 텍스트로 만든다.
/// 가구 추천의 유일한 기준 dataset이다.
struct ProductCatalog {
    static let fileName = "TUCK_Product_Catalog - 시트1"

    /// AI가 판단하는 데 필요한 열만 싣는다 (이미지 URL 등은 제외해 토큰을 아낀다).
    private static let promptColumns = [
        "id", "name", "brand", "category", "description", "price_cents", "currency", "availability",
        "width_in", "depth_in", "height_in", "seat_height_in", "color_name", "color_family",
        "style_tags", "upholstery_material", "frame_material",
    ]

    let rows: [[String: String]]

    var ids: Set<String> { Set(rows.compactMap { $0["id"] }) }

    func row(id: String) -> [String: String]? { rows.first { $0["id"] == id } }

    /// `["a","b"]` 형태로 저장된 열을 배열로 푼다.
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

    /// 한 줄에 제품 하나인 JSON Lines. 값이 비었거나 "null"인 열은 생략한다.
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

    /// 따옴표·줄바꿈이 들어간 필드를 처리하는 최소 CSV 파서.
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

/// AI가 고른 가구 한 개. 화면 값은 `id`로 카탈로그에서 가져온다.
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

/// 응답을 구성하는 한 덩어리. 본문과 가구 pick이 번갈아 나올 수 있다.
enum ReplySegment: Equatable {
    case text(String)
    case products([ProductPick])
}

/// 응답 원문을 본문과 가구 pick 덩어리로 나눈다.
/// 모델은 가구를 언급한 자리에 ```tuck-products 블록(`{"products":[{"id","keywords"}]}`)을 넣는다.
enum ReplyParser {
    static let fence = "```tuck-products"
    static let maxProducts = 5

    static func parse(_ raw: String) -> [ReplySegment] {
        var segments: [ReplySegment] = []
        var seen = Set<String>()
        var rest = Substring(raw)

        func appendText(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { segments.append(.text(trimmed)) }
        }

        while let start = rest.range(of: fence) {
            appendText(String(rest[..<start.lowerBound]))
            let body = rest[start.upperBound...]
            // 스트리밍 중: 블록이 아직 닫히지 않았으면 여기서 멈춘다.
            guard let end = body.range(of: "```") else { return segments }
            let picks = picks(in: String(body[..<end.lowerBound]))
                .filter { seen.insert($0.id).inserted && seen.count <= maxProducts }
            if !picks.isEmpty { segments.append(.products(picks)) }
            rest = body[end.upperBound...]
        }
        appendText(visibleText(String(rest)))
        return segments
    }

    /// 스트리밍 중 끝에 걸린 펜스 조각("`", "```tuck-pro" 등)은 화면에 내보내지 않는다.
    private static func visibleText(_ raw: String) -> String {
        for length in stride(from: min(fence.count - 1, raw.count), through: 1, by: -1)
        where fence.hasPrefix(String(raw.suffix(length))) {
            return String(raw.dropLast(length))
        }
        return raw
    }

    private struct Payload: Decodable { let products: [ProductPick] }

    private static func picks(in json: String) -> [ProductPick] {
        guard let data = json.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return [] }
        return payload.products
    }
}
