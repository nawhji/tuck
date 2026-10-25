import SwiftUI

/// Chat input. It is one line when empty and unfocused, and expands to provide more space while typing.
struct ChatInputBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let canSend: Bool
    let onSend: () -> Void
    var isResponding = false
    var onStop: () -> Void = {}

    private var isActive: Bool { isFocused.wrappedValue || !text.isEmpty }

    var body: some View {
        // Keep the field in the same position. Recreating the TextField in a layout branch would lose focus.
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
        // Make the whole input area focus the field, not just the text region.
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
        // `.disabled` makes the inactive button consume taps and prevents the input field from receiving focus.
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
