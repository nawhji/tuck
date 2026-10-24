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

/// 에이전트 답변 텍스트 (말풍선 없이 본문으로 표시). `#### 제목`, **굵게**, *기울임*을 적용한다.
struct AssistantText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.lines(text).enumerated()), id: \.offset) { _, line in
                switch line {
                case .heading(let title):
                    Text(Self.markdown(title))
                        .font(.system(size: 18, weight: .semibold))
                case .paragraph(let body):
                    Text(Self.markdown(body))
                        .font(.system(size: 16))
                }
            }
        }
        .foregroundStyle(Color("TuckBrown"))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
    }

    enum Line: Equatable {
        case heading(String)
        case paragraph(String)
    }

    /// `#`으로 시작하는 줄은 제목, 이어지는 나머지 줄은 한 문단으로 묶는다.
    static func lines(_ text: String) -> [Line] {
        var result: [Line] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { result.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let heading = heading(in: line) {
                flush()
                result.append(.heading(heading))
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            } else {
                paragraph.append(String(line))
            }
        }
        flush()
        return result
    }

    private static func heading(in line: Substring) -> String? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count), line.dropFirst(hashes.count).first == " " else { return nil }
        return line.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
    }

    /// 인라인 마크다운을 적용한다. 스트리밍 중 닫히지 않은 기호는 글자 그대로 둔다.
    static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

#Preview {
    VStack(spacing: 16) {
        UserBubble(text: ChatMessage.sampleUser.text)
        AssistantText(text: ChatMessage.sampleAnswer.text)
    }
}
