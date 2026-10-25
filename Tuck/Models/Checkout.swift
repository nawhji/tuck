import Foundation

/// 주문 API(`backend/`)의 응답 모델. 금액은 전부 서버가 계산한 센트 값이며 앱은 표시만 한다.
struct OrderAddress: Codable, Equatable {
    var line1: String
    var line2: String?
    var city: String
    var state: String
    var postalCode: String
    var country: String

    var oneLine: String { "\(line1), \(city), \(state) \(postalCode)" }
}

struct QuotedProduct: Codable, Equatable {
    let id: String
    let name: String
    let brand: String
    let imageUrl: String?
    let category: String
}

struct CardSummary: Codable, Equatable {
    let brand: String
    let last4: String

    var label: String { "\(brand.capitalized) •••• \(last4)" }
}

/// 서버가 카탈로그·배송지로 계산한 견적. `hash`는 사용자가 승인한 견적이 바뀌었는지 서버가 확인하는 값이다.
struct OrderQuote: Codable, Equatable {
    let product: QuotedProduct
    let quantity: Int
    let unitCents: Int
    let subtotalCents: Int
    let shippingCents: Int
    let taxCents: Int
    let totalCents: Int
    let currency: String
    let address: OrderAddress
    let budgetCents: Int?
    let hash: String

    func format(_ cents: Int) -> String { Product.formatPrice(cents: cents, currency: currency.uppercased()) }
}

struct QuoteAlternative: Decodable, Equatable {
    let product: QuotedProduct
    let totalCents: Int
    let fitsPlacement: Bool
    let styleTags: [String]
}

enum QuoteStatus: String, Decodable {
    case ok
    case overBudget = "over_budget"
    case unavailable
}

struct QuoteResponse: Decodable {
    let status: QuoteStatus
    let orderId: String?
    let quote: OrderQuote?
    let alternatives: [QuoteAlternative]
    let paymentMethod: CardSummary?

    private enum CodingKeys: String, CodingKey { case status, orderId, quote, alternatives, paymentMethod }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(QuoteStatus.self, forKey: .status)
        orderId = try container.decodeIfPresent(String.self, forKey: .orderId)
        // 품절 응답의 quote에는 금액·해시가 없으므로 디코딩에 실패하면 nil로 둔다.
        quote = try? container.decodeIfPresent(OrderQuote.self, forKey: .quote)
        alternatives = (try? container.decode([QuoteAlternative].self, forKey: .alternatives)) ?? []
        paymentMethod = try? container.decodeIfPresent(CardSummary.self, forKey: .paymentMethod)
    }
}

enum OrderStatus: String, Decodable {
    case quoted
    case awaitingPayment = "awaiting_payment"
    case paid
    case paymentFailed = "payment_failed"
    case canceled
    case needsReview = "needs_review"
    case unknown

    init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

/// PaymentSheet을 띄우는 데 필요한 값. 카드 정보는 앱도 서버도 다루지 않고 Stripe로 직접 간다.
struct PaymentParams: Decodable, Equatable {
    let clientSecret: String
    let customerId: String
    let ephemeralKeySecret: String
}

struct OrderSnapshot: Decodable {
    struct Failure: Decodable { let message: String }

    let orderId: String
    let status: OrderStatus
    let quote: OrderQuote
    let failure: Failure?
    let paymentMethod: CardSummary?
    let payment: PaymentParams?
}

/// 채팅 안 주문 확인 카드의 값. 상태는 서버 주문 상태(웹훅 기준)를 따라 바뀐다.
struct CheckoutCard: Equatable {
    enum State: Equatable {
        case ready
        case processing
        case confirming
        /// 결제는 끝났지만 서버 웹훅 확인이 늦어지고 있다. [Check status]로 다시 확인한다.
        case pending
        case paid
        case failed(String)
        case canceled
    }

    let orderID: String
    var quote: OrderQuote
    var paymentMethod: CardSummary?
    var state: State = .ready
    /// 가격이 바뀌었을 때 등, 카드 아래에 보여주는 안내.
    var notice: String?
}

/// 에이전트가 사용자의 구매 의사를 전달하는 값. 상품 id는 앱이 카탈로그와 서버 가격으로 다시 검증한다.
struct BuyIntent: Equatable, Decodable {
    /// 사용자가 지칭했거나 조건에 맞아 모델이 카탈로그에서 고른 상품. 없으면 방에 놓인 상품을 쓴다.
    let productID: String?
    let quantity: Int
    let budgetCents: Int?

    init(productID: String? = nil, quantity: Int = 1, budgetCents: Int? = nil) {
        self.productID = productID
        self.quantity = quantity
        self.budgetCents = budgetCents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        productID = try? container.decode(String.self, forKey: .productID)
        quantity = (try? container.decode(Int.self, forKey: .quantity)) ?? 1
        budgetCents = (try? container.decode(Double.self, forKey: .budgetUSD)).map { Int(($0 * 100).rounded()) }
    }

    private enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case quantity
        case budgetUSD = "budget_usd"
    }
}

/// 사용자가 실수로 입력한 카드 번호는 모델과 대화 이력에 남기지 않는다. (Luhn 검사를 통과하는 13~19자리)
enum CardNumberRedactor {
    static func redact(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?<!\d)\d(?:[ -]?\d){12,18}(?!\d)"#) else { return text }
        var result = text
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range).reversed() {
            guard let swiftRange = Range(match.range, in: result) else { continue }
            let digits = result[swiftRange].filter(\.isNumber)
            if isLuhnValid(digits) { result.replaceSubrange(swiftRange, with: "[card number removed]") }
        }
        return result
    }

    private static func isLuhnValid(_ digits: String) -> Bool {
        var sum = 0
        for (index, char) in digits.reversed().enumerated() {
            guard var value = char.wholeNumberValue else { return false }
            if index % 2 == 1 {
                value *= 2
                if value > 9 { value -= 9 }
            }
            sum += value
        }
        return sum % 10 == 0
    }
}
