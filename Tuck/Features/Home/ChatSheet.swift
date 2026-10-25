import SwiftUI

/// Bottom chat sheet: handle, title, message list, and input. The parent handles height changes by dragging.
struct ChatSheet<Drag: Gesture>: View {
    let messages: [ChatMessage]
    let selectedProductID: Product.ID?
    var placedProductIDs: Set<Product.ID>? = nil
    @Binding var draft: String
    var isInputFocused: FocusState<Bool>.Binding
    let canSend: Bool
    let dragGesture: Drag
    let onSend: () -> Void
    let isResponding: Bool
    let onStop: () -> Void
    let onSelect: (Product) -> Void
    let onOrder: (CheckoutCard) -> Void

    var isMinimized = false
    var onExpand: () -> Void = {}

    @State private var tailHeight: CGFloat = 0

    private var tailStart: Int {
        messages.lastIndex(where: { $0.role == .user }) ?? messages.count
    }

    var body: some View {
        VStack(spacing: 0) {
            grabber
            if !isMinimized {
                GeometryReader { viewport in
                    ScrollViewReader { scroll in
                        ScrollView {
                            VStack(spacing: 16) {
                                ForEach(messages.prefix(tailStart)) { message in
                                    messageView(message).id(message.id)
                                }
                                // Measure the last question and answer, then use only the remaining height as bottom spacing.
                                VStack(spacing: 16) {
                                    ForEach(messages.dropFirst(tailStart)) { message in
                                        messageView(message).id(message.id)
                                    }
                                }
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tailHeight = $0 }
                                // Keep only the space left after the last question so it can stay at the top even when its answer is short.
                                Color.clear.frame(height: max(viewport.size.height - tailHeight - 16, 0))
                            }
                            .padding(.vertical, 16)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        // After sending a question, align it at the top of the sheet and do not auto-scroll during streaming.
                        .onChange(of: messages.count) {
                            guard let question = messages.last(where: { $0.role == .user }) else { return }
                            withAnimation { scroll.scrollTo(question.id, anchor: .top) }
                        }
                    }
                }
                ChatInputBar(
                    text: $draft,
                    isFocused: isInputFocused,
                    canSend: canSend,
                    onSend: onSend,
                    isResponding: isResponding,
                    onStop: onStop
                )
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 31, topTrailingRadius: 31)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 8)
                Color.white.padding(.top, 31)
            }
            // Extend the sheet color through the home-indicator area and cover the bottom shadow.
            .overlay(alignment: .bottom) {
                Color.white
                    .frame(height: 120)
                    .offset(y: 120)
            }
        }
    }

    private var grabber: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color("GrayScale100"))
                .frame(width: 34, height: 5)
        }
        .padding(.top, 12)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .gesture(dragGesture)
        .onTapGesture { if isMinimized { onExpand() } }
        .accessibilityLabel(isMinimized ? "Expand chat" : "Resize chat")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onExpand() }
    }

    @ViewBuilder
    private func messageView(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            UserBubble(text: message.text)
        case .assistant:
            VStack(alignment: .leading, spacing: 16) {
                // Put the mascot on its own line above the response so it does not affect text wrapping.
                Group {
                    if message.blocks.isEmpty {
                        TuckLoadingIndicator()
                    } else {
                        TuckAvatar()
                    }
                }
                .padding(.horizontal, 26)
                ForEach(Array((message.blocks + message.trailing).enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let text):
                        AssistantText(text: text)
                    case .products(let products):
                        ForEach(products) { product in
                            ProductCardView(product: product, isSelected: placedProductIDs?.contains(product.id) ?? (product.id == selectedProductID)) {
                                onSelect(product)
                            }
                        }
                    case .checkout(let card):
                        CheckoutCardView(card: card) { onOrder(card) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
