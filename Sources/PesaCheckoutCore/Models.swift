import Foundation

public enum WalletKind: String, Sendable {
    case applePay = "apple_pay"
    case googlePay = "google_pay"
}

public struct CheckoutMerchant: Decodable, Equatable, Sendable {
    public var displayName: String
    public var logoUrl: String?
    public var supportUrl: String?

    public init(displayName: String = "", logoUrl: String? = nil, supportUrl: String? = nil) {
        self.displayName = displayName
        self.logoUrl = logoUrl
        self.supportUrl = supportUrl
    }

    enum CodingKeys: String, CodingKey { case displayName, logoUrl, supportUrl }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        logoUrl = try c.decodeIfPresent(String.self, forKey: .logoUrl)
        supportUrl = try c.decodeIfPresent(String.self, forKey: .supportUrl)
    }
}

/// The latest card attempt on the intent.
public struct CheckoutAttempt: Decodable, Equatable, Sendable {
    /// pending, requires_3ds, authorized, captured, declined, failed,
    /// cancelled, refunded or unknown.
    public var state: String
    public var challengeUrl: URL?
    public var brand: String?
    public var last4: String?
    public var failureReason: String?
    public var declineCode: String?

    public init(state: String, challengeUrl: URL? = nil, brand: String? = nil, last4: String? = nil,
                failureReason: String? = nil, declineCode: String? = nil) {
        self.state = state
        self.challengeUrl = challengeUrl
        self.brand = brand
        self.last4 = last4
        self.failureReason = failureReason
        self.declineCode = declineCode
    }

    public var isPending: Bool { state == "pending" }
    public var requires3DS: Bool { state == "requires_3ds" }
    public var isSuccess: Bool { state == "captured" || state == "authorized" }

    enum CodingKeys: String, CodingKey { case state, challengeUrl, card, failureReason, declineCode }
    enum CardKeys: String, CodingKey { case brand, last4 }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? "unknown"
        challengeUrl = try c.decodeIfPresent(String.self, forKey: .challengeUrl).flatMap(URL.init(string:))
        failureReason = try c.decodeIfPresent(String.self, forKey: .failureReason).nonEmpty
        declineCode = try c.decodeIfPresent(String.self, forKey: .declineCode).nonEmpty
        if let card = try? c.nestedContainer(keyedBy: CardKeys.self, forKey: .card) {
            brand = try card.decodeIfPresent(String.self, forKey: .brand).nonEmpty
            last4 = try card.decodeIfPresent(String.self, forKey: .last4).nonEmpty
        }
    }
}

/// Whether the form asks the CVV again for a saved card. An unknown value
/// reads as `.optional`.
public enum SavedCardSecurityCode: String, Sendable {
    case required, optional, never
}

/// A card the customer kept on file. `token` is opaque: pass it to
/// `payWithSavedCard` and nowhere else.
public struct SavedCard: Decodable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public var token: String
    public var brand: String
    public var last4: String
    /// MM/YYYY.
    public var expiry: String
    public var holderName: String

    public init(token: String, brand: String = "", last4: String = "", expiry: String = "", holderName: String = "") {
        self.token = token
        self.brand = brand
        self.last4 = last4
        self.expiry = expiry
        self.holderName = holderName
    }

    public var cardBrand: CardBrand { CardBrand(rawValue: brand) ?? .unknown }

    public var description: String { "SavedCard(\(brand) •••• \(last4), \(expiry))" }
    public var debugDescription: String { description }

    enum CodingKeys: String, CodingKey { case token, brand, last4, expiry, holderName }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
        brand = try c.decodeIfPresent(String.self, forKey: .brand) ?? ""
        last4 = try c.decodeIfPresent(String.self, forKey: .last4) ?? ""
        expiry = try c.decodeIfPresent(String.self, forKey: .expiry) ?? ""
        holderName = try c.decodeIfPresent(String.self, forKey: .holderName) ?? ""
    }
}

/// `checkoutSession` from the contract: the intent as the checkout sees it.
public struct CheckoutSession: Decodable, Equatable, Sendable {
    public var intentId: String
    /// open, authorized, settled, expired or cancelled.
    public var state: String
    public var amount: String
    public var currency: String
    public var description: String
    public var descriptor: String
    public var merchant: CheckoutMerchant
    public var methods: [String]
    public var needsEmail: Bool
    public var returnUrl: URL?
    public var cancelUrl: URL?
    public var attempt: CheckoutAttempt?
    public var expiresAt: Date?
    public var canSaveCard: Bool
    /// Most recently used first; empty when there are none.
    public var savedCards: [SavedCard]
    public var savedCardSecurityCode: SavedCardSecurityCode

