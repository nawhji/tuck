import SwiftUI

/// Tuck 캐릭터. 로딩 중에는 눈을 깜빡이고, 끝나면 눈을 뜬 모습을 유지한다.
struct TuckAvatar: View {
    var isLoading = false
    var size: CGFloat = 32

    var body: some View {
        if isLoading {
            TimelineView(.periodic(from: .now, by: 0.45)) { context in
                let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.45)
                face(eyesOpen: tick.isMultiple(of: 2))
            }
        } else {
            face(eyesOpen: true)
        }
    }

    private func face(eyesOpen: Bool) -> some View {
        Image(eyesOpen ? "TuckEyesOpen" : "TuckEyesClosed")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// 답변을 기다리는 동안 보이는 캐릭터와 귀여운 문구.
struct TuckLoadingIndicator: View {
    private static let phrases = [
        "Rearranging the furniture in my head…",
        "Measuring twice, thinking thrice…",
        "Consulting my inner interior designer…",
        "Fluffing the virtual pillows…",
        "Hunting for the perfect cozy corner…",
        "Squinting at some fabric swatches…",
    ]

    @State private var phrase = Self.phrases.randomElement() ?? Self.phrases[0]

    var body: some View {
        HStack(spacing: 8) {
            TuckAvatar(isLoading: true)
            Text(phrase)
                .font(.system(size: 14))
                .foregroundStyle(Color("GrayScale300"))
                .id(phrase)
                .transition(.opacity)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation { phrase = Self.phrases.filter { $0 != phrase }.randomElement() ?? phrase }
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 24) {
        TuckLoadingIndicator()
        TuckAvatar()
    }
    .padding()
}
