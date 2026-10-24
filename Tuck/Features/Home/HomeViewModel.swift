import Foundation
import Observation

enum SheetDetent {
    case collapsed
    case expanded
}

/// Home 화면이 그리는 상태. 채팅은 Claude API에 연결되어 있고, 스캔·시뮬레이션은 아직 연결되지 않았다.
@Observable
final class HomeViewModel {
    /// 로그인이 없는 서비스라 사용자 정보는 고정값이다.
    let userName = "Harper"
    let userInitial = "H"

    var hasScannedSpace = false
    var isPresentingScan = false
    var isSimulating = false
    var messages: [ChatMessage] = []
    var draft = ""
    var selectedProductID: Product.ID?
    var sheetDetent: SheetDetent = .collapsed
    private(set) var isResponding = false

    private let client = ClaudeClient()
    private let catalog = try? ProductCatalog()
    private var responseTask: Task<Void, Never>?

    var sheetTitle: String { "\(userName)’s Room" }
    var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding }

    // MARK: - Actions (미구현)

    func startScan() { isPresentingScan = true }

    /// Demo destination is deliberately independent of RoomPlan success or support.
    func finishDemoScan() {
        hasScannedSpace = true
        sheetDetent = .collapsed
        isPresentingScan = false
    }
    func openProfile() { /* TODO: Profile 화면으로 이동 */ }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }
        draft = ""
        messages.append(ChatMessage(role: .user, text: text))
        let reply = ChatMessage(role: .assistant, text: "")
        messages.append(reply)

        let turns = messages.dropLast().map { ClaudeClient.Turn(role: $0.role == .user ? "user" : "assistant", text: $0.rawText) }
        isResponding = true
        responseTask = Task { [client] in
            do {
                for try await chunk in client.stream(Array(turns)) {
                    append(chunk, to: reply.id)
                }
            } catch is CancellationError {
            } catch {
                append(replyIsEmpty(reply.id) ? error.localizedDescription : "\n\n⚠️ \(error.localizedDescription)", to: reply.id)
            }
            isResponding = false
        }
    }

    /// 원문을 이어 붙이고 본문·카드 덩어리로 다시 나눈다. 카드는 JSON 블록이 닫힌 뒤에 나타난다.
    private func append(_ text: String, to id: ChatMessage.ID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].rawText += text
        messages[index].blocks = blocks(from: messages[index].rawText)
    }

    private func blocks(from raw: String) -> [ChatMessage.Block] {
        ReplyParser.parse(raw).compactMap { segment in
            switch segment {
            case .text(let text):
                return .text(text)
            case .products(let picks):
                // 카탈로그에 없는 id는 버린다.
                let products = catalog.map { catalog in picks.compactMap { Product(pick: $0, catalog: catalog) } } ?? []
                return products.isEmpty ? nil : .products(products)
            }
        }
    }

    private func replyIsEmpty(_ id: ChatMessage.ID) -> Bool {
        messages.first(where: { $0.id == id })?.rawText.isEmpty ?? true
    }

    func attachImage() { /* TODO: 이미지 입력 */ }
    /// 카드를 누르면 선택, 선택된 카드를 다시 누르면 해제. (시뮬레이션 연동은 TODO)
    func toggleSelection(of product: Product) {
        selectedProductID = selectedProductID == product.id ? nil : product.id
    }
}

#if DEBUG
extension HomeViewModel {
    enum PreviewState {
        case empty, scanned, asking, answer, simulation
    }

    static func preview(_ state: PreviewState) -> HomeViewModel {
        let model = HomeViewModel()
        switch state {
        case .empty:
            model.messages = [.sampleUser]
        case .scanned:
            model.hasScannedSpace = true
            model.messages = [.sampleUser]
        case .asking:
            model.hasScannedSpace = true
            model.sheetDetent = .expanded
            model.draft = "I’d like to get a modern carpet besides my bed."
        case .answer:
            model.hasScannedSpace = true
            model.sheetDetent = .expanded
            model.messages = [.sampleAnswer]
            model.selectedProductID = Product.samples[0].id
        case .simulation:
            model.hasScannedSpace = true
            model.isSimulating = true
        }
        return model
    }
}

extension Product {
    static let samples = [
        Product(id: "chair-1", name: "Really Cool Chair", price: "$ 495.15", brand: "IKEA",
                keywords: ["freeshipping", "modern", "walnut", "velvet"], imageURL: nil, sourceURL: URL(string: "https://www.ikea.com")),
        Product(id: "chair-2", name: "Really Cool Chair", price: "$ 495.15", brand: "IKEA",
                keywords: ["freeshipping", "modern"], imageURL: nil, sourceURL: nil),
    ]
}

extension ChatMessage {
    static let sampleUser = ChatMessage(
        role: .user,
        text: "I want to add a knee-height cabinet next to my vanity. I’d prefer something with a modern, minimalist design."
    )
    static let sampleAnswer = ChatMessage(
        role: .assistant,
        text: "",
        blocks: [
            .text("#### Two options\nFor a modern look, the first one is **compact** and *easy to place* next to a vanity."),
            .products([Product.samples[0]]),
            .text("If you want something with more storage, the second one is a better fit."),
            .products([Product.samples[1]]),
        ]
    )
}
#endif
