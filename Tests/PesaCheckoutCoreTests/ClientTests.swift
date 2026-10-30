import XCTest
@testable import PesaCheckoutCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A fake checkout edge: scripted answers per route, in order.
final class FakeEdge: CheckoutTransport, @unchecked Sendable {
    struct Step {
        let status: Int
        let body: String
    }

    private let lock = NSLock()
    private(set) var requests: [URLRequest] = []
    private(set) var bodies: [[String: Any]] = []
    var card: [Step] = []
    var sessions: [Step] = []

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
        let path = request.url!.path
        let step: Step
        if path.hasSuffix("/card") {
            if let body = request.httpBody, let j = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                bodies.append(j)
            }
            guard !card.isEmpty else { throw URLError(.badServerResponse) }
            step = card.removeFirst()
        } else {
            guard !sessions.isEmpty else { throw URLError(.badServerResponse) }
            step = sessions.count == 1 ? sessions[0] : sessions.removeFirst()
        }
        let resp = HTTPURLResponse(url: request.url!, statusCode: step.status, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        return (Data(step.body.utf8), resp)
    }
}

func session(state: String = "open", attempt: String? = nil, extra: String = "") -> String {
    let a = attempt.map { ", \"attempt\": \($0)" } ?? ""
    return """
    {"intentId":"int_1","state":"\(state)","amount":"25.00","currency":"GBP","description":"Order 42",
     "merchant":{"displayName":"Shop"},"methods":["card"],"needsEmail":false,
     "returnUrl":"https://shop.example/done","expiresAt":"2026-10-24T10:00:00Z"\(a)\(extra)}
    """
}

func attempt(_ state: String, challenge: Bool = false, reason: String? = nil, code: String? = nil) -> String {
    var s = "{\"state\":\"\(state)\",\"card\":{\"brand\":\"visa\",\"last4\":\"1111\"}"
    if challenge { s += ",\"challengeUrl\":\"https://checkout.pesa.co/c/int_1/challenge?t=s\"" }
    if let reason { s += ",\"failureReason\":\"\(reason)\"" }
    if let code { s += ",\"declineCode\":\"\(code)\"" }
    return s + "}"
}

final class ClientTests: XCTestCase {
    private func client(_ edge: FakeEdge, tries: Int = 60, now: @escaping @Sendable () -> Date = { Date() }) -> PesaCheckoutClient {
        PesaCheckoutClient(configuration: .init(checkoutURL: URL(string: "https://checkout.test")!, pollTries: tries),
                           transport: edge, sleep: { _ in }, now: now)
    }

    private func visa() -> CardDetails {
        CardDetails(number: "4111 1111 1111 1111", expiry: CardExpiry(month: 12, year: 2028), securityCode: "123", holderName: "Ada Lovelace")
    }

    func testSessionReadSendsSecretHeaderAndDecodes() async throws {
        let edge = FakeEdge()
        edge.sessions = [.init(status: 200, body: session(attempt: attempt("captured")))]
        let s = try await client(edge).session(intentId: "int_1", clientSecret: "sec")
        XCTAssertEqual(s.intentId, "int_1")
        XCTAssertEqual(s.merchant.displayName, "Shop")
        XCTAssertEqual(s.attempt?.brand, "visa")
        XCTAssertEqual(s.returnUrl?.host, "shop.example")
        XCTAssertNotNil(s.expiresAt)
        let req = edge.requests[0]
        XCTAssertEqual(req.url?.path, "/c/int_1/session")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-Client-Secret"), "sec")
    }

