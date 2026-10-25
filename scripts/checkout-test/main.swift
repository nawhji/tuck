import Foundation

// Tests the app purchase flow (CheckoutClient, ReplyParser, and models) against the backend development server (mock Stripe).
// Run: scripts/test-checkout.sh
var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if condition() { print("  ✓ \(message)") } else { print("  ✗ \(message) (line \(line))"); failures += 1 }
}

let base = URL(string: CommandLine.arguments[1])!
let control = URL(string: CommandLine.arguments[2])!

func post(_ path: String, _ body: [String: Any]) async throws {
    var request = URLRequest(url: control.appendingPathComponent(path))
    request.httpMethod = "POST"
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    _ = try await URLSession.shared.data(for: request)
}

print("ReplyParser / Models")
let reply = "On it.\n\n```tuck-buy\n{\"quantity\":2,\"budget_usd\":200}\n```"
check(ReplyParser.buyIntent(in: reply) == BuyIntent(quantity: 2, budgetCents: 20_000), "parses purchase block: quantity 2, $200 budget")
check(ReplyParser.buyIntent(in: "```tuck-buy\n{\"quantity\":1}\n```") == BuyIntent(quantity: 1, budgetCents: nil), "budget is optional")
check(ReplyParser.buyIntent(in: "```tuck-buy\n{\"quantity\":1,\"budget_usd\":2") == nil, "ignores an unclosed block during streaming")
check(ReplyParser.buyIntent(in: "just chatting") == nil, "returns nil when there is no purchase block")
check(ReplyParser.parse(reply) == [.text("On it."), .buy(BuyIntent(quantity: 2, budgetCents: 20_000))], "parses text and purchase block")
check(ReplyParser.parse("hi ```tuck-b") == [.text("hi")], "hides an incomplete trailing purchase fence")
let mixed = ReplyParser.parse("A\n```tuck-products\n{\"products\":[{\"id\":\"sofa_001_yellow\"}]}\n```\nB\n```tuck-buy\n{\"quantity\":1}\n```")
check(mixed.count == 4, "preserves order when cards and purchase blocks are mixed")
check(CardNumberRedactor.redact("my card 4242 4242 4242 4242 ok") == "my card [card number removed] ok", "removes card numbers before sending text to the model")
check(CardNumberRedactor.redact("order 1234567890123 please") == "order 1234567890123 please", "keeps numbers that fail the Luhn check")
check(CardNumberRedactor.redact("buy this within $200") == "buy this within $200", "leaves ordinary text unchanged")

print("\nCheckoutClient ↔ backend")
let client = CheckoutClient(baseURL: base)
let product = "sofa_028_brown"

// Quote
let quote = try await client.quote(productID: product, quantity: 1, budgetCents: 20_000_00 / 10)
check(quote.status == .ok && quote.orderId != nil, "gets an order draft and quote within budget")
let card = quote.quote!
check(card.totalCents == card.subtotalCents + card.shippingCents + card.taxCents, "total = product + shipping + tax (calculated by server)")
check(quote.paymentMethod?.label == "Visa •••• 4242", "shows the preloaded payment method")
check(card.address.city == "San Francisco", "shows the shipping address")

// Over budget → alternatives
let over = try await client.quote(productID: "sofa_012_brown", quantity: 1, budgetCents: 20_000)
check(over.status == .overBudget && over.orderId == nil, "does not create an order when over budget")
check(!over.alternatives.isEmpty && over.alternatives.allSatisfy { $0.totalCents <= 20_000 }, "suggests alternatives within budget")
check(over.alternatives.first?.fitsPlacement == true, "places fitting alternatives first")
let gone = try await client.quote(productID: "sofa_007_brown", quantity: 1, budgetCents: nil)
check(gone.status == .unavailable && gone.quote == nil && !gone.alternatives.isEmpty, "suggests alternatives when out of stock (decodes a quote without an amount)")

