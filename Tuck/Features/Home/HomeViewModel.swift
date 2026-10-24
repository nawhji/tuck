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
    var isSimulating = false
    var messages: [ChatMessage] = []
    var draft = ""
    var selectedProductID: Product.ID?
    var sheetDetent: SheetDetent = .collapsed
    private(set) var isResponding = false

    private let client = ClaudeClient()
    private var responseTask: Task<Void, Never>?

    var sheetTitle: String { "\(userName)’s Room" }
    var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding }

    // MARK: - Actions (미구현)

    func startScan() { /* TODO: Room Scan 화면으로 이동 */ }
    func openProfile() { /* TODO: Profile 화면으로 이동 */ }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }
        draft = ""
        messages.append(ChatMessage(role: .user, text: text))
        let reply = ChatMessage(role: .assistant, text: "")
        messages.append(reply)

        let turns = messages.dropLast().map { ClaudeClient.Turn(role: $0.role == .user ? "user" : "assistant", text: $0.text) }
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

    private func append(_ text: String, to id: ChatMessage.ID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text += text
    }

    private func replyIsEmpty(_ id: ChatMessage.ID) -> Bool {
        messages.first(where: { $0.id == id })?.text.isEmpty ?? true
    }

    func attachImage() { /* TODO: 이미지 입력 */ }
    func share(_ product: Product) { /* TODO: 공유 */ }
    func toggleSelection(of product: Product) { /* TODO: 선택 → 시뮬레이션 */ }
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
        Product(id: "chair-1", name: "Really Cool Chair", price: "$ 495.15",
                imageURL: nil, brandLogoURL: nil, tags: ["#freeshipping", "#freeshipping", "#freeshipping", "#freeshipping"]),
        Product(id: "chair-2", name: "Really Cool Chair", price: "$ 495.15",
                imageURL: nil, brandLogoURL: nil, tags: ["#freeshipping", "#freeshipping", "#freeshipping", "#freeshipping"]),
    ]
}

extension ChatMessage {
    static let sampleUser = ChatMessage(
        role: .user,
        text: "I want to add a knee-height cabinet next to my vanity. I’d prefer something with a modern, minimalist design."
    )
    static let sampleAnswer = ChatMessage(
        role: .assistant,
        text: "Sure. Here is a Typescript code block for your Analog Clock project. It is built using React, "
            + "and uses the local time for London, England as standard. Let me know if you would like to make any refinements to the code.",
        products: Product.samples
    )
}
#endif
