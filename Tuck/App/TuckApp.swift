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
            // Stripe resumes the flow when the app returns from external authentication such as 3DS.
            .onOpenURL { _ = PaymentSheetPresenter.handleURLCallback($0) }
            .task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.easeOut(duration: 0.4)) {
                    showSplash = false
                }
            }
        }
    }
}
