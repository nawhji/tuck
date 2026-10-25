import Foundation

/// Response models for the order API (`backend/`). The server calculates all amounts in cents; the app only displays them.
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

/// Quote calculated by the server from the catalog and shipping address. The server uses `hash` to detect changes to an approved quote.
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
        // Out-of-stock responses have no amount or hash; use nil if quote decoding fails.
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

/// Values required to present PaymentSheet. Card details go directly to Stripe and are never handled by the app or server.
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

/// Values for the order confirmation card in chat. Status follows the server order state, based on webhooks.
struct CheckoutCard: Equatable {
    enum State: Equatable {
        case ready
        case processing
        case confirming
        /// Payment completed, but the server webhook is delayed. Check again with [Check status].
        case pending
        case paid
        case failed(String)
        case canceled
    }

    let orderID: String
    var quote: OrderQuote
    var paymentMethod: CardSummary?
    var state: State = .ready
    /// Message displayed below the card, for example when the price changes.
    var notice: String?
}

/// Purchase intent reported by the agent. The app validates the product ID against the catalog and server price.
struct BuyIntent: Equatable, Decodable {
    /// Product named by the user or selected by the model from the catalog. If absent, use the product placed in the room.
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

/// Card numbers entered by mistake are removed before they reach the model or conversation history (13–19 digits that pass the Luhn check).
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
