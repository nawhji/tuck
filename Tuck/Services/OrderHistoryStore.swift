import Foundation
import Observation

/// 결제가 확정된(paid) 주문 기록. 기기에만 저장하며, 같은 주문은 한 번만 기록한다.
struct OrderRecord: Codable, Identifiable, Equatable {
    let id: String
    let productName: String
    let brand: String
    let imageURL: String?
    let quantity: Int
    let totalCents: Int
    let currency: String
    let address: String
    let card: String?
    let date: Date

    var total: String { Product.formatPrice(cents: totalCents, currency: currency.uppercased()) }
}

@Observable
final class OrderHistoryStore {
    private(set) var orders: [OrderRecord] = []
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("order-history.json")
        if let data = try? Data(contentsOf: self.fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            orders = (try? decoder.decode([OrderRecord].self, from: data)) ?? []
        }
    }

    func record(orderID: String, quote: OrderQuote, card: CardSummary?, date: Date = Date()) {
        guard !orders.contains(where: { $0.id == orderID }) else { return }
        let record = OrderRecord(
            id: orderID, productName: quote.product.name, brand: quote.product.brand, imageURL: quote.product.imageUrl,
            quantity: quote.quantity, totalCents: quote.totalCents, currency: quote.currency,
            address: quote.address.oneLine, card: card?.label, date: date)
        let updated = [record] + orders
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(updated).write(to: fileURL, options: .atomic)
            orders = updated
        } catch {}
    }
}
