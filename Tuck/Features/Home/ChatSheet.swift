import SwiftUI

/// 하단 채팅 시트: 핸들 + 제목 + 메시지 목록 + 입력창. 높이 조절(드래그)은 부모가 담당한다.
struct ChatSheet<Drag: Gesture>: View {
    let messages: [ChatMessage]
    let selectedProductID: Product.ID?
    @Binding var draft: String
    var isInputFocused: FocusState<Bool>.Binding
    let canSend: Bool
    let dragGesture: Drag
    let onSend: () -> Void
    let onImage: () -> Void
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
                                // 마지막 질문과 그 답변: 높이를 재서 남는 만큼만 아래 여백으로 채운다.
                                VStack(spacing: 16) {
                                    ForEach(messages.dropFirst(tailStart)) { message in
                                        messageView(message).id(message.id)
                                    }
                                }
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tailHeight = $0 }
                                // 답변이 짧아도 질문을 맨 위로 올릴 수 있도록, 마지막 질문 이후 내용 높이를 뺀 만큼만 여백을 둔다.
                                Color.clear.frame(height: max(viewport.size.height - tailHeight - 16, 0))
                            }
                            .padding(.vertical, 16)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        // 질문을 보내면 그 질문이 시트 상단에 보이도록 맞추고, 스트리밍 중에는 따라가지 않는다.
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
                    onImage: onImage
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
            // 홈 인디케이터 영역까지 시트 색을 이어 붙이고, 하단 그림자를 덮는다.
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
                // 캐릭터는 본문 위 별도 줄에 둬서 텍스트 줄바꿈에 영향을 주지 않는다.
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
                            ProductCardView(product: product, isSelected: product.id == selectedProductID) {
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
