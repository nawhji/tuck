import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Color(red: 0x4A / 255, green: 0x35 / 255, blue: 0x2B / 255)
                .ignoresSafeArea()

            Image("SplashIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 291, height: 291)
                // Figma: icon top at 253 in an 852pt frame (center 398.5 vs 426)
                .offset(y: -27.5)
        }
    }
}

#Preview {
    SplashView()
}
