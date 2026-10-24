import Foundation

/// 채팅 스레드의 한 항목. 에이전트 응답이 스트리밍되며 채워진다.
struct ChatMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var text: String
    var products: [Product]

    init(id: UUID = UUID(), role: Role, text: String, products: [Product] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.products = products
    }
}

/// 추천 가구 카드에 표시되는 값. 이미지·브랜드 로고는 응답이 도착하면 채워진다.
struct Product: Identifiable, Equatable {
    let id: String
    var name: String
    var price: String
    var imageURL: URL?
    var brandLogoURL: URL?
    var tags: [String]
}
