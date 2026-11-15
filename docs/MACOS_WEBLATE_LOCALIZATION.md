# macOS C3.7: Weblate localization handoff

The macOS host uses `apple/macos/FluxNews/Localizable.xcstrings` as the **authoritative** runtime string catalog. English (`en`) is the source. German (`de`) is fully translated and is now also exposed to Weblate. Spanish (`es`), Galician (`gl`), Dutch (`nl`), Tamil (`ta`), and Turkish (`tr`) remain translation targets that require human review.

## Weblate onboarding

The six `apple/macos/Weblate/<locale>.xliff` files provide the XLIFF 1.2 handoff for the single Hosted Weblate **macOS** component. The component uses the file mask `apple/macos/Weblate/*.xliff`, source language English, no monolingual base file, and the **XLIFF 1.2 with Apple extensions** format. Adding new translations and source-key management are disabled.

`de.xliff` contains the existing reviewed German translations from the macOS String Catalog. The five other XLIFF files contain source units only and intentionally have no target values until translators review them in Weblate.

Weblate supports XLIFF 1.2; the native Xcode string catalog stays the application source of truth. After reviewers supply or change translations, import reviewed target values into the matching locale entries of `Localizable.xcstrings`. Keep source keys stable and validate placeholders before committing. Do not fabricate target translations or copy English strings merely to make a locale appear complete.

The XLIFF files are a handoff snapshot, not an automatic two-way sync. When the canonical catalog changes, regenerate XLIFF source units while preserving reviewed Weblate targets. The macOS component shares the existing FluxNews repository connection (`weblate://flux-news/android`) and repository integration. Translation changes are delivered through reviewed pull requests.

## Validation

Run `python3 apple/macos/Build/check-localization.py` (also part of the macOS CI gate). It checks that all six XLIFF files match the macOS source-unit set, that `de.xliff` exactly matches the complete German translations in `Localizable.xcstrings`, and that no target translations have been invented in ES/GL/NL/TA/TR.

Verify the resulting Xcode catalog with the Apple CI. XLIFF handoff files are intentionally not bundled as localized app resources.

Accessibility acceptance also includes VoiceOver descriptions, keyboard navigation, narrow Settings layout, long copy and localization of new UI strings. Any untranslated future locale falls back to English.
