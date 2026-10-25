import Foundation

/// 채팅 스레드의 한 항목. 에이전트 응답이 스트리밍되며 채워진다.
struct ChatMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
    }

    /// 에이전트 답변의 한 덩어리. 본문과 가구 카드가 번갈아 나올 수 있다.
    enum Block: Equatable {
        case text(String)
        case products([Product])
        /// 주문 확인 카드. 스트림이 끝난 뒤 앱이 붙이며, 상태는 서버 주문 상태를 따라 바뀐다.
        case checkout(CheckoutCard)
    }

    let id: UUID
    let role: Role
    /// 사용자 메시지 본문.
    var text: String
    /// 에이전트 답변 (JSON 블록은 카드로 바뀌어 있다).
    var blocks: [Block]
    /// 답변 뒤에 앱이 붙이는 덩어리. 스트리밍 중 `blocks`를 다시 만들어도 사라지지 않는다.
    var trailing: [Block] = []
    /// 모델이 보낸 원문. 대화 이력을 다시 보낼 때 쓴다.
    var rawText: String

    init(id: UUID = UUID(), role: Role, text: String, blocks: [Block] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.blocks = blocks
        self.rawText = text
    }
}

/// 추천 가구 카드에 표시되는 값. 이름·가격·브랜드·이미지·링크는 카탈로그, 키워드는 AI가 정한다.
struct Product: Identifiable, Equatable, Codable {
    let id: String
    var name: String
    var price: String
    var brand: String
    var keywords: [String]
    var imageURL: URL?
    var sourceURL: URL?
}

extension Product {
    /// 카탈로그 행과 AI pick으로 카드 값을 만든다. 카탈로그에 없는 id면 nil.
    init?(pick: ProductPick, catalog: ProductCatalog) {
        guard let row = catalog.row(id: pick.id) else { return nil }
        let keywords = pick.keywords.isEmpty
            ? ProductCatalog.list(row["style_tags"])
            : pick.keywords
        self.init(
            id: pick.id,
            name: row["name"] ?? pick.id,
            price: Self.formatPrice(cents: Int(row["price_cents"] ?? ""), currency: row["currency"] ?? "USD"),
            brand: row["brand"] ?? "",
            keywords: Array(keywords.prefix(4)),
            imageURL: URL(string: row["image_url"] ?? ""),
            sourceURL: URL(string: row["source_url"] ?? "")
        )
    }

    /// 495.15 USD → "$ 495.15"
    static func formatPrice(cents: Int?, currency: String) -> String {
        guard let cents else { return "" }
        let amount = String(format: "%.2f", Double(cents) / 100)
        return currency == "USD" ? "$ \(amount)" : "\(amount) \(currency)"
    }
}
