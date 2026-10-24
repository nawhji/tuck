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
                // Figma: icon center 27.5pt above screen center. LaunchLogo is padded
                // with 55pt of background at the bottom so the system launch screen
                // (which centers the image) places the logo at the same spot.
                .offset(y: -27.5)
        }
        // Center on the full screen like the system launch screen, not the safe area.
        .ignoresSafeArea()
    }
}

#Preview {
    SplashView()
}
