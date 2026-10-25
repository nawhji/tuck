import SwiftUI

/// In-chat order confirmation card. Shows product, quantity, total, shipping address, and payment method; [Order] opens the payment sheet.
/// All amounts come from the server quote, and test mode is always indicated.
struct CheckoutCardView: View {
    let card: CheckoutCard
    let onOrder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            testBadge
            product
            Divider()
            totals
            Divider()
            details
            orderButton
            if let notice = card.notice {
                Text(notice)
                    .font(.system(size: 13))
                    .foregroundStyle(Color("TuckBrown"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(.rect(cornerRadius: 30))
        .padding(.horizontal, 19)
        .accessibilityElement(children: .contain)
    }

    private var testBadge: some View {
        Text("TEST MODE · no real charge")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color("TuckBrown"))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color("TuckCream"), in: .capsule)
    }

    private var product: some View {
        HStack(spacing: 12) {
            RemoteImage(url: card.quote.product.imageUrl.flatMap(URL.init(string:)))
                .frame(width: 72, height: 72)
                .clipShape(.rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(card.quote.product.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.black)
                    .lineLimit(2)
                Text(card.quote.product.brand)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color("TuckBrown"))
                Text("Qty \(card.quote.quantity)")
                    .font(.system(size: 13))
                    .foregroundStyle(Color("GrayScale300"))
            }
        }
    }

    private var totals: some View {
        VStack(spacing: 6) {
            row("Subtotal", card.quote.format(card.quote.subtotalCents))
            row("Shipping", card.quote.shippingCents == 0 ? "Free" : card.quote.format(card.quote.shippingCents))
            row("Tax", card.quote.format(card.quote.taxCents))
            row("Total", card.quote.format(card.quote.totalCents), emphasized: true)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            detail("Ship to", card.quote.address.oneLine)
            detail("Payment", card.paymentMethod?.label ?? "Card (enter in the payment sheet)")
        }
    }

    private func row(_ title: String, _ value: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
        }
        .font(.system(size: emphasized ? 17 : 14, weight: emphasized ? .semibold : .regular))
        .foregroundStyle(emphasized ? .black : Color("GrayScale300"))
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color("GrayScale300"))
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.black)
        }
    }

    private var orderButton: some View {
        Button(action: onOrder) {
            HStack(spacing: 8) {
                if isBusy { ProgressView().tint(.white) }
                Text(buttonTitle)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(isEnabled ? Color("TuckBrown") : Color("GrayScale300"), in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var isBusy: Bool { card.state == .processing || card.state == .confirming }

    private var isEnabled: Bool {
        switch card.state {
        case .ready, .failed, .canceled, .pending: true
        case .processing, .confirming, .paid: false
        }
    }

    private var buttonTitle: String {
        switch card.state {
        case .ready: "Order"
        case .processing: "Opening payment…"
        case .confirming: "Confirming payment…"
        case .pending: "Check status"
        case .paid: "Ordered"
        case .failed: "Try again"
        case .canceled: "Order again"
        }
    }
}

#if DEBUG
#Preview {
    CheckoutCardView(card: CheckoutCard.sample) {}
        .background(Color("TuckSheet"))
}

extension CheckoutCard {
    static let sample = CheckoutCard(
        orderID: "ord_sample",
        quote: OrderQuote(
            product: QuotedProduct(id: "sofa_028_brown", name: "Peacemaker Accent Chair", brand: "Wayfair", imageUrl: nil, category: "single_seat_sofa"),
            quantity: 1, unitCents: 41999, subtotalCents: 41999, shippingCents: 0, taxCents: 3675, totalCents: 45674, currency: "usd",
            address: OrderAddress(line1: "1 Market St", line2: nil, city: "San Francisco", state: "CA", postalCode: "94105", country: "US"),
            budgetCents: 50000, hash: "sample"
        ),
        paymentMethod: CardSummary(brand: "visa", last4: "4242")
    )
}
#endif
