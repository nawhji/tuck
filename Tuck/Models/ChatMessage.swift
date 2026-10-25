import Foundation
import CryptoKit

/// One item in the chat thread. Agent responses are populated as they stream.
struct ChatMessage: Identifiable, Equatable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    /// One segment of an agent response. Text and furniture cards may alternate.
    enum Block: Equatable {
        case text(String)
        case products([Product])
        /// Order confirmation card appended by the app after streaming ends. Its status follows the server order state.
        case checkout(CheckoutCard)
    }

    let id: UUID
    let role: Role
    /// User message text.
    var text: String
    /// Agent response (JSON blocks have been converted into cards).
    var blocks: [Block]
    /// Segment appended by the app after the response. It survives rebuilding `blocks` during streaming.
    var trailing: [Block] = []
    /// Raw model response, used when sending the conversation history again.
    var rawText: String

    init(id: UUID = UUID(), role: Role, text: String, blocks: [Block] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.blocks = blocks
        self.rawText = text
    }
}

/// Values shown on a recommended furniture card. The catalog provides name, price, brand, image, and link; the AI provides keywords.
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
    /// Builds card values from a catalog row and AI pick. Returns nil if the ID is not in the catalog.
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
