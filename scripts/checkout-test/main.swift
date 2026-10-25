import Foundation

// 앱의 CheckoutClient / ReplyParser / 모델을 backend 개발 서버(가짜 Stripe)에 붙여 구매 흐름을 검증한다.
// 실행: scripts/test-checkout.sh
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

print("ReplyParser / 모델")
let reply = "On it.\n\n```tuck-buy\n{\"quantity\":2,\"budget_usd\":200}\n```"
check(ReplyParser.buyIntent(in: reply) == BuyIntent(quantity: 2, budgetCents: 20_000), "구매 블록 파싱: 수량 2, 예산 $200")
check(ReplyParser.buyIntent(in: "```tuck-buy\n{\"quantity\":1}\n```") == BuyIntent(quantity: 1, budgetCents: nil), "예산 생략 가능")
check(ReplyParser.buyIntent(in: "```tuck-buy\n{\"quantity\":1,\"budget_usd\":2") == nil, "닫히지 않은 블록은 스트리밍 중이라 무시")
check(ReplyParser.buyIntent(in: "just chatting") == nil, "구매 블록이 없으면 nil")
check(ReplyParser.parse(reply) == [.text("On it."), .buy(BuyIntent(quantity: 2, budgetCents: 20_000))], "본문 + 구매 블록 구성")
check(ReplyParser.parse("hi ```tuck-b") == [.text("hi")], "끝에 걸린 구매 펜스 조각은 숨김")
let mixed = ReplyParser.parse("A\n```tuck-products\n{\"products\":[{\"id\":\"sofa_001_yellow\"}]}\n```\nB\n```tuck-buy\n{\"quantity\":1}\n```")
check(mixed.count == 4, "카드와 구매 블록이 섞여도 순서대로 파싱")
check(CardNumberRedactor.redact("my card 4242 4242 4242 4242 ok") == "my card [card number removed] ok", "카드 번호는 모델로 보내기 전에 제거")
check(CardNumberRedactor.redact("order 1234567890123 please") == "order 1234567890123 please", "Luhn을 통과하지 않는 숫자는 그대로")
check(CardNumberRedactor.redact("buy this within $200") == "buy this within $200", "일반 문장은 그대로")

print("\nCheckoutClient ↔ backend")
let client = CheckoutClient(baseURL: base)
let product = "sofa_028_brown"

// 견적
let quote = try await client.quote(productID: product, quantity: 1, budgetCents: 20_000_00 / 10)
check(quote.status == .ok && quote.orderId != nil, "예산 안이면 주문 초안과 견적을 받는다")
let card = quote.quote!
check(card.totalCents == card.subtotalCents + card.shippingCents + card.taxCents, "합계 = 상품 + 배송 + 세금 (서버 계산)")
check(quote.paymentMethod?.label == "Visa •••• 4242", "미리 채워진 결제 수단 표시")
check(card.address.city == "San Francisco", "배송지 표시")

// 예산 초과 → 대안
let over = try await client.quote(productID: "sofa_012_brown", quantity: 1, budgetCents: 20_000)
check(over.status == .overBudget && over.orderId == nil, "예산 초과면 주문을 만들지 않는다")
check(!over.alternatives.isEmpty && over.alternatives.allSatisfy { $0.totalCents <= 20_000 }, "예산 안 대안 제시")
check(over.alternatives.first?.fitsPlacement == true, "자리에 맞는 대안이 먼저")
let gone = try await client.quote(productID: "sofa_007_brown", quantity: 1, budgetCents: nil)
check(gone.status == .unavailable && gone.quote == nil && !gone.alternatives.isEmpty, "품절이면 대안 제시 (금액 없는 견적도 디코딩)")

