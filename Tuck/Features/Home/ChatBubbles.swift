import SwiftUI

/// 사용자 말풍선 (우측 정렬, 크림색 배경).
struct UserBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 16))
            .foregroundStyle(Color("TuckBrown"))
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background(Color("TuckCream"), in: .rect(cornerRadius: 16))
            .frame(maxWidth: 265, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 23)
    }
}

/// 에이전트 답변 텍스트 (말풍선 없이 본문으로 표시).
struct AssistantText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 16))
            .foregroundStyle(Color("TuckBrown"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 26)
    }
}

#Preview {
    VStack(spacing: 16) {
        UserBubble(text: ChatMessage.sampleUser.text)
        AssistantText(text: ChatMessage.sampleAnswer.text)
    }
}
