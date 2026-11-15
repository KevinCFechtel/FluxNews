import Foundation
import XCTest

final class SystemNotificationPresentationTests: XCTestCase {
    func testBodyIncludesPluralCountAndLocalizedDateTime() throws {
        let body = SystemNotificationPresentation.body(
            newCount: 3,
            submittedAt: Date(timeIntervalSince1970: 1_777_242_840),
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            bundle: try localizationBundle("en")
        )

        XCTAssertTrue(body.hasPrefix("3 new articles"))
        XCTAssertTrue(body.contains("·"))
        XCTAssertFalse(body.split(separator: "·").last!.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    func testBodyPreservesSingularCount() throws {
        let body = SystemNotificationPresentation.body(
            newCount: 1,
            submittedAt: Date(timeIntervalSince1970: 1_777_242_840),
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            bundle: try localizationBundle("en")
        )

        XCTAssertTrue(body.hasPrefix("1 new article"))
    }

    func testBodyFormatsGermanLocale() {
        let body = SystemNotificationPresentation.body(
            newCount: 3,
            submittedAt: Date(timeIntervalSince1970: 1_777_242_840),
            locale: Locale(identifier: "de_DE"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertTrue(body.hasPrefix("3 "))
        XCTAssertTrue(body.contains("·"))
    }

    /// `String(localized:locale:)` formats numbers and dates with the locale, but
    /// resolves the language from the bundle. Asserting on English wording
    /// therefore needs the English bundle explicitly — without it these tests
    /// only pass on a machine that happens to run in English.
    ///
    /// The strings live in the app bundle, not in the test bundle.
    private func localizationBundle(_ identifier: String) throws -> Bundle {
        let appBundle = try XCTUnwrap(Bundle(identifier: "dev.kevincfechtel.fluxNews"))
        let path = try XCTUnwrap(appBundle.path(forResource: identifier, ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path))
    }
}
