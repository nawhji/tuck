import Foundation

/// In-chat purchase flow: quote → (alternatives if over budget) → order confirmation card → [Order] → PaymentSheet → server/webhook confirmation → result.
/// Appends a segment to the answer that requested the purchase instead of creating a message, preserving chat scroll and 3D room state.
extension HomeViewModel {
    // MARK: - Quote

    /// Called when the agent reports purchase intent. The product is named by the user or selected by the model to match their criteria;
    /// if unspecified, use the product placed/selected in the room. The user does not need to tap Try.
    @MainActor
    func startCheckout(for placedID: Product.ID?, intent: BuyIntent, attachingTo messageID: ChatMessage.ID) async {
        guard !Task.isCancelled else { return }
        guard PaymentSheetPresenter.isSupported else {
            attach([.text(PaymentSheetPresenter.unsupportedMessage)], to: messageID)
            return
        }
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

    /// Handles [Order]. Set the state to `.processing` first so a double tap cannot start a second request.
    @MainActor
    func placeOrder(_ tapped: CheckoutCard) {
        guard let card = card(orderID: tapped.orderID) else { return }
        guard PaymentSheetPresenter.isSupported else {
            fail(orderID: card.orderID, message: PaymentSheetPresenter.unsupportedMessage)
            return
        }
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
                // Never charge an amount the user has not seen. Show the updated quote and require [Order] again.
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
            // Do not trust the sheet result. Wait for the server to confirm the status with a signed webhook.
            update(orderID: orderID) { $0.state = .confirming }
            await settle(orderID: orderID)
        case .canceled:
            // If the sheet closes after a decline, report a payment failure rather than cancellation.
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
            // If payment is already in progress, do not cancel it; follow the server status.
            update(orderID: orderID) { $0.state = .confirming }
            await settle(orderID: orderID)
        }
    }

    /// Waits for the server to confirm the final status through a webhook.
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

    /// Appends a segment to the answer for a purchase request. Also adds a brief note to the raw response so the model knows the status on the next turn.
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
