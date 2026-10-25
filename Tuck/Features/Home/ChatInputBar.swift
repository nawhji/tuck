import SwiftUI

/// 채팅 입력창. 비어 있고 포커스가 없을 때는 한 줄, 입력 중에는 추가 입력 공간이 있는 확장 형태.
struct ChatInputBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let canSend: Bool
    let onSend: () -> Void
    var isResponding = false
    var onStop: () -> Void = {}

    private var isActive: Bool { isFocused.wrappedValue || !text.isEmpty }

    var body: some View {
        // 필드는 항상 같은 위치에 둔다. 레이아웃 분기로 TextField가 새로 만들어지면 포커스를 잃는다.
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                field
                if !isActive { sendButton }
            }
            if isActive {
                HStack(spacing: 14) {
                    Spacer()
                    sendButton
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isActive ? 14 : 9)
        .background(Color("TuckSheet"), in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color("GrayScale100"), lineWidth: 1)
        }
        .padding(.horizontal, 11)
        // 필드 글자 영역뿐 아니라 입력창 어디를 눌러도 포커스가 잡히게 한다.
        .contentShape(.rect)
        .onTapGesture { isFocused.wrappedValue = true }
        .animation(.easeOut(duration: 0.2), value: isActive)
    }

    private var field: some View {
        TextField("Any new ideas?", text: $text, axis: .vertical)
            .font(.system(size: 16))
            .foregroundStyle(Color("TuckBrown"))
            .lineLimit(1...5)
            .focused(isFocused)
    }

    private var sendButton: some View {
        // .disabled 를 쓰면 비활성 버튼이 탭을 삼켜 입력창 포커스가 안 잡힌다.
        Button {
            if isResponding { onStop() }
            else if canSend { onSend() }
            else { isFocused.wrappedValue = true }
        } label: {
            Image(systemName: isResponding ? "stop.fill" : "arrow.up")
                .font(.system(size: isResponding ? 12 : 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background((canSend || isResponding) ? Color("TuckBrown") : Color("GrayScale100"), in: .circle)
        }
        .accessibilityLabel(isResponding ? "Stop response" : "Send")
    }
}

#Preview("Idle") {
    @Previewable @State var text = ""
    @Previewable @FocusState var focused: Bool
    ChatInputBar(text: $text, isFocused: $focused, canSend: false, onSend: {})
}

#Preview("Typing") {
    @Previewable @State var text = "I’d like to get a modern carpet besides my bed."
    @Previewable @FocusState var focused: Bool
    ChatInputBar(text: $text, isFocused: $focused, canSend: true, onSend: {})
}

#Preview("Responding") {
    @Previewable @State var text = ""
    @Previewable @FocusState var focused: Bool
    ChatInputBar(text: $text, isFocused: $focused, canSend: false, onSend: {}, isResponding: true, onStop: {})
}