    func testSaleIsPostedThenPolledToCaptured() async throws {
        let edge = FakeEdge()
        edge.card = [.init(status: 202, body: session(attempt: attempt("pending")))]
        edge.sessions = [
            .init(status: 200, body: session(attempt: attempt("pending"))),
            .init(status: 200, body: session(state: "settled", attempt: attempt("captured"))),
        ]
        let card = visa()
        let result = try await client(edge).payWithCard(intentId: "int_1", clientSecret: "sec", card: card) { _ in
            XCTFail("no challenge expected"); return true
        }
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.state, "settled")
        XCTAssertEqual(result.attempt?.state, "captured")
        let body = edge.bodies[0]
        XCTAssertEqual(body["cardNumber"] as? String, "4111111111111111")
        XCTAssertEqual(body["securityCode"] as? String, "123")
        XCTAssertEqual(body["expiryMonth"] as? Int, 12)
        XCTAssertEqual(body["expiryYear"] as? Int, 2028)
        XCTAssertEqual(body["holderName"] as? String, "Ada Lovelace")
        XCTAssertEqual(body["clientSecret"] as? String, "sec")
        XCTAssertNil(body["email"])
        XCTAssertTrue(card.number.isEmpty, "card wiped after send")
        XCTAssertEqual(edge.requests.filter { $0.url!.path.hasSuffix("/session") }.count, 2)
    }

    func testEmailAndSaveCardAreSentWhenGiven() async throws {
        let edge = FakeEdge()
        edge.card = [.init(status: 202, body: session(state: "settled", attempt: attempt("captured")))]
        _ = try await client(edge).payWithCard(intentId: "int_1", clientSecret: "sec", card: visa(), email: " a@b.co ", saveCard: true) { _ in true }
        XCTAssertEqual(edge.bodies[0]["email"] as? String, "a@b.co")
        XCTAssertEqual(edge.bodies[0]["saveCard"] as? Bool, true)
    }

    func testThreeDSOpensChallengeOnceAndKeepsPolling() async throws {
        let edge = FakeEdge()
        edge.card = [.init(status: 202, body: session(attempt: attempt("pending")))]
        edge.sessions = [
            .init(status: 200, body: session(attempt: attempt("requires_3ds", challenge: true))),
            .init(status: 200, body: session(attempt: attempt("requires_3ds", challenge: true))),
            .init(status: 200, body: session(attempt: attempt("pending"))),
            .init(status: 200, body: session(state: "settled", attempt: attempt("captured"))),
        ]
        let opened = Counter()
        let result = try await client(edge).payWithCard(intentId: "int_1", clientSecret: "sec", card: visa()) { url in
            await opened.add(url)
            return true
        }
        XCTAssertTrue(result.isSuccess)
        let urls = await opened.urls
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.path, "/c/int_1/challenge")
    }

    func testChallengeThatCannotOpenFails() async {
        let edge = FakeEdge()
        edge.card = [.init(status: 202, body: session(attempt: attempt("requires_3ds", challenge: true)))]
        do {
            _ = try await client(edge).payWithCard(intentId: "int_1", clientSecret: "sec", card: visa()) { _ in false }
            XCTFail("expected error")
        } catch let e as PesaCheckoutError {
            XCTAssertEqual(e.code, .challengeUnavailable)
        } catch { XCTFail("\(error)") }
    }

    func testDeclineLeavesTheIntentOpen() async throws {
        let edge = FakeEdge()
        edge.card = [.init(status: 202, body: session(attempt: attempt("pending")))]
        edge.sessions = [.init(status: 200, body: session(state: "open", attempt: attempt("declined", reason: "The card was declined.", code: "051")))]
        let result = try await client(edge).payWithCard(intentId: "int_1", clientSecret: "sec", card: visa()) { _ in true }
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.isDeclined)
        XCTAssertEqual(result.state, "open")
        XCTAssertEqual(result.failureReason, "The card was declined.")
        XCTAssertEqual(result.attempt?.declineCode, "051")
    }

    func testManualCaptureEndsAuthorized() async throws {
        let edge = FakeEdge()
        edge.card = [.init(status: 202, body: session(state: "authorized", attempt: attempt("authorized")))]
        let result = try await client(edge).payWithCard(intentId: "int_1", clientSecret: "sec", card: visa()) { _ in true }
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.state, "authorized")
        XCTAssertEqual(edge.requests.count, 1)
    }

    func testPollingCeilingTimesOut() async {
        let edge = FakeEdge()
        edge.card = [.init(status: 202, body: session(attempt: attempt("pending")))]
        edge.sessions = [.init(status: 200, body: session(attempt: attempt("pending")))]
        do {
            _ = try await client(edge, tries: 3).payWithCard(intentId: "int_1", clientSecret: "sec", card: visa()) { _ in true }
            XCTFail("expected timeout")
        } catch let e as PesaCheckoutError {
            XCTAssertEqual(e.code, .timeout)
        } catch { XCTFail("\(error)") }
        XCTAssertEqual(edge.requests.count, 3)
    }

    func testChallengeCeilingIsWallClock() async {
        let edge = FakeEdge()
        edge.card = [.init(status: 202, body: session(attempt: attempt("requires_3ds", challenge: true)))]
        edge.sessions = [.init(status: 200, body: session(attempt: attempt("requires_3ds", challenge: true)))]
        let clock = Clock()
        do {
            _ = try await client(edge, tries: 1000, now: { clock.now() }).payWithCard(intentId: "int_1", clientSecret: "sec", card: visa()) { _ in true }
            XCTFail("expected timeout")
        } catch let e as PesaCheckoutError {
            XCTAssertEqual(e.code, .timeout)
        } catch { XCTFail("\(error)") }
        XCTAssertLessThan(edge.requests.count, 20)
    }

    func testErrorMapping() {
        func map(_ status: Int, _ body: String) -> PesaCheckoutError { PesaCheckoutClient.error(status: status, body: Data(body.utf8)) }
        let bad = map(400, #"{"error":{"code":"invalid_request","message":"Check the card number.","field":"cardNumber"}}"#)
        XCTAssertEqual(bad.code, .invalidCard)
        XCTAssertEqual(bad.field, "cardNumber")
        XCTAssertEqual(bad.message, PesaStrings.en.numberInvalid)
        XCTAssertEqual(bad.gatewayMessage, "Check the card number.")
        XCTAssertEqual(map(400, #"{"error":{"code":"invalid_request","message":"x","field":"amount"}}"#).code, .invalidRequest)
        XCTAssertEqual(map(404, #"{"error":{"code":"not_found","message":"x"}}"#).code, .notFound)
        XCTAssertEqual(map(401, "").code, .notFound)
        XCTAssertEqual(map(409, #"{"error":{"code":"card_state","message":"x"}}"#).code, .attemptInProgress)
        XCTAssertEqual(map(409, #"{"error":{"code":"intent_closed","message":"x"}}"#).code, .intentClosed)
        XCTAssertEqual(map(410, "").code, .intentClosed)
        XCTAssertEqual(map(429, #"{"error":{"code":"rate_limited","message":"Slow down."}}"#).code, .rateLimited)
        XCTAssertEqual(map(503, "<html>").code, .server)
        XCTAssertEqual(map(503, "<html>").message, PesaStrings.en.errorServer)
        XCTAssertNil(map(503, "<html>").gatewayMessage)
        XCTAssertEqual(map(409, #"{"error":{"code":"card_state","message":"x"}}"#).gatewayCode, "card_state")
    }

    func testRefusalSurfacesAsError() async {
        let edge = FakeEdge()
        edge.card = [.init(status: 404, body: #"{"error":{"code":"not_found","message":"This payment link is not valid."}}"#)]
        do {
            _ = try await client(edge).payWithCard(intentId: "int_1", clientSecret: "wrong", card: visa()) { _ in true }
            XCTFail("expected error")
        } catch let e as PesaCheckoutError {
            XCTAssertEqual(e.code, .notFound)
            XCTAssertEqual(e.status, 404)
        } catch { XCTFail("\(error)") }
    }

    func testTransportFailureIsTransport() async {
        let edge = FakeEdge()
        do {
            _ = try await client(edge).session(intentId: "int_1", clientSecret: "sec")
            XCTFail("expected error")
        } catch let e as PesaCheckoutError {
            XCTAssertEqual(e.code, .transport)
        } catch { XCTFail("\(error)") }
    }

    func testWalletIsNotImplementedYet() async {
        do {
            _ = try await client(FakeEdge()).payWithWallet(intentId: "int_1", clientSecret: "sec", wallet: .applePay)
            XCTFail("expected error")
        } catch let e as PesaCheckoutError {
            XCTAssertEqual(e.code, .notImplemented)
        } catch { XCTFail("\(error)") }
    }

    func testSessionDecodesSavedCards() async throws {
        let edge = FakeEdge()
        let extra = #", "canSaveCard": true, "savedCardSecurityCode": "required", "savedCards": [{"token": "tok_secret_1", "brand": "visa", "last4": "4242", "expiry": "12/2028", "holderName": "A Payer"}]"#
        edge.sessions = [.init(status: 200, body: session(extra: extra))]
        let s = try await client(edge).session(intentId: "int_1", clientSecret: "sec")
        XCTAssertTrue(s.canSaveCard)
        XCTAssertEqual(s.savedCardSecurityCode, .required)
        XCTAssertEqual(s.savedCards, [SavedCard(token: "tok_secret_1", brand: "visa", last4: "4242", expiry: "12/2028", holderName: "A Payer")])
        XCTAssertEqual(s.savedCards.first?.cardBrand, .visa)
        XCTAssertFalse("\(s.savedCards)".contains("tok_secret_1"), "token stays out of descriptions")
    }

    func testSessionWithoutSavedCardsUsesDefaults() async throws {
        let edge = FakeEdge()
        edge.sessions = [.init(status: 200, body: session())]
        let s = try await client(edge).session(intentId: "int_1", clientSecret: "sec")
        XCTAssertFalse(s.canSaveCard)
        XCTAssertTrue(s.savedCards.isEmpty)
        XCTAssertEqual(s.savedCardSecurityCode, .never)
    }

    func testUnknownSavedCardSecurityCodeReadsAsNever() async throws {
        let edge = FakeEdge()
        let extra = #", "savedCardSecurityCode": "sometimes", "savedCards": [{"token": "t", "brand": "diners", "last4": "0004", "expiry": "01/2030"}]"#
        edge.sessions = [.init(status: 200, body: session(extra: extra))]
        let s = try await client(edge).session(intentId: "int_1", clientSecret: "sec")
        XCTAssertEqual(s.savedCardSecurityCode, .never)
        XCTAssertEqual(s.savedCards.first?.cardBrand, .unknown)
        XCTAssertEqual(s.savedCards.first?.holderName, "")
    }

    func testSavedCardBrandIsReadTolerantly() async throws {
        let edge = FakeEdge()
        let extra = #", "savedCardSecurityCode": "optional", "savedCards": [{"token": "a", "brand": "MC"}, {"token": "b", "brand": "American_Express"}, {"token": "c", "brand": "China UnionPay"}]"#
        edge.sessions = [.init(status: 200, body: session(extra: extra))]
        let s = try await client(edge).session(intentId: "int_1", clientSecret: "sec")
        XCTAssertEqual(s.savedCardSecurityCode, .optional)
        XCTAssertEqual(s.savedCards.map(\.cardBrand), [.mastercard, .amex, .unionpay])
    }

    func testSaveCardIsLeftOutByDefault() async throws {
        let edge = FakeEdge()
        edge.card = [.init(status: 202, body: session(state: "settled", attempt: attempt("captured")))]
        _ = try await client(edge).payWithCard(intentId: "int_1", clientSecret: "sec", card: visa()) { _ in true }
        XCTAssertNil(edge.bodies[0]["saveCard"])
    }

    func testSavedCardPostsTokenAndSecurityCode() async throws {
        let edge = FakeEdge()
        edge.card = [.init(status: 202, body: session(attempt: attempt("pending")))]
        edge.sessions = [.init(status: 200, body: session(state: "settled", attempt: attempt("captured")))]
        let code = SecretBytes("123")
        let result = try await client(edge).payWithSavedCard(intentId: "int_1", clientSecret: "sec", token: "tok_secret_1",
                                                             securityCode: code, email: " a@b.co ") { _ in
            XCTFail("no challenge expected"); return true
        }
        XCTAssertTrue(result.isSuccess)
        XCTAssertTrue(code.isEmpty, "security code wiped after send")
        let req = edge.requests[0]
        XCTAssertEqual(req.url?.path, "/c/int_1/card")
        XCTAssertFalse(req.url!.absoluteString.contains("tok_secret_1"))
        let body = edge.bodies[0]
        XCTAssertEqual(Set(body.keys), ["clientSecret", "savedCard", "email"])
        XCTAssertEqual(body["email"] as? String, "a@b.co")
        let saved = body["savedCard"] as? [String: Any]
        XCTAssertEqual(saved?["token"] as? String, "tok_secret_1")
        XCTAssertEqual(saved?["securityCode"] as? String, "123")
    }

    func testSavedCardWithoutSecurityCodeLeavesItOut() async throws {
        let edge = FakeEdge()
        edge.card = [.init(status: 202, body: session(state: "settled", attempt: attempt("captured")))]
        _ = try await client(edge).payWithSavedCard(intentId: "int_1", clientSecret: "sec", token: "tok_secret_1") { _ in true }
        let body = edge.bodies[0]
        XCTAssertEqual(Set(body.keys), ["clientSecret", "savedCard"])
        XCTAssertEqual((body["savedCard"] as? [String: Any]).map { Set($0.keys) }, ["token"])
    }

    func testSavedCardFollowsTheChallenge() async throws {
        let edge = FakeEdge()
        edge.card = [.init(status: 202, body: session(attempt: attempt("requires_3ds", challenge: true)))]
        edge.sessions = [.init(status: 200, body: session(state: "settled", attempt: attempt("captured")))]
        let opened = Counter()
        let result = try await client(edge).payWithSavedCard(intentId: "int_1", clientSecret: "sec", token: "tok_secret_1") { url in
            await opened.add(url)
            return true
        }
        XCTAssertTrue(result.isSuccess)
        let urls = await opened.urls
        XCTAssertEqual(urls.count, 1)
    }

    func testRefusedSavedCardIsAnInvalidCard() {
        let e = PesaCheckoutClient.error(status: 400, body: Data(#"{"error":{"code":"invalid_request","message":"Choose another card.","field":"savedCard.token"}}"#.utf8))
        XCTAssertEqual(e.code, .invalidCard)
        XCTAssertEqual(e.field, "savedCard.token")
    }

    func testIntentIdIsPathEncoded() async throws {
        let edge = FakeEdge()
        edge.sessions = [.init(status: 200, body: session())]
        _ = try await client(edge).session(intentId: "a b/c", clientSecret: "sec")
        XCTAssertEqual(edge.requests[0].url?.absoluteString, "https://checkout.test/c/a%20b%2Fc/session")
    }
}

actor Counter {
    var urls: [URL] = []
    func add(_ u: URL) { urls.append(u) }
}

final class Clock: @unchecked Sendable {
    private var t = Date(timeIntervalSince1970: 1_000_000)
    private let lock = NSLock()
    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        t = t.addingTimeInterval(30)
        return t
    }
}
