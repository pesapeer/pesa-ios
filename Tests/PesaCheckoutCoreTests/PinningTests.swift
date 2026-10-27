import XCTest
@testable import PesaCheckoutCore

final class PinningTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func der() throws -> Data {
        let pem = String(decoding: try fixture("cert.pem"), as: UTF8.self)
        let body = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        return try XCTUnwrap(Data(base64Encoded: body))
    }

    func testPinMatchesTheFlutterFixture() throws {
        let expected = String(decoding: try fixture("pin.txt"), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(try SpkiPin.of(certificateDER: try der()), expected)
        XCTAssertTrue(SpkiPin.matches(certificateDER: try der(), pins: ["nope", " " + expected + "\n"]))
        XCTAssertFalse(SpkiPin.matches(certificateDER: try der(), pins: ["nope"]))
        XCTAssertFalse(SpkiPin.matches(certificateDER: try der(), pins: []))
    }

    func testSpkiStartsWithASequence() throws {
        let spki = try SpkiPin.subjectPublicKeyInfo(try der())
        XCTAssertEqual(spki.first, 0x30)
        XCTAssertGreaterThan(spki.count, 40)
    }

    func testGarbageIsRefused() {
        XCTAssertThrowsError(try SpkiPin.subjectPublicKeyInfo(Data([0x02, 0x01, 0x01])))
        XCTAssertThrowsError(try SpkiPin.subjectPublicKeyInfo(Data([0x30, 0x84, 0xff])))
        XCTAssertFalse(SpkiPin.matches(certificateDER: Data(), pins: ["x"]))
    }

    func testSHA256Vectors() {
        func hex(_ s: String) -> String { SHA256.hash(Array(s.utf8)).map { String(format: "%02x", $0) }.joined() }
        XCTAssertEqual(hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        XCTAssertEqual(hex(String(repeating: "a", count: 1000)),
                       "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
    }
}
