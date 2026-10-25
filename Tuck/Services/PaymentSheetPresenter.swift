#if canImport(StripePaymentSheet) && !TUCK_NO_PAYMENTS
import StripePaymentSheet
#endif
import UIKit

/// Presents Stripe PaymentSheet as a modal over the current screen. Stripe handles card entry and 3DS authentication;
/// the Home screen (including the 3D room) stays alive underneath and keeps its state.
@MainActor
enum PaymentSheetPresenter {
    enum Outcome: Equatable {
        case completed
        case canceled
        case failed(String)
    }

    /// URL used to return to the app after test-mode payment or external authentication such as 3DS.
    static let returnURL = "tuck://stripe-redirect"

    static let unsupportedMessage = "Payments are not supported on this device."

    static var isSupported: Bool {
        #if canImport(StripePaymentSheet) && !TUCK_NO_PAYMENTS
        return Secrets.stripePublishableKey.hasPrefix("pk_") && Secrets.backendURL.host != "checkout-not-configured.invalid"
        #else
        return false
        #endif
    }

    static func handleURLCallback(_ url: URL) -> Bool {
        #if canImport(StripePaymentSheet) && !TUCK_NO_PAYMENTS
        return StripeAPI.handleURLCallback(with: url)
        #else
        return false
        #endif
    }

    #if canImport(StripePaymentSheet) && !TUCK_NO_PAYMENTS
    private static var sheet: PaymentSheet?

    static func present(_ params: PaymentParams) async -> Outcome {
        guard isSupported else { return .failed(unsupportedMessage) }
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
    #else
    static func present(_ params: PaymentParams) async -> Outcome { .failed(unsupportedMessage) }
    #endif

}
