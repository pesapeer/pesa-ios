import Foundation

/// A card scheme, as the gateway names it.
public enum CardBrand: String, Sendable, CaseIterable {
    case visa, mastercard, amex, unionpay
    case unknown = "card"

    public var label: String {
        switch self {
        case .visa: return "Visa"
        case .mastercard: return "Mastercard"
        case .amex: return "American Express"
        case .unionpay: return "UnionPay"
        case .unknown: return "Card"
        }
    }

    public var minLength: Int { self == .amex ? 15 : self == .unknown ? 13 : 16 }
    public var maxLength: Int {
        switch self {
        case .amex: return 15
        case .visa, .mastercard: return 16
        case .unionpay, .unknown: return 19
        }
    }
    public var cvvLength: Int { self == .amex ? 4 : 3 }

    /// Where spaces go when the number is shown.
    public var groups: [Int] { self == .amex ? [4, 6, 5] : [4, 4, 4, 4, 3] }

    /// Reads a brand as the gateway or an acquirer names it, in any case and
    /// with or without spaces, `_` or `-`.
    public static func parse(_ name: String) -> CardBrand {
        switch name.lowercased().filter({ $0 != " " && $0 != "_" && $0 != "-" }) {
        case "visa": return .visa
        case "mastercard", "mc": return .mastercard
        case "amex", "americanexpress": return .amex
        case "unionpay", "cup", "chinaunionpay": return .unionpay
        default: return .unknown
        }
    }

    /// Detects the brand from the digits typed so far.
    public static func detect(_ digits: String) -> CardBrand {
        guard let first = digits.first else { return .unknown }
        if first == "4" { return .visa }
        if digits.count >= 2, let two = Int(digits.prefix(2)) {
            if two == 34 || two == 37 { return .amex }
            if (51...55).contains(two) { return .mastercard }
            if two == 62 { return .unionpay }
        }
        if digits.count >= 4, let four = Int(digits.prefix(4)), (2221...2720).contains(four) {
            return .mastercard
        }
        return .unknown
    }
}

/// A card expiry, month and four-digit year.
public struct CardExpiry: Equatable, Sendable {
    public let month: Int
    public let year: Int

    public init(month: Int, year: Int) {
        self.month = month
        self.year = year
    }

    /// Parses "MM/YY", "MM/YYYY", "MMYY" or "MMYYYY".
    public static func parse(_ text: String) -> CardExpiry? {
        let digits = text.filter(\.isNumber)
        guard digits.count == 4 || digits.count == 6,
              let month = Int(digits.prefix(2)), var year = Int(digits.dropFirst(2)) else { return nil }
        if digits.count == 4 { year += 2000 }
        guard (1...12).contains(month) else { return nil }
        return CardExpiry(month: month, year: year)
    }

    /// Whether the card is still valid in the month of `now`.
    public func isValid(at now: Date = Date()) -> Bool {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: now)
        let y = parts.year ?? 0, m = parts.month ?? 0
        return year > y || (year == y && month >= m)
    }
}

/// Bytes that are overwritten when no longer needed. Swift strings are
/// copied freely and cannot be scrubbed; the card number and security code
/// live here until the request is encoded, then `wipe()` zeroes them.
public final class SecretBytes: @unchecked Sendable {
    private var bytes: [UInt8]

    public init(_ text: String) {
        bytes = Array(text.utf8)
    }

    public var isEmpty: Bool { bytes.isEmpty }
    public var count: Int { bytes.count }

    /// Hands the bytes to `body` as a string that lives only for the call.
    public func withString<T>(_ body: (String) throws -> T) rethrows -> T {
        try body(String(decoding: bytes, as: UTF8.self))
    }

    public func wipe() {
        for i in bytes.indices { bytes[i] = 0 }
        bytes.removeAll(keepingCapacity: false)
    }

    deinit { wipe() }
}

/// What the cardholder typed. Lives in memory until the client has sent it;
/// `wipe()` is called by the client once the request is encoded.
public final class CardDetails: @unchecked Sendable {
    public let number: SecretBytes
    public let expiry: CardExpiry
    public let securityCode: SecretBytes
    public let holderName: String
    public let brand: CardBrand
    public let last4: String

    public init(number: String, expiry: CardExpiry, securityCode: String, holderName: String) {
        let digits = number.filter { !$0.isWhitespace }
        self.number = SecretBytes(digits)
        self.expiry = expiry
        self.securityCode = SecretBytes(securityCode.trimmingCharacters(in: .whitespaces))
        self.holderName = holderName.trimmingCharacters(in: .whitespaces)
        self.brand = CardBrand.detect(digits)
        self.last4 = String(digits.suffix(4))
    }

    public func wipe() {
        number.wipe()
        securityCode.wipe()
    }
}

/// The checks the form applies. They mirror the gateway's; the gateway's
/// answer is the one that counts.
public enum CardValidation {
    public static func allDigits(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
    }

    public static func luhn(_ digits: String) -> Bool {
        guard allDigits(digits) else { return false }
        var sum = 0
        var double = false
        for byte in digits.utf8.reversed() {
            var d = Int(byte) - 0x30
            if double {
                d *= 2
                if d > 9 { d -= 9 }
            }
            sum += d
            double.toggle()
        }
        return sum % 10 == 0
    }

    /// Nil when the number is acceptable, else a message for the field in
    /// `strings`. Each check below works the same way.
    public static func number(_ raw: String, strings: PesaStrings = .en) -> String? {
        let digits = raw.filter { !$0.isWhitespace }
        if digits.isEmpty { return strings.numberEmpty }
        if !allDigits(digits) { return strings.numberDigitsOnly }
        let brand = CardBrand.detect(digits)
        if digits.count < brand.minLength || digits.count > brand.maxLength { return strings.numberInvalid }
        if !luhn(digits) { return strings.numberInvalid }
        return nil
    }

    public static func expiry(_ raw: String, now: Date = Date(), strings: PesaStrings = .en) -> String? {
        guard let parsed = CardExpiry.parse(raw) else { return strings.expiryInvalid }
        if !parsed.isValid(at: now) { return strings.cardExpired }
        return nil
    }

    public static func securityCode(_ raw: String, brand: CardBrand, strings: PesaStrings = .en) -> String? {
        if !allDigits(raw) { return strings.securityCodeEmpty }
        let lenient = brand == .unknown && (raw.count == 3 || raw.count == 4)
        if raw.count != brand.cvvLength && !lenient { return strings.securityCodeInvalid }
        return nil
    }

    public static func holderName(_ raw: String, strings: PesaStrings = .en) -> String? {
        let name = raw.trimmingCharacters(in: .whitespaces)
        if name.count < 3 || name.count > 26 { return strings.holderNameLength }
        return nil
    }

    public static func email(_ raw: String, strings: PesaStrings = .en) -> String? {
        let e = raw.trimmingCharacters(in: .whitespaces)
        if e.isEmpty || !e.contains("@") || e.count > 50 { return strings.emailInvalid }
        return nil
    }

    /// Groups the digits with spaces for display.
    public static func format(_ digits: String, brand: CardBrand) -> String {
        var out = ""
        var rest = Substring(digits)
        for g in brand.groups where !rest.isEmpty {
            if !out.isEmpty { out += " " }
            out += rest.prefix(g)
            rest = rest.dropFirst(g)
        }
        return out
    }
}
