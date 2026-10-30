import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends one HTTP request. `URLSessionTransport` is the real one; tests
/// inject a fake.
public protocol CheckoutTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// How the client reaches the checkout edge.
public struct PesaCheckoutConfiguration: Sendable {
    public var checkoutURL: URL
    /// SPKI pins of checkout.pesa.co (base64 SHA-256). Production builds set
    /// both current pins; an empty list turns pinning off and is for
    /// development against a local edge only.
    public var pins: [String]
    public var pollInterval: TimeInterval
    public var pollTries: Int
    public var challengeCeiling: TimeInterval
    public var requestTimeout: TimeInterval
    /// The language of error messages, such as `fr`. Nil follows the
    /// session's `locale`, then the device. See `PesaStrings.resolve`.
    public var locale: String?

    public init(checkoutURL: URL = URL(string: "https://checkout.pesa.co")!,
                pins: [String] = [],
                pollInterval: TimeInterval = 1.5,
                pollTries: Int = 60,
                challengeCeiling: TimeInterval = 300,
                requestTimeout: TimeInterval = 30,
                locale: String? = nil) {
        self.checkoutURL = checkoutURL
        self.pins = pins
        self.pollInterval = pollInterval
        self.pollTries = pollTries
        self.challengeCeiling = challengeCeiling
        self.requestTimeout = requestTimeout
        self.locale = locale
    }
}

/// Talks to the checkout edge for one app. Create one and keep it.
public final class PesaCheckoutClient: Sendable {
    public let configuration: PesaCheckoutConfiguration
    private let transport: CheckoutTransport
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let now: @Sendable () -> Date

    public init(configuration: PesaCheckoutConfiguration = .init()) {
        self.configuration = configuration
        self.transport = URLSessionTransport(configuration: configuration)
        self.sleep = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
        self.now = { Date() }
    }

    /// For tests: a transport of your own, and a clock that does not wait.
    public init(configuration: PesaCheckoutConfiguration,
                transport: CheckoutTransport,
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.configuration = configuration
        self.transport = transport
        self.sleep = sleep
        self.now = now
    }

    /// Reads the intent as the checkout sees it.
    public func session(intentId: String, clientSecret: String) async throws -> CheckoutSession {
        var req = URLRequest(url: url(intentId, "/session"))
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(clientSecret, forHTTPHeaderField: "X-Client-Secret")
        return try await decode(send(req))
    }

    /// Charges `card` against the intent and follows it to an outcome: polls
    /// the session, hands the 3-D Secure challenge URL to `openChallenge`
    /// once when the issuer asks, and returns when the attempt is no longer
    /// pending. The card is wiped once the request is encoded.
    public func payWithCard(intentId: String,
                            clientSecret: String,
                            card: CardDetails,
                            email: String? = nil,
                            saveCard: Bool = false,
                            openChallenge: @escaping @Sendable (URL) async -> Bool) async throws -> CheckoutResult {
        defer { card.wipe() }
        var body: [String: Any] = [
            "clientSecret": clientSecret,
            "expiryMonth": card.expiry.month,
            "expiryYear": card.expiry.year,
            "holderName": card.holderName,
        ]
        card.number.withString { body["cardNumber"] = $0 }
        card.securityCode.withString { body["securityCode"] = $0 }
        if let email = email?.trimmingCharacters(in: .whitespaces), !email.isEmpty { body["email"] = email }
        if saveCard { body["saveCard"] = true }
        var req = try cardRequest(intentId: intentId, clientSecret: clientSecret, body: body)
        body.removeAll()
        let first: CheckoutSession = try await decode(send(req))
        req.httpBody = nil
        return try await follow(intentId: intentId, clientSecret: clientSecret, first: first, openChallenge: openChallenge)
    }

    /// Charges one of the session's `savedCards` and follows it to an
    /// outcome, as `payWithCard` does. Pass `securityCode` when
    /// `savedCardSecurityCode` is `.required`, or when the payer typed one.
    /// It is wiped once the request is encoded.
    public func payWithSavedCard(intentId: String,
                                 clientSecret: String,
                                 token: String,
                                 securityCode: SecretBytes? = nil,
                                 email: String? = nil,
                                 openChallenge: @escaping @Sendable (URL) async -> Bool) async throws -> CheckoutResult {
        defer { securityCode?.wipe() }
        var savedCard: [String: Any] = ["token": token]
        if let securityCode, !securityCode.isEmpty { securityCode.withString { savedCard["securityCode"] = $0 } }
        var body: [String: Any] = ["clientSecret": clientSecret, "savedCard": savedCard]
        if let email = email?.trimmingCharacters(in: .whitespaces), !email.isEmpty { body["email"] = email }
        var req = try cardRequest(intentId: intentId, clientSecret: clientSecret, body: body)
        savedCard.removeAll()
        body.removeAll()
        let first: CheckoutSession = try await decode(send(req))
        req.httpBody = nil
        return try await follow(intentId: intentId, clientSecret: clientSecret, first: first, openChallenge: openChallenge)
    }

