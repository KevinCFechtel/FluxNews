import Foundation

enum SystemNotificationPresentation {
    /// `locale` formats the number and the timestamp; the *language* comes from
    /// `bundle`. They are separate parameters because they are separate
    /// decisions — passing only a locale would format "3" for en_US while still
    /// loading whatever language the app is running in.
    static func body(
        newCount: UInt32,
        submittedAt: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        bundle: Bundle = .main
    ) -> String {
        let count = newCount == 1
            ? String(localized: "1 new article", bundle: bundle, locale: locale)
            : String(
                format: String(
                    localized: "%lld new articles",
                    bundle: bundle,
                    locale: locale
                ),
                locale: locale,
                newCount
            )
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return String(
            format: String(localized: "%@ · %@", bundle: bundle, locale: locale),
            locale: locale,
            count,
            formatter.string(from: submittedAt)
        )
    }
}
