import SwiftUI

/// 좌측 TUCK 로고, 우측 프로필 아바타.
struct HomeHeader: View {
    let initial: String
    let onAvatarTap: () -> Void

    var body: some View {
        HStack {
            Image("TuckLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 35)
                .accessibilityLabel("Tuck")
            Spacer()
            Button(action: onAvatarTap) {
                Text(initial)
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 35, height: 35)
                    .background(Color("TuckBrown"), in: .circle)
            }
            .accessibilityLabel("Profile")
        }
        .padding(.horizontal, 19)
    }
}

#Preview {
    HomeHeader(initial: "H") {}
}
