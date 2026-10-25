import Foundation
import Security

/// Older local Secrets files can omit checkout fields. Existing teammate fields take precedence.
protocol TuckCheckoutConfigurationProviding {
    static var backendURL: URL { get }
    static var stripePublishableKey: String { get }
}
extension TuckCheckoutConfigurationProviding {
    static var backendURL: URL { URL(string: "https://checkout-not-configured.invalid")! }
    static var stripePublishableKey: String { "" }
}
extension Secrets: TuckCheckoutConfigurationProviding {}

/// Client for the order backend (`backend/`). The Stripe secret key stays on the server; the app uses a device token.
actor CheckoutClient {
    enum CheckoutError: LocalizedError {
        case server(code: String, message: String)
        case invalidResponse
        case notConfigured

        var errorDescription: String? {
            switch self {
            case let .server(_, message): message
            case .notConfigured: "Payments are not supported on this device."
            case .invalidResponse: "The order service sent an unexpected response."
            }
        }
    }

    enum ConfirmOutcome {
        /// Continue payment with PaymentSheet.
        case pay(PaymentParams, OrderSnapshot)
        case alreadyPaid(OrderSnapshot)
        /// The server price changed, so the user must review the updated quote.
        case quoteChanged(OrderSnapshot)
    }

    private let baseURL: URL
    private var token: String?

    init(baseURL: URL = Secrets.backendURL) {
        self.baseURL = baseURL
        token = Keychain.read(Self.tokenKey)
    }

    func quote(productID: String, quantity: Int, budgetCents: Int?) async throws -> QuoteResponse {
        var body: [String: Any] = ["productId": productID, "quantity": quantity]
        if let budgetCents { body["budgetCents"] = budgetCents }
        return try decode(try await send("POST", "/v1/quotes", body: body).data)
    }

    func confirm(orderID: String, quoteHash: String) async throws -> ConfirmOutcome {
        let (data, status) = try await send("POST", "/v1/orders/\(orderID)/confirm", body: ["quoteHash": quoteHash],
                                            acceptedStatuses: [200, 409])
        if status == 409, let error = try? JSONDecoder().decode(ErrorBody.self, from: data), error.error != "quote_changed" {
            throw CheckoutError.server(code: error.error, message: error.message ?? "This order can't be placed right now.")
        }
        let snapshot: OrderSnapshot = try decode(data)
        if status == 409 { return .quoteChanged(snapshot) }
        if let payment = snapshot.payment { return .pay(payment, snapshot) }
        return .alreadyPaid(snapshot)
    }

    func order(id: String) async throws -> OrderSnapshot {
        try decode(try await send("GET", "/v1/orders/\(id)").data)
    }

    @discardableResult
    func cancel(orderID: String) async throws -> OrderSnapshot {
        try decode(try await send("POST", "/v1/orders/\(orderID)/cancel").data)
    }

    // MARK: - Transport

    private struct ErrorBody: Decodable {
        let error: String
        let message: String?
    }

    private static let tokenKey = "tuck.checkout.token"

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw CheckoutError.invalidResponse }
    }

    private func send(_ method: String, _ path: String, body: [String: Any]? = nil, acceptedStatuses: Set<Int> = [200],
                      retryingAuth: Bool = true) async throws -> (data: Data, status: Int) {
        guard baseURL.host != "checkout-not-configured.invalid" else { throw CheckoutError.notConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(try await authToken())", forHTTPHeaderField: "authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CheckoutError.invalidResponse }
        if http.statusCode == 401, retryingAuth {
            // Register again once if the server has lost the token (for example, after a test-server reset).
            token = nil
            Keychain.delete(Self.tokenKey)
            return try await send(method, path, body: body, acceptedStatuses: acceptedStatuses, retryingAuth: false)
        }
        guard acceptedStatuses.contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw CheckoutError.server(code: error?.error ?? "http_\(http.statusCode)",
                                       message: error?.message ?? "The order service is unavailable (\(http.statusCode)).")
        }
        return (data, http.statusCode)
    }

    private func authToken() async throws -> String {
        if let token { return token }
        var request = URLRequest(url: baseURL.appendingPathComponent("/v1/devices"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(DemoProfile.current)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 201,
              let registered = try? JSONDecoder().decode(Registration.self, from: data)
        else { throw CheckoutError.invalidResponse }
        token = registered.token
        Keychain.save(registered.token, for: Self.tokenKey)
        return registered.token
    }

    private struct Registration: Decodable { let token: String }
}

/// Default shipping address used until the profile screen is complete. The server preloads a test payment method.
struct DemoProfile: Encodable {
    let name: String
    let address: OrderAddress

    /// Matches the test card (`pm_card_visa`) attached to the customer when the server registers the device.
    static let card = CardSummary(brand: "visa", last4: "4242")

    static let current = DemoProfile(
        name: "Harper",
        address: OrderAddress(line1: "1 Market St", line2: nil, city: "San Francisco", state: "CA", postalCode: "94105", country: "US")
    )
}

/// Minimal Keychain wrapper for storing the anonymous device token.
private enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.hackathon.tuck", kSecAttrAccount as String: key]
    }

    static func read(_ key: String) -> String? {
        var item = query(key)
        item[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, for key: String) {
        delete(key)
        var item = query(key)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func delete(_ key: String) { SecItemDelete(query(key) as CFDictionary) }
}
