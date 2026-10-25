import StripePaymentSheet
import SwiftUI

@main
struct TuckApp: App {
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                HomeView()
                    .preferredColorScheme(.light)

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            // 3DS 등 외부 인증에서 돌아올 때 Stripe가 결과를 이어받는다.
            .onOpenURL { _ = StripeAPI.handleURLCallback(with: $0) }
            .task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.easeOut(duration: 0.4)) {
                    showSplash = false
                }
            }
        }
    }
}
