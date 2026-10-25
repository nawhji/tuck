import Foundation
import CryptoKit

/// 채팅 스레드의 한 항목. 에이전트 응답이 스트리밍되며 채워진다.
struct ChatMessage: Identifiable, Equatable {
    enum Role: String, Codable {
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


/// Local room histories store raw text, never credentials or cached product prices.
/// Callers rebuild cards from the current catalog after loading.
struct RoomChatStore {
    private struct Record: Codable {
        let version: Int
        let roomKey: String
        let messages: [Entry]
    }
    private struct Entry: Codable {
        let id: UUID
        let role: ChatMessage.Role
        let rawText: String
        let interrupted: Bool
    }
    enum StoreError: LocalizedError {
        case unreadable, tooLarge
        var errorDescription: String? {
            switch self {
            case .unreadable: "This room's chat couldn't be loaded. Its saved file has been kept."
            case .tooLarge: "This room's chat is too large to save. Its previous file has been kept."
            }
        }
    }

    let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RoomChats", isDirectory: true)
    }

    func fileURL(for key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json")
    }

    func load(_ key: String) throws -> [ChatMessage] {
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 10_000_000 else { throw StoreError.unreadable }
            let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: url))
            guard record.version == 1, record.roomKey == key, record.messages.count <= 2000,
                  Set(record.messages.map(\.id)).count == record.messages.count else { throw StoreError.unreadable }
            return record.messages.filter { !$0.rawText.isEmpty }.map { entry in
                let suffix = entry.interrupted && entry.role == .assistant
                    ? "\n\n[This reply was interrupted. Send a follow-up to continue.]" : ""
                return ChatMessage(id: entry.id, role: entry.role, text: entry.rawText + suffix)
            }
        } catch { throw StoreError.unreadable }
    }

    func save(_ messages: [ChatMessage], key: String, streamingID: UUID? = nil) throws {
        // Refuse to replace an unreadable existing history, even across app launches.
        _ = try load(key)
        let entries = messages.filter { !$0.rawText.isEmpty }.map {
            Entry(id: $0.id, role: $0.role, rawText: $0.rawText, interrupted: $0.id == streamingID)
        }
        guard entries.count <= 2000 else { throw StoreError.tooLarge }
        guard Set(entries.map(\.id)).count == entries.count else { throw StoreError.unreadable }
        let data = try JSONEncoder().encode(Record(version: 1, roomKey: key, messages: entries))
        guard data.count <= 10_000_000 else { throw StoreError.tooLarge }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: key), options: .atomic)
    }
}
