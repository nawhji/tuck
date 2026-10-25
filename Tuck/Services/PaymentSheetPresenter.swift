import StripePaymentSheet
import UIKit

/// Stripe PaymentSheet를 현재 화면 위에 모달로 띄운다. 카드 입력·3DS 인증은 Stripe가 처리하고,
/// 홈 화면(3D 방 포함)은 그대로 아래에 살아 있어 상태가 유지된다.
@MainActor
enum PaymentSheetPresenter {
    enum Outcome: Equatable {
        case completed
        case canceled
        case failed(String)
    }

    /// 테스트 모드 결제 완료 후 3DS 등 외부 인증에서 앱으로 돌아오는 주소.
    static let returnURL = "tuck://stripe-redirect"

    private static var sheet: PaymentSheet?

    static func present(_ params: PaymentParams) async -> Outcome {
        StripeAPI.defaultPublishableKey = Secrets.stripePublishableKey
        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = "Tuck (TEST MODE)"
        configuration.customer = .init(id: params.customerId, ephemeralKeySecret: params.ephemeralKeySecret)
        configuration.returnURL = returnURL
        configuration.allowsDelayedPaymentMethods = false
        configuration.appearance.colors.primary = UIColor(named: "TuckBrown") ?? .brown

        guard let presenter = topViewController() else { return .failed("Couldn't open the payment sheet.") }
        let paymentSheet = PaymentSheet(paymentIntentClientSecret: params.clientSecret, configuration: configuration)
        sheet = paymentSheet
        defer { sheet = nil }
        return await withCheckedContinuation { continuation in
            paymentSheet.present(from: presenter) { result in
                switch result {
                case .completed: continuation.resume(returning: .completed)
                case .canceled: continuation.resume(returning: .canceled)
                case .failed(let error): continuation.resume(returning: .failed(error.localizedDescription))
                }
            }
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