    private func cardRequest(intentId: String, clientSecret: String, body: [String: Any]) throws -> URLRequest {
        var req = URLRequest(url: url(intentId, "/card"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(clientSecret, forHTTPHeaderField: "X-Client-Secret")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// Apple Pay. Phase 2: the PassKit token goes to `POST /c/{intent}/wallet`.
    public func payWithWallet(intentId: String, clientSecret: String, wallet: WalletKind) async throws -> CheckoutResult {
        throw PesaCheckoutError(.notImplemented, strings().errorNotImplemented)
    }

    private func follow(intentId: String, clientSecret: String, first: CheckoutSession,
                        openChallenge: @Sendable (URL) async -> Bool) async throws -> CheckoutResult {
        var s = first
        var tries = 0
        var challengeStarted: Date?
        while true {
            let a = s.attempt
            if a == nil || !(a!.isPending || a!.requires3DS) || s.isClosed {
                return CheckoutResult(intentId: intentId, state: s.state, attempt: a)
            }
            if let a, a.requires3DS, let url = a.challengeUrl, challengeStarted == nil {
                challengeStarted = now()
                guard await openChallenge(url) else {
                    throw PesaCheckoutError(.challengeUnavailable, strings(s).errorChallengeUnavailable)
                }
            }
            tries += 1
            let over = challengeStarted.map { now().timeIntervalSince($0) > configuration.challengeCeiling }
                ?? (tries >= configuration.pollTries)
            if over {
                throw PesaCheckoutError(.timeout, strings(s).errorTimeout)
            }
            try await sleep(configuration.pollInterval)
            s = try await session(intentId: intentId, clientSecret: clientSecret)
        }
    }

    /// The client's language: the configured locale, then the session's,
    /// then the device.
    private func strings(_ session: CheckoutSession? = nil) -> PesaStrings {
        PesaStrings.resolve(configuration.locale, session: session?.locale)
    }

    private func url(_ intentId: String, _ suffix: String) -> URL {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let id = intentId.addingPercentEncoding(withAllowedCharacters: unreserved) ?? intentId
        var base = configuration.checkoutURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: "\(base)/c/\(id)\(suffix)")!
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let e as PesaCheckoutError {
            throw e
        } catch let e as URLError where e.code == .serverCertificateUntrusted || e.code == .cancelled {
            throw PesaCheckoutError(.pinMismatch, strings().errorPinMismatch)
        } catch {
            throw PesaCheckoutError(.transport, strings().errorNetwork)
        }
        if (200..<300).contains(response.statusCode) { return data }
        throw Self.error(status: response.statusCode, body: data, strings: strings())
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PesaCheckoutError(.transport, strings().errorServer)
        }
    }

    static func error(status: Int, body: Data, strings: PesaStrings = .en) -> PesaCheckoutError {
        var gatewayCode: String?
        var gatewayMessage: String?
        var field: String?
        if let j = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            let e = (j["error"] as? [String: Any]) ?? j
            gatewayCode = e["code"] as? String
            gatewayMessage = e["message"] as? String
            field = e["field"] as? String
        }
        let cardFields: Set<String> = ["cardNumber", "expiryMonth", "expiryYear", "securityCode", "holderName", "email",
                                       "savedCard.token", "savedCard.securityCode"]
        let code: PesaCheckoutError.Code
        switch status {
        case 400, 422: code = field.map(cardFields.contains) == true ? .invalidCard : .invalidRequest
        case 401, 403, 404: code = .notFound
        case 409: code = gatewayCode == "intent_closed" ? .intentClosed : .attemptInProgress
        case 410: code = .intentClosed
        case 429: code = .rateLimited
        case 500...: code = .server
        default: code = .invalidRequest
        }
        return PesaCheckoutError(code, strings.message(for: code, field: field), gatewayCode: gatewayCode,
                                 gatewayMessage: gatewayMessage, status: status, field: field)
    }
}

/// The production transport: one URLSession, pinned when pins are set.
public final class URLSessionTransport: NSObject, CheckoutTransport, @unchecked Sendable {
    private let session: URLSession
    private let timeout: TimeInterval

    public init(configuration: PesaCheckoutConfiguration) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = configuration.requestTimeout
        cfg.httpAdditionalHeaders = ["User-Agent": "PesaCheckout-iOS/\(PesaCheckoutVersion.current)"]
        timeout = configuration.requestTimeout
        #if canImport(Security) && !os(Linux)
        let delegate = configuration.pins.isEmpty ? nil : PinningDelegate(pins: configuration.pins, host: configuration.checkoutURL.host ?? "")
        session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        #else
        session = URLSession(configuration: cfg)
        #endif
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.timeoutInterval = timeout
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PesaCheckoutError(.transport, PesaStrings.resolve().errorServer)
        }
        return (data, http)
    }
}

public enum PesaCheckoutVersion {
    public static let current = "0.3.0"
}
