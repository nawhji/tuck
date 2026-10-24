import SwiftUI

/// 하단 채팅 시트: 핸들 + 제목 + 메시지 목록 + 입력창. 높이 조절(드래그)은 부모가 담당한다.
struct ChatSheet<Drag: Gesture>: View {
    let title: String
    let messages: [ChatMessage]
    let selectedProductID: Product.ID?
    @Binding var draft: String
    var isInputFocused: FocusState<Bool>.Binding
    let canSend: Bool
    let dragGesture: Drag
    let onSend: () -> Void
    let onImage: () -> Void
    let onShare: (Product) -> Void
    let onSelect: (Product) -> Void

    private let bottomID = "chat-bottom"

    var body: some View {
        VStack(spacing: 0) {
            grabber
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(messages) { message in
                            messageView(message)
                        }
                        Color.clear.frame(height: 1).id(bottomID)
                    }
                    .padding(.vertical, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages) {
                    scroll.scrollTo(bottomID, anchor: .bottom)
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
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 31, topTrailingRadius: 31)
                    .fill(Color("TuckSheet"))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 8)
                Color("TuckSheet").padding(.top, 31)
            }
            // 홈 인디케이터 영역까지 시트 색을 이어 붙이고, 하단 그림자를 덮는다.
            .overlay(alignment: .bottom) {
                Color("TuckSheet")
                    .frame(height: 120)
                    .offset(y: 120)
            }
        }
    }

    private var grabber: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(Color("GrayScale100"))
                .frame(width: 34, height: 5)
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color("GrayScale300"))
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .gesture(dragGesture)
    }

    @ViewBuilder
    private func messageView(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            UserBubble(text: message.text)
        case .assistant:
            if message.text.isEmpty && message.products.isEmpty {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24)
            } else {
                AssistantText(text: message.text)
            }
            ForEach(message.products) { product in
                ProductCardView(product: product, isSelected: product.id == selectedProductID) {
                    onShare(product)
                }
                .onTapGesture { onSelect(product) }
            }
        }
    }
}