    public var isOpen: Bool { state == "open" }
    public var isClosed: Bool { ["settled", "authorized", "expired", "cancelled"].contains(state) }

    enum CodingKeys: String, CodingKey {
        case intentId, state, amount, currency, description, descriptor, merchant, methods, needsEmail
        case returnUrl, cancelUrl, attempt, expiresAt
        case canSaveCard, savedCards, savedCardSecurityCode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        intentId = try c.decodeIfPresent(String.self, forKey: .intentId) ?? ""
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? "open"
        amount = try c.decodeIfPresent(String.self, forKey: .amount) ?? ""
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        descriptor = try c.decodeIfPresent(String.self, forKey: .descriptor) ?? ""
        merchant = try c.decodeIfPresent(CheckoutMerchant.self, forKey: .merchant) ?? CheckoutMerchant()
        methods = try c.decodeIfPresent([String].self, forKey: .methods) ?? ["card"]
        needsEmail = try c.decodeIfPresent(Bool.self, forKey: .needsEmail) ?? false
        returnUrl = try c.decodeIfPresent(String.self, forKey: .returnUrl).nonEmpty.flatMap(URL.init(string:))
        cancelUrl = try c.decodeIfPresent(String.self, forKey: .cancelUrl).nonEmpty.flatMap(URL.init(string:))
        attempt = try c.decodeIfPresent(CheckoutAttempt.self, forKey: .attempt)
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt).flatMap(ISO8601.parse)
        canSaveCard = try c.decodeIfPresent(Bool.self, forKey: .canSaveCard) ?? false
        savedCards = try c.decodeIfPresent([SavedCard].self, forKey: .savedCards) ?? []
        savedCardSecurityCode = try c.decodeIfPresent(String.self, forKey: .savedCardSecurityCode)
            .flatMap(SavedCardSecurityCode.init(rawValue:)) ?? .optional
    }
}

/// What the SDK saw. The app shows it; the app's backend does not trust it.
public struct CheckoutResult: Equatable, Sendable {
    public let intentId: String
    /// The intent's state as last read: settled or authorized on success,
    /// open after a decline (the payer may try again), expired or cancelled.
    public let state: String
    public let attempt: CheckoutAttempt?

    public init(intentId: String, state: String, attempt: CheckoutAttempt?) {
        self.intentId = intentId
        self.state = state
        self.attempt = attempt
    }

    public var isSuccess: Bool { state == "settled" || state == "authorized" }
    public var isDeclined: Bool { attempt?.state == "declined" || attempt?.state == "failed" }
    /// Plain-language reason safe to show, when the payment did not go through.
    public var failureReason: String? { attempt?.failureReason }
}

/// A refusal from the checkout edge or the gateway, or a transport failure.
public struct PesaCheckoutError: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Code: String, Sendable {
        case invalidCard = "invalid_card"
        case invalidRequest = "invalid_request"
        case notFound = "not_found"
        case attemptInProgress = "attempt_in_progress"
        case intentClosed = "intent_closed"
        case rateLimited = "rate_limited"
        case server
        case transport
        case timeout
        case pinMismatch = "pin_mismatch"
        case challengeUnavailable = "challenge_unavailable"
        case notImplemented = "not_implemented"
    }

    public let code: Code
    /// The gateway's own code when it sent one (card_state, intent_closed…),
    /// for support conversations.
    public let gatewayCode: String?
    public let message: String
    public let status: Int?
    public let field: String?

    public init(_ code: Code, _ message: String, gatewayCode: String? = nil, status: Int? = nil, field: String? = nil) {
        self.code = code
        self.gatewayCode = gatewayCode
        self.message = message
        self.status = status
        self.field = field
    }

    public var description: String {
        "PesaCheckoutError(\(code.rawValue)\(status.map { ", \($0)" } ?? "")): \(message)"
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let s = self, !s.isEmpty else { return nil }
        return s
    }
}

enum ISO8601 {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    static func parse(_ s: String) -> Date? {
        fractional.date(from: s) ?? plain.date(from: s)
    }
}
