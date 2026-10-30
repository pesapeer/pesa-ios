import XCTest
@testable import PesaCheckoutCore

final class PesaStringsTests: XCTestCase {
    private func entries(_ s: PesaStrings) -> [String: String] {
        Dictionary(uniqueKeysWithValues: Mirror(reflecting: s).children.map { ($0.label!, $0.value as! String) })
    }

    private func placeholders(_ text: String) -> Set<String> {
        let regex = try! NSRegularExpression(pattern: #"\{\w+\}"#)
        let range = NSRange(text.startIndex..., in: text)
        return Set(regex.matches(in: text, range: range).map { String(text[Range($0.range, in: text)!]) })
    }

    func testEveryLocaleHasEveryKeyAndTheSamePlaceholders() {
        let en = entries(.en)
        XCTAssertGreaterThan(en.count, 40)
        for strings in PesaStrings.all {
            let table = entries(strings)
            XCTAssertEqual(Set(table.keys), Set(en.keys), strings.tag)
            for (key, value) in table {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "\(strings.tag).\(key) is blank")
                XCTAssertEqual(placeholders(value), placeholders(en[key]!), "\(strings.tag).\(key) placeholders")
            }
        }
    }

    func testTranslationsAreNotEnglish() {
        let same: Set<String> = ["cvv", "cid", "expiryFormat", "emailPlaceholder"]
        let en = entries(.en)
        for strings in [PesaStrings.fr, .frCA, .zhHans] {
            for (key, value) in entries(strings) where !same.contains(key) {
                XCTAssertNotEqual(value, en[key], "\(strings.tag).\(key)")
            }
        }
    }

    func testQuebecOverridesFrench() {
        XCTAssertEqual(PesaStrings.frCA.tag, "fr-CA")
        XCTAssertEqual(PesaStrings.frCA.email, "Courriel pour votre reçu")
        XCTAssertEqual(PesaStrings.frCA.card, "Carte de crédit ou de débit")
        XCTAssertEqual(PesaStrings.frCA.cardNumber, PesaStrings.fr.cardNumber)
    }

    func testCloseTagsAreMapped() {
        let cases = ["en": "en", "en-GB": "en", "fr": "fr", "fr-FR": "fr", "fr-BE": "fr", "fr-CA": "fr-CA",
                     "fr_CA": "fr-CA", "FR-ca": "fr-CA", "zh": "zh-Hans", "zh-CN": "zh-Hans",
                     "zh-Hans-CN": "zh-Hans", "zh-Hant": "zh-Hans", "zh-TW": "zh-Hans"]
        for (tag, want) in cases { XCTAssertEqual(PesaStrings.supportedTag(tag), want, tag) }
        for tag in [nil, "", "de", "es-ES", "pt-BR"] { XCTAssertNil(PesaStrings.supportedTag(tag), tag ?? "nil") }
    }

    func testResolutionOrderIsHostThenSessionThenDeviceThenEnglish() {
        XCTAssertEqual(PesaStrings.resolve("fr-BE", session: "zh-Hans", device: "en-US").tag, "fr")
        XCTAssertEqual(PesaStrings.resolve(nil, session: "zh-Hans", device: "fr-FR").tag, "zh-Hans")
        XCTAssertEqual(PesaStrings.resolve("de", session: "zh", device: "fr-FR").tag, "zh-Hans")
        XCTAssertEqual(PesaStrings.resolve(nil, session: nil, device: "fr-CA").tag, "fr-CA")
        XCTAssertEqual(PesaStrings.resolve(nil, session: nil, device: "de-DE").tag, "en")
        XCTAssertEqual(PesaStrings.resolve(nil, session: nil, device: nil).tag, "en")
    }

    func testValidationMessagesFollowTheStrings() {
        XCTAssertEqual(CardValidation.number("", strings: .fr), "Saisissez le numéro de carte.")
        XCTAssertEqual(CardValidation.number("4111111111111112", strings: .zhHans), "请检查卡号。")
        XCTAssertEqual(CardValidation.securityCode("", brand: .visa, strings: .zhHans), "请输入安全码。")
        XCTAssertEqual(CardValidation.email("x", strings: .frCA), "Saisissez une adresse courriel.")
        XCTAssertEqual(CardValidation.number(""), "Enter the card number.", "English by default")
    }

    func testPayLabels() {
        XCTAssertEqual(PesaStrings.en.payLabel(amount: "2.00", currency: "GBP"), "Pay £2.00")
        XCTAssertEqual(PesaStrings.en.payLabel(amount: "2.00", currency: "GBP", last4: "0165"), "Pay £2.00 with •••• 0165")
        XCTAssertEqual(PesaStrings.zhHans.payLabel(amount: "2.00", currency: "GBP"), "支付 £2.00")
        XCTAssertEqual(PesaStrings.zhHans.payLabel(amount: "2.00", currency: "GBP", last4: "0165"), "使用 •••• 0165 支付 £2.00")
        for fr in [PesaStrings.fr, .frCA] {
            let label = fr.payLabel(amount: "2.00", currency: "GBP", last4: "0165")
            XCTAssertTrue(label.hasPrefix("Payer 2,00") && label.contains("£") && label.hasSuffix(" avec •••• 0165"), label)
        }
        XCTAssertEqual(PesaStrings.en.payLabel(amount: "soon", currency: "GBP"), "Pay soon GBP")
        XCTAssertEqual(PesaStrings.en.title("Pay", last4: "0165"), "Pay with •••• 0165")
        XCTAssertEqual(PesaStrings.fr.expiresOn("09/28"), "Expire fin 09/28")
    }

    func testErrorsAreInTheGivenLanguage() {
        let body = Data(#"{"error":{"code":"invalid_request","message":"Check the card number.","field":"cardNumber"}}"#.utf8)
        let e = PesaCheckoutClient.error(status: 400, body: body, strings: .fr)
        XCTAssertEqual(e.code, .invalidCard)
        XCTAssertEqual(e.message, PesaStrings.fr.numberInvalid)
        XCTAssertEqual(e.gatewayMessage, "Check the card number.")
        XCTAssertEqual(PesaStrings.zhHans.message(for: .transport), PesaStrings.zhHans.errorNetwork)
        XCTAssertEqual(PesaStrings.en.message(for: .invalidCard, field: "savedCard.token"), PesaStrings.en.errorSavedCard)
    }

    func testSessionReadsTheLocale() throws {
        let json = #"{"intentId":"int_1","state":"open","amount":"2.00","currency":"GBP","locale":"fr-CA"}"#
        XCTAssertEqual(try JSONDecoder().decode(CheckoutSession.self, from: Data(json.utf8)).locale, "fr-CA")
        let none = #"{"intentId":"int_1","state":"open","amount":"2.00","currency":"GBP"}"#
        XCTAssertNil(try JSONDecoder().decode(CheckoutSession.self, from: Data(none.utf8)).locale)
    }
}
