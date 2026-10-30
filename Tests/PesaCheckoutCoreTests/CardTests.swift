import XCTest
@testable import PesaCheckoutCore

final class CardTests: XCTestCase {
    func testBrandDetection() {
        XCTAssertEqual(CardBrand.detect("4111111111111111"), .visa)
        XCTAssertEqual(CardBrand.detect("5555555555554444"), .mastercard)
        XCTAssertEqual(CardBrand.detect("2221000000000009"), .mastercard)
        XCTAssertEqual(CardBrand.detect("378282246310005"), .amex)
        XCTAssertEqual(CardBrand.detect("6200000000000005"), .unionpay)
        XCTAssertEqual(CardBrand.detect("3"), .unknown)
        XCTAssertEqual(CardBrand.detect(""), .unknown)
    }

    func testLuhnAndNumberMessages() {
        XCTAssertTrue(CardValidation.luhn("4111111111111111"))
        XCTAssertFalse(CardValidation.luhn("4111111111111112"))
        XCTAssertNil(CardValidation.number("4111 1111 1111 1111"))
        XCTAssertEqual(CardValidation.number(""), "Enter the card number.")
        XCTAssertEqual(CardValidation.number("41x1"), "Digits only.")
        XCTAssertEqual(CardValidation.number("4111111111111112"), "Check the card number.")
        XCTAssertEqual(CardValidation.number("378282246310005"), nil)
        XCTAssertEqual(CardValidation.number("37828224631000"), "Check the card number.")
    }

    func testExpiryParsing() {
        XCTAssertEqual(CardExpiry.parse("12/28"), CardExpiry(month: 12, year: 2028))
        XCTAssertEqual(CardExpiry.parse("1228"), CardExpiry(month: 12, year: 2028))
        XCTAssertEqual(CardExpiry.parse("12/2028"), CardExpiry(month: 12, year: 2028))
        XCTAssertNil(CardExpiry.parse("13/28"))
        XCTAssertNil(CardExpiry.parse("1/28"))
        let now = ISO8601DateFormatter().date(from: "2026-10-24T00:00:00Z")!
        XCTAssertNil(CardValidation.expiry("10/26", now: now))
        XCTAssertEqual(CardValidation.expiry("09/26", now: now), "This card has expired.")
        XCTAssertEqual(CardValidation.expiry("9/26", now: now), "Use MM/YY.")
    }

    func testSecurityCodeByBrand() {
        XCTAssertNil(CardValidation.securityCode("123", brand: .visa))
        XCTAssertEqual(CardValidation.securityCode("1234", brand: .visa), "Check the security code.")
        XCTAssertNil(CardValidation.securityCode("1234", brand: .amex))
        XCTAssertNil(CardValidation.securityCode("123", brand: .unknown))
        XCTAssertNil(CardValidation.securityCode("1234", brand: .unknown))
        XCTAssertEqual(CardValidation.securityCode("", brand: .visa), "Enter the security code.")
    }

    func testHolderAndEmail() {
        XCTAssertNil(CardValidation.holderName("Ada Lovelace"))
        XCTAssertNotNil(CardValidation.holderName("Al"))
        XCTAssertNotNil(CardValidation.holderName(String(repeating: "a", count: 27)))
        XCTAssertNil(CardValidation.email("a@b.co"))
        XCTAssertNotNil(CardValidation.email("ab.co"))
    }

    func testFormatting() {
        XCTAssertEqual(CardValidation.format("4111111111111111", brand: .visa), "4111 1111 1111 1111")
        XCTAssertEqual(CardValidation.format("378282246310005", brand: .amex), "3782 822463 10005")
        XCTAssertEqual(CardValidation.format("41", brand: .visa), "41")
        XCTAssertEqual(CardValidation.format("6200000000000005123", brand: .unionpay), "6200 0000 0000 0005 123")
    }

    func testCardDetailsWipes() {
        let card = CardDetails(number: "4111 1111 1111 1111", expiry: CardExpiry(month: 12, year: 2028),
                               securityCode: " 123 ", holderName: " Ada Lovelace ")
        XCTAssertEqual(card.brand, .visa)
        XCTAssertEqual(card.last4, "1111")
        XCTAssertEqual(card.holderName, "Ada Lovelace")
        card.number.withString { XCTAssertEqual($0, "4111111111111111") }
        card.securityCode.withString { XCTAssertEqual($0, "123") }
        card.wipe()
        XCTAssertTrue(card.number.isEmpty)
        XCTAssertTrue(card.securityCode.isEmpty)
        card.number.withString { XCTAssertEqual($0, "") }
    }

    func testBrandFromItsName() {
        for name in ["visa", "VISA", " Visa "] { XCTAssertEqual(CardBrand.parse(name), .visa, name) }
        for name in ["mastercard", "MasterCard", "master_card", "master-card", "mc", "MC"] { XCTAssertEqual(CardBrand.parse(name), .mastercard, name) }
        for name in ["amex", "AMEX", "americanexpress", "American Express", "american_express"] { XCTAssertEqual(CardBrand.parse(name), .amex, name) }
        for name in ["unionpay", "UnionPay", "union-pay", "cup", "CUP", "chinaunionpay", "China UnionPay"] { XCTAssertEqual(CardBrand.parse(name), .unionpay, name) }
        for name in ["", "diners", "card", "visa electron"] { XCTAssertEqual(CardBrand.parse(name), .unknown, name) }
    }

    func testSavedCardExpiry() {
        let card = SavedCard(token: "t", brand: "visa", last4: "0165", expiry: "09/2028")
        XCTAssertEqual(card.shortExpiry, "09/28")
        XCTAssertTrue(card.isUsable(at: utc(2028, 9, 30)), "usable through its expiry month")
        XCTAssertFalse(card.isUsable(at: utc(2028, 10, 1)))
        XCTAssertEqual(SavedCard(token: "t", expiry: "soon").shortExpiry, "soon")
        XCTAssertTrue(SavedCard(token: "t", expiry: "soon").isUsable(at: utc(2030, 1, 1)), "an unparsed expiry is left to the gateway")
    }

    private func utc(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }
}
