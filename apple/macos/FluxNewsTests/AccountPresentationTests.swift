import XCTest

final class AccountPresentationTests: XCTestCase {
    func testValidationErrorsUseDistinctUsefulMessages() {
        XCTAssertEqual(
            AccountValidationPresentation.message(for: .invalidURL),
            "Enter a valid HTTP or HTTPS Miniflux server URL."
        )
        XCTAssertEqual(
            AccountValidationPresentation.message(for: .unauthorized),
            "Miniflux rejected the API key."
        )
        XCTAssertNotEqual(
            AccountValidationPresentation.message(for: .network),
            AccountValidationPresentation.message(for: .unauthorized)
        )
    }

    func testCustomHeaderValidationExplainsTheTransportPolicy() {
        XCTAssertEqual(
            AccountValidationPresentation.message(for: .invalidCustomHeader),
            "Custom headers must have unique valid names and cannot replace FluxNews transport headers."
        )
    }

    func testSupportRedactionRemovesSensitiveFieldsAndPaths() {
        let input = "Authorization: Bearer abc123 https://server.test/path?token=123 /Users/me/Media/file.mp3 secret-value"
        let safe = SupportLogRedaction.sanitize(input, secrets: ["secret-value"])
        for value in ["abc123", "server.test", "/Users/me", "secret-value"] {
            XCTAssertFalse(safe.contains(value))
        }
        XCTAssertEqual(SupportLogRedaction.sanitize("sync completed items=3"), "sync completed items=3")
    }

    func testAuthorizationHeaderMaskingConsumesSchemeAndActualSecret() {
        let cases = [
            "Authorization: Bearer abc123",
            "authorization=Basic QWxhZGRpbjpPcGVuU2VzYW1l",
            "Proxy-Authorization: Digest username=alice,response=secret",
            "Authorization: Token sensitive-token",
            "Authorization: plain-secret"
        ]
        for raw in cases {
            let sanitized = SupportLogRedaction.sanitize(raw)
            XCTAssertFalse(sanitized.contains("abc123"), "Bearer token leaked")
            XCTAssertFalse(sanitized.contains("QWxhZGRpbjpPcGVuU2VzYW1l"), "Basic token leaked")
            XCTAssertFalse(sanitized.contains("sensitive-token"), "Token value leaked")
            XCTAssertFalse(sanitized.contains("plain-secret"), "Plain token leaked")
            XCTAssertFalse(sanitized.contains("response=secret"), "Digest parameters leaked")
        }
    }

    func testUnencryptedHTTPWarningOnlyForValidHTTPServerURLs() {
        XCTAssertTrue(AccountTransportWarning.usesUnencryptedHTTP("http://news.example:8080/miniflux"))
        XCTAssertTrue(AccountTransportWarning.usesUnencryptedHTTP("  HTTP://news.example/  "))
        XCTAssertFalse(AccountTransportWarning.usesUnencryptedHTTP("https://news.example"))
        XCTAssertFalse(AccountTransportWarning.usesUnencryptedHTTP("http://"))
        XCTAssertFalse(AccountTransportWarning.usesUnencryptedHTTP("not a URL"))
        XCTAssertFalse(AccountTransportWarning.usesUnencryptedHTTP(""))
    }

    func testAboutUsesRealBundleVersionAndBuildWithSafeFallback() {
        XCTAssertEqual(MacOSAboutInformation.version(from: ["CFBundleShortVersionString": " 3.0.0 "]), "3.0.0")
        XCTAssertEqual(MacOSAboutInformation.build(from: ["CFBundleVersion": "20261015"]), "20261015")
        XCTAssertEqual(MacOSAboutInformation.version(from: [:]), String(localized: "Unknown"))
        XCTAssertEqual(MacOSAboutInformation.build(from: ["CFBundleVersion": "  "]), String(localized: "Unknown"))
        XCTAssertEqual(MacOSAboutInformation.licenseURL.absoluteString, "https://github.com/KevinCFechtel/Flux/blob/main/LICENSE")
    }

    func testMinifluxEntryURLUsesCoreResolvedRootAndSubpathURLs() {
        XCTAssertEqual(
            MinifluxEntryURL.resolve(articleID: 583862) { _ in
                "https://news.example/unread/entry/583862"
            }?.absoluteString,
            "https://news.example/unread/entry/583862"
        )
        XCTAssertEqual(
            MinifluxEntryURL.resolve(articleID: 583862) { _ in
                "https://news.example/miniflux/unread/entry/583862"
            }?.absoluteString,
            "https://news.example/miniflux/unread/entry/583862"
        )
    }

    func testInvalidCoreResolvedEntryURLHasNoSwiftFallback() {
        XCTAssertNil(MinifluxEntryURL.resolve(articleID: 583862) { _ in "not a URL" })
    }
}
