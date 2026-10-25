import Foundation

/// 채팅 안 구매 흐름: 견적 → (예산 초과 시 대안) → 주문 확인 카드 → [Order] → PaymentSheet → 서버(웹훅) 확정 → 결과 안내.
/// 새 메시지를 만들지 않고 구매를 요청한 답변 뒤에 덩어리를 붙여, 채팅 스크롤과 3D 방 상태를 건드리지 않는다.
extension HomeViewModel {
    // MARK: - Quote

    /// 에이전트가 구매 의사를 전달하면 호출된다. 상품은 사용자가 지칭했거나 조건에 맞아 모델이 고른 것이고,
    /// 지정이 없으면 방에 놓인(선택된) 상품이다. Try를 누르지 않아도 된다.
    @MainActor
    func startCheckout(for placedID: Product.ID?, intent: BuyIntent, attachingTo messageID: ChatMessage.ID) async {
        guard !Task.isCancelled else { return }
        let requested = intent.productID.flatMap { id in catalog?.row(id: id) != nil ? id : nil }
        guard let productID = requested ?? placedID else {
            attach([.text("I'm not sure which piece you mean. Tell me which one, or describe what you want, and I'll order it.")], to: messageID)
            return
        }
        selectedProductID = productID
        do {
            let response = try await checkout.quote(productID: productID, quantity: intent.quantity, budgetCents: intent.budgetCents)
            try Task.checkCancellation()
            attach(blocks(for: response), note: quoteNote(response), to: messageID)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            attach([.text("I couldn't get a quote right now: \(error.localizedDescription)")], to: messageID)
        }
    }

    private func blocks(for response: QuoteResponse) -> [ChatMessage.Block] {
        switch response.status {
        case .ok:
            guard let quote = response.quote, let orderID = response.orderId else { return [.text("I couldn't price that order.")] }
            return [.checkout(CheckoutCard(orderID: orderID, quote: quote, paymentMethod: response.paymentMethod))]
        case .overBudget:
            guard let quote = response.quote else { return [] }
            let budget = quote.budgetCents.map { quote.format($0) } ?? "your budget"
            return alternativesBlocks(
                response.alternatives,
                intro: "That one comes to **\(quote.format(quote.totalCents))** with shipping and tax, over your **\(budget)** budget.",
                found: "These stay in budget (shipping and tax included), keep the same style, and fit the spot you placed it in. Tap **Try** to swap one in, then ask me to buy it.",
                none: "Nothing else in the catalog fits that budget with shipping and tax. Want to raise it a little?"
            )
        case .unavailable:
            return alternativesBlocks(
                response.alternatives,
                intro: "That one is out of stock right now.",
                found: "These are close matches that are available. Tap **Try** to place one, then ask me to buy it.",
                none: "I don't have a similar piece in stock at the moment."
            )
        }
    }

    private func alternativesBlocks(_ alternatives: [QuoteAlternative], intro: String, found: String, none: String)
        -> [ChatMessage.Block] {
        let products = alternatives.compactMap { alternative in
            catalog.flatMap { Product(pick: ProductPick(id: alternative.product.id, keywords: alternative.styleTags), catalog: $0) }
        }
        guard !products.isEmpty else { return [.text("\(intro) \(none)")] }
        var blocks: [ChatMessage.Block] = [.text("\(intro) \(found)"), .products(products)]
        if alternatives.contains(where: { !$0.fitsPlacement }) {
            blocks.append(.text("Heads up: the last pick is a bit bigger than your current spot, so check it in the room first."))
        }
        return blocks
    }

    private func quoteNote(_ response: QuoteResponse) -> String {
        switch response.status {
        case .ok: "[app: order summary card shown; waiting for the user to tap Order]"
        case .overBudget: "[app: the placed product is over the user's budget; in-budget alternatives were shown]"
        case .unavailable: "[app: the placed product is unavailable; alternatives were shown]"
        }
    }

    // MARK: - Order

    /// [Order] 탭. 상태를 먼저 `.processing`으로 바꿔 더블 탭이 두 번째 요청을 만들지 못하게 한다.
    @MainActor
    func placeOrder(_ tapped: CheckoutCard) {
        guard let card = card(orderID: tapped.orderID) else { return }
        switch card.state {
        case .ready, .failed:
            update(orderID: card.orderID) { $0.state = .processing; $0.notice = nil }
            Task { await pay(orderID: card.orderID) }
        case .pending:
            update(orderID: card.orderID) { $0.state = .confirming; $0.notice = nil }
            Task { await settle(orderID: card.orderID) }
        case .canceled:
            reorder(card)
        case .processing, .confirming, .paid:
            break
        }
    }

    @MainActor
    private func reorder(_ card: CheckoutCard) {
        guard let messageID = messageID(forOrder: card.orderID) else { return }
        let intent = BuyIntent(quantity: card.quote.quantity, budgetCents: card.quote.budgetCents)
        update(orderID: card.orderID) { $0.state = .processing; $0.notice = nil }
        Task {
            await startCheckout(for: card.quote.product.id, intent: intent, attachingTo: messageID)
            update(orderID: card.orderID) { $0.state = .canceled }
        }
    }

