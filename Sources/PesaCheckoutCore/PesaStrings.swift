import Foundation

/// Every sentence the SDK shows, in one language. The SDK ships `.en`,
/// `.fr`, `.frCA` and `.zhHans`. Get one with `resolve(_:session:)`. A host
/// may copy one and change a sentence.
///
/// Templates hold named placeholders such as `{amount}`. Use the functions
/// below to fill them.
public struct PesaStrings: Equatable, Sendable {
    /// The BCP 47 tag of this table, such as `fr-CA`. Money is formatted for it.
    public var tag: String
    /// The card payment method, and the name of a card of unknown brand.
    public var card: String
    public var cardNumber: String
    public var expiry: String
    public var expiryFormat: String
    public var cvv: String
    public var cid: String
    public var holderName: String
    public var holderNamePlaceholder: String
    public var email: String
    public var emailPlaceholder: String
    public var securityCode: String
    public var securityCodeOptional: String
    /// `{date}`
    public var expires: String
    public var expired: String
    /// `{brand}`, `{last4}`, `{date}`
    public var savedCardLabel: String
    /// `{brand}`, `{last4}`
    public var savedCardExpiredLabel: String
    public var useAnotherCard: String
    public var saveCard: String
    public var payButton: String
    /// `{amount}`
    public var pay: String
    /// `{amount}`, `{last4}`
    public var payWithSavedCard: String
    /// `{title}`, `{last4}`
    public var titleWithSavedCard: String
    public var processing: String
    public var numberEmpty: String
    public var numberDigitsOnly: String
    public var numberInvalid: String
    public var expiryInvalid: String
    public var cardExpired: String
    public var securityCodeEmpty: String
    public var securityCodeInvalid: String
    public var holderNameLength: String
    public var emailInvalid: String
    public var errorInvalidCard: String
    public var errorSavedCard: String
    public var errorInvalidRequest: String
    public var errorNotFound: String
    public var errorIntentClosed: String
    public var errorAttemptInProgress: String
    public var errorRateLimited: String
    public var errorNetwork: String
    public var errorPinMismatch: String
    public var errorTimeout: String
    public var errorChallengeUnavailable: String
    public var errorServer: String
    public var errorNotImplemented: String

    public static let all: [PesaStrings] = [.en, .fr, .frCA, .zhHans]

    /// The shipped tag for `tag`, or nil when the SDK has no table for it.
    /// Close tags are mapped: `fr-BE` to `fr`, `fr_CA` to `fr-CA`, any `zh`
    /// (`zh-CN`, `zh-Hant`) to `zh-Hans`, `en-GB` to `en`.
    public static func supportedTag(_ tag: String?) -> String? {
        guard let tag else { return nil }
        let parts = tag.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "_", with: "-")
            .lowercased().split(separator: "-").map(String.init)
        switch parts.first {
        case "en": return "en"
        case "fr": return parts.dropFirst().contains("ca") ? "fr-CA" : "fr"
        case "zh": return "zh-Hans"
        default: return nil
        }
    }

    /// The first table found for: `locale` from the host, then the
    /// session's locale, then the device, then English.
    public static func resolve(_ locale: String? = nil, session: String? = nil) -> PesaStrings {
        resolve(locale, session: session, device: Locale.preferredLanguages.first)
    }

    static func resolve(_ locale: String?, session: String?, device: String?) -> PesaStrings {
        switch supportedTag(locale) ?? supportedTag(session) ?? supportedTag(device) {
        case "fr": return .fr
        case "fr-CA": return .frCA
        case "zh-Hans": return .zhHans
        default: return .en
        }
    }

    /// `amount` (a decimal string such as `2.00`) in `currency`, formatted by
    /// Foundation for `tag`.
    public func formatAmount(_ amount: String, currency: String) -> String {
        let fallback = "\(amount) \(currency)"
        guard amount.range(of: #"^-?[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let number = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) else { return fallback }
        let format = NumberFormatter()
        format.numberStyle = .currency
        format.locale = Locale(identifier: tag)
        format.currencyCode = currency.uppercased()
        return format.string(from: NSDecimalNumber(decimal: number)) ?? fallback
    }

    /// "Pay £2.00", or "Pay £2.00 with •••• 0165" when `last4` is set.
    public func payLabel(amount: String, currency: String, last4: String? = nil) -> String {
        let money = formatAmount(amount, currency: currency)
        guard let last4 else { return pay.fill(["amount": money]) }
        return payWithSavedCard.fill(["amount": money, "last4": last4])
    }

    /// `title` followed by the saved card, as "Pay £1.00 with •••• 0165".
    public func title(_ title: String, last4: String) -> String {
        titleWithSavedCard.fill(["title": title, "last4": last4])
    }

    public func expiresOn(_ date: String) -> String { expires.fill(["date": date]) }

    /// The spoken name of a saved card row. Nil `expiry` reads as expired.
    public func savedCardAccessibilityLabel(brand: String, last4: String, expiry: String?) -> String {
        guard let expiry else { return savedCardExpiredLabel.fill(["brand": brand, "last4": last4]) }
        return savedCardLabel.fill(["brand": brand, "last4": last4, "date": expiry])
    }

    /// The brand's name, or `card` for an unknown brand.
    public func brandName(_ brand: CardBrand) -> String { brand == .unknown ? card : brand.label }

    /// The sentence for an SDK error. `field` is the gateway's field for
    /// `.invalidCard`.
    public func message(for code: PesaCheckoutError.Code, field: String? = nil) -> String {
        switch code {
        case .invalidCard:
            switch field ?? "" {
            case "cardNumber": return numberInvalid
            case "expiryMonth", "expiryYear": return expiryInvalid
            case "securityCode", "savedCard.securityCode": return securityCodeInvalid
            case "holderName": return holderNameLength
            case "email": return emailInvalid
            case "savedCard.token": return errorSavedCard
            default: return errorInvalidCard
            }
        case .invalidRequest: return errorInvalidRequest
        case .notFound: return errorNotFound
        case .attemptInProgress: return errorAttemptInProgress
        case .intentClosed: return errorIntentClosed
        case .rateLimited: return errorRateLimited
        case .server: return errorServer
        case .transport: return errorNetwork
        case .timeout: return errorTimeout
        case .pinMismatch: return errorPinMismatch
        case .challengeUnavailable: return errorChallengeUnavailable
        case .notImplemented: return errorNotImplemented
        }
    }
}

extension String {
    func fill(_ values: [String: String]) -> String {
        values.reduce(self) { text, item in text.replacingOccurrences(of: "{\(item.key)}", with: item.value) }
    }
}