// 성공: confirm → PaymentSheet 파라미터 → 웹훅 → paid
let orderID = quote.orderId!
guard case let .pay(params, _) = try await client.confirm(orderID: orderID, quoteHash: card.hash) else { fatalError("expected .pay") }
check(params.clientSecret.hasPrefix("pi_secret_") && params.ephemeralKeySecret.hasPrefix("ek_test_"), "PaymentSheet 파라미터 수신")
guard case let .pay(again, _) = try await client.confirm(orderID: orderID, quoteHash: card.hash) else { fatalError("expected .pay") }
check(again.clientSecret == params.clientSecret, "중복 confirm은 같은 PaymentIntent")
let pending = try await client.order(id: orderID)
check(pending.status == .awaitingPayment, "시트가 끝나도 웹훅 전에는 결제 완료가 아니다")
try await post("/event", ["type": "payment_intent.succeeded", "orderId": orderID, "status": "succeeded"])
let settled = try await client.order(id: orderID)
check(settled.status == .paid, "서명된 웹훅 후 paid")
if case .alreadyPaid = try await client.confirm(orderID: orderID, quoteHash: card.hash) { check(true, "paid 주문의 confirm은 결제를 다시 만들지 않는다") } else { check(false, "paid confirm") }

// 거절 → 재시도 → 성공
let declined = try await client.quote(productID: "sofa_030_brown", quantity: 1, budgetCents: nil)
let declinedID = declined.orderId!
_ = try await client.confirm(orderID: declinedID, quoteHash: declined.quote!.hash)
try await post("/event", ["type": "payment_intent.payment_failed", "orderId": declinedID,
                          "failure": ["code": "card_declined", "decline_code": "generic_decline", "message": "Your card was declined."]])
let failed = try await client.order(id: declinedID)
check(failed.status == .paymentFailed && failed.failure?.message == "Your card was declined.", "거절은 웹훅으로 기록되고 메시지가 전달된다")
if case .pay = try await client.confirm(orderID: declinedID, quoteHash: declined.quote!.hash) { check(true, "거절 후 같은 주문으로 재시도 가능") } else { check(false, "retry") }

// 취소
let cancelQuote = try await client.quote(productID: "sofa_024_beige", quantity: 1, budgetCents: nil)
let cancelID = cancelQuote.orderId!
_ = try await client.confirm(orderID: cancelID, quoteHash: cancelQuote.quote!.hash)
let canceled = try await client.cancel(orderID: cancelID)
check(canceled.status == .canceled, "시트 취소 → 주문 canceled")
do {
    _ = try await client.confirm(orderID: cancelID, quoteHash: cancelQuote.quote!.hash)
    check(false, "취소된 주문은 결제할 수 없다")
} catch let CheckoutClient.CheckoutError.server(code, _) {
    check(code == "order_canceled", "취소된 주문은 결제할 수 없다")
}

// 가격 변경 → 재확인
let changing = try await client.quote(productID: "sofa_020_black", quantity: 1, budgetCents: nil)
try await post("/price", ["productId": "sofa_020_black", "cents": 31_900])
if case let .quoteChanged(snapshot) = try await client.confirm(orderID: changing.orderId!, quoteHash: changing.quote!.hash) {
    check(snapshot.quote.unitCents == 31_900 && snapshot.quote.hash != changing.quote!.hash, "가격이 바뀌면 새 견적을 돌려주고 결제하지 않는다")
    if case .pay = try await client.confirm(orderID: changing.orderId!, quoteHash: snapshot.quote.hash) {
        check(true, "새 견적을 승인하면 새 금액으로 진행")
    } else { check(false, "approve new quote") }
} else { check(false, "quote change") }

// 중복 요청 동시성
let burst = try await client.quote(productID: "sofa_021_brown", quantity: 1, budgetCents: nil)
let results = await withTaskGroup(of: PaymentParams?.self) { group in
    for _ in 0..<5 { group.addTask { if case let .pay(p, _)? = try? await client.confirm(orderID: burst.orderId!, quoteHash: burst.quote!.hash) { p } else { nil } } }
    return await group.reduce(into: [PaymentParams?]()) { $0.append($1) }
}
check(results.compactMap { $0 }.count == 5 && Set(results.compactMap { $0?.clientSecret }).count == 1, "동시 5회 confirm → 같은 PaymentIntent 하나")

print(failures == 0 ? "\n✅ all checks passed" : "\n❌ \(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