    @MainActor
    private func pay(orderID: String) async {
        guard let hash = card(orderID: orderID)?.quote.hash else { return }
        do {
            switch try await checkout.confirm(orderID: orderID, quoteHash: hash) {
            case .quoteChanged(let snapshot):
                // 사용자가 보지 못한 금액은 결제하지 않는다. 새 견적을 보여주고 다시 [Order]를 받는다.
                let old = card(orderID: orderID)?.quote
                update(orderID: orderID) {
                    $0.quote = snapshot.quote
                    $0.paymentMethod = snapshot.paymentMethod ?? $0.paymentMethod
                    $0.state = .ready
                    $0.notice = "The price changed from \(old?.format(old?.totalCents ?? 0) ?? "before") to "
                        + "\(snapshot.quote.format(snapshot.quote.totalCents)). Review the new total and tap Order again."
                }
            case .alreadyPaid(let snapshot):
                finish(orderID: orderID, snapshot: snapshot)
            case .pay(let params, _):
                await present(params, orderID: orderID)
            }
        } catch {
            fail(orderID: orderID, message: error.localizedDescription)
        }
    }

    @MainActor
    private func present(_ params: PaymentParams, orderID: String) async {
        switch await PaymentSheetPresenter.present(params) {
        case .completed:
            // 시트 결과는 신뢰하지 않는다. 서버가 서명된 웹훅으로 확정한 상태를 기다린다.
            update(orderID: orderID) { $0.state = .confirming }
            await settle(orderID: orderID)
        case .canceled:
            // 거절 후 시트를 닫은 경우는 취소가 아니라 결제 실패로 안내한다.
            if let snapshot = try? await checkout.order(id: orderID), snapshot.status == .paymentFailed {
                fail(orderID: orderID, message: snapshot.failure?.message ?? "Your payment was declined.")
                return
            }
            await cancel(orderID: orderID)
        case .failed(let message):
            fail(orderID: orderID, message: message)
        }
    }

    @MainActor
    private func cancel(orderID: String) async {
        do {
            let snapshot = try await checkout.cancel(orderID: orderID)
            if snapshot.status == .canceled {
                update(orderID: orderID) { $0.state = .canceled; $0.notice = nil }
                announce("Payment canceled. You haven't been charged. Tap **Order again** whenever you're ready.", note: "canceled",
                         orderID: orderID)
            }
        } catch {
            // 이미 결제가 진행 중이면 취소하지 않고 서버 상태를 따라간다.
            update(orderID: orderID) { $0.state = .confirming }
            await settle(orderID: orderID)
        }
    }

    /// 서버가 웹훅으로 최종 상태를 확정할 때까지 기다린다.
    @MainActor
    private func settle(orderID: String) async {
        for _ in 0..<30 {
            if let snapshot = try? await checkout.order(id: orderID) {
                switch snapshot.status {
                case .paid:
                    finish(orderID: orderID, snapshot: snapshot)
                    return
                case .paymentFailed:
                    fail(orderID: orderID, message: snapshot.failure?.message ?? "Your payment was declined.")
                    return
                case .canceled:
                    update(orderID: orderID) { $0.state = .canceled }
                    return
                case .needsReview:
                    update(orderID: orderID) { $0.state = .pending; $0.notice = "We're double-checking this payment. Nothing more to do for now." }
                    return
                case .quoted, .awaitingPayment, .unknown:
                    break
                }
            }
            try? await Task.sleep(for: .seconds(1))
        }
        update(orderID: orderID) {
            $0.state = .pending
            $0.notice = "Still waiting for the payment confirmation. Tap Check status in a moment."
        }
    }

    // MARK: - Results

    @MainActor
    private func finish(orderID: String, snapshot: OrderSnapshot) {
        update(orderID: orderID) { $0.state = .paid; $0.notice = nil }
        let quote = snapshot.quote
        orders.record(orderID: orderID, quote: quote, card: snapshot.paymentMethod ?? card(orderID: orderID)?.paymentMethod)
        announce(
            "Order placed ✅ **\(quote.product.name)** is on its way to \(quote.address.line1). "
                + "Total **\(quote.format(quote.totalCents))**. This was a Stripe test payment, so nothing was really charged.",
            note: "order paid, total \(quote.format(quote.totalCents))", orderID: orderID
        )
    }

    @MainActor
    private func fail(orderID: String, message: String) {
        update(orderID: orderID) { $0.state = .failed(message); $0.notice = nil }
        announce("That payment didn't go through: \(message) You haven't been charged. Tap **Try again** or use a different card.",
                 note: "payment failed: \(message)", orderID: orderID)
    }

    // MARK: - Chat plumbing

    /// 구매 요청에 대한 답변 뒤에 덩어리를 붙인다. 모델이 다음 턴에 상태를 알 수 있도록 원문에 짧은 메모도 남긴다.
    @MainActor
    private func attach(_ blocks: [ChatMessage.Block], note: String? = nil, to id: ChatMessage.ID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].trailing += blocks
        if let note { messages[index].rawText += "\n\n\(note)" }
    }

    @MainActor
    private func announce(_ text: String, note: String, orderID: String) {
        guard let id = messageID(forOrder: orderID) else { return }
        attach([.text(text)], note: "[app: \(note)]", to: id)
    }

    private func messageID(forOrder orderID: String) -> ChatMessage.ID? {
        messages.first { message in
            message.trailing.contains { if case .checkout(let card) = $0 { card.orderID == orderID } else { false } }
        }?.id
    }

    private func card(orderID: String) -> CheckoutCard? {
        for message in messages {
            for case let .checkout(card) in message.trailing where card.orderID == orderID { return card }
        }
        return nil
    }

    private func update(orderID: String, _ change: (inout CheckoutCard) -> Void) {
        for messageIndex in messages.indices {
            for blockIndex in messages[messageIndex].trailing.indices {
                if case .checkout(var card) = messages[messageIndex].trailing[blockIndex], card.orderID == orderID {
                    change(&card)
                    messages[messageIndex].trailing[blockIndex] = .checkout(card)
                    return
                }
            }
        }
    }
}