// Success: confirm → PaymentSheet parameters → webhook → paid
let orderID = quote.orderId!
guard case let .pay(params, _) = try await client.confirm(orderID: orderID, quoteHash: card.hash) else { fatalError("expected .pay") }
check(params.clientSecret.hasPrefix("pi_secret_") && params.ephemeralKeySecret.hasPrefix("ek_test_"), "receives PaymentSheet parameters")
guard case let .pay(again, _) = try await client.confirm(orderID: orderID, quoteHash: card.hash) else { fatalError("expected .pay") }
check(again.clientSecret == params.clientSecret, "duplicate confirm returns the same PaymentIntent")
let pending = try await client.order(id: orderID)
check(pending.status == .awaitingPayment, "payment is not complete until the webhook arrives, even after the sheet closes")
try await post("/event", ["type": "payment_intent.succeeded", "orderId": orderID, "status": "succeeded"])
let settled = try await client.order(id: orderID)
check(settled.status == .paid, "marks paid after a signed webhook")
if case .alreadyPaid = try await client.confirm(orderID: orderID, quoteHash: card.hash) { check(true, "confirming a paid order does not create another payment") } else { check(false, "paid confirm") }

// Decline → retry → success
let declined = try await client.quote(productID: "sofa_030_brown", quantity: 1, budgetCents: nil)
let declinedID = declined.orderId!
_ = try await client.confirm(orderID: declinedID, quoteHash: declined.quote!.hash)
try await post("/event", ["type": "payment_intent.payment_failed", "orderId": declinedID,
                          "failure": ["code": "card_declined", "decline_code": "generic_decline", "message": "Your card was declined."]])
let failed = try await client.order(id: declinedID)
check(failed.status == .paymentFailed && failed.failure?.message == "Your card was declined.", "records the decline from the webhook and returns the message")
if case .pay = try await client.confirm(orderID: declinedID, quoteHash: declined.quote!.hash) { check(true, "allows retrying the same order after a decline") } else { check(false, "retry") }

// Cancellation
let cancelQuote = try await client.quote(productID: "sofa_024_beige", quantity: 1, budgetCents: nil)
let cancelID = cancelQuote.orderId!
_ = try await client.confirm(orderID: cancelID, quoteHash: cancelQuote.quote!.hash)
let canceled = try await client.cancel(orderID: cancelID)
check(canceled.status == .canceled, "sheet cancellation marks the order canceled")
do {
    _ = try await client.confirm(orderID: cancelID, quoteHash: cancelQuote.quote!.hash)
    check(false, "cannot pay for a canceled order")
} catch let CheckoutClient.CheckoutError.server(code, _) {
    check(code == "order_canceled", "cannot pay for a canceled order")
}

// Price change → reconfirmation
let changing = try await client.quote(productID: "sofa_020_black", quantity: 1, budgetCents: nil)
try await post("/price", ["productId": "sofa_020_black", "cents": 31_900])
if case let .quoteChanged(snapshot) = try await client.confirm(orderID: changing.orderId!, quoteHash: changing.quote!.hash) {
    check(snapshot.quote.unitCents == 31_900 && snapshot.quote.hash != changing.quote!.hash, "returns a new quote and does not charge when the price changes")
    if case .pay = try await client.confirm(orderID: changing.orderId!, quoteHash: snapshot.quote.hash) {
        check(true, "continues with the new amount after approving the quote")
    } else { check(false, "approve new quote") }
} else { check(false, "quote change") }

// Concurrent duplicate requests
let burst = try await client.quote(productID: "sofa_021_brown", quantity: 1, budgetCents: nil)
let results = await withTaskGroup(of: PaymentParams?.self) { group in
    for _ in 0..<5 { group.addTask { if case let .pay(p, _)? = try? await client.confirm(orderID: burst.orderId!, quoteHash: burst.quote!.hash) { p } else { nil } } }
    return await group.reduce(into: [PaymentParams?]()) { $0.append($1) }
}
check(results.compactMap { $0 }.count == 5 && Set(results.compactMap { $0?.clientSecret }).count == 1, "five concurrent confirms create the same single PaymentIntent")

print(failures == 0 ? "\n✅ all checks passed" : "\n❌ \(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
