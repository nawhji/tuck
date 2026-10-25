import SwiftUI

/// User message bubble (right-aligned with a cream background).
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

/// Agent response text, shown without a bubble. Supports `#### headings`, **bold**, and *italic*.
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

    /// Lines starting with `#` are headings; consecutive remaining lines are grouped into paragraphs.
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

    /// Applies inline Markdown. Unclosed markers are shown literally while streaming.
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
