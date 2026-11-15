# macOS C3.7: Weblate localization handoff

The macOS host uses `apple/macos/FluxNews/Localizable.xcstrings` as the **authoritative** runtime string catalog. English (`en`) is the source; German (`de`) is maintained in the string catalog. Spanish (`es`), Galician (`gl`), Dutch (`nl`), Tamil (`ta`), and Turkish (`tr`) are **translation targets only**.

## Weblate onboarding

The five `apple/macos/Weblate/<locale>.xliff` files provide XLIFF 1.2 import scaffolding with source units and no target translations. Import each file into a Weblate component for its locale. Configure the source language as English. Do not enable an in-app language selector or mark any of these five locales translated before human review.

Weblate supports XLIFF 1.2; the native Xcode string catalog stays the application source of truth. After reviewers supply translations, import reviewed target values into the matching locale entries of `Localizable.xcstrings`. Keep the source keys stable and check placeholders before committing. Do not blindly replace existing German translations with iOS translations, and never copy English strings into target values to make a locale appear complete.

The XLIFF files are a handoff snapshot, not an automatic two-way sync. When the canonical catalog changes, regenerate XLIFF source units, preserving any independently reviewed targets in Weblate. A live Weblate integration/permissions setup is **not** performed by this PR.

## Validation

Run `python3 apple/macos/Build/check-localization.py` (also part of the macOS CI gate) to check that the five XLIFF scaffolds match the macOS catalog, that no target translations have been invented, and that German entries are marked translated. Verify the resulting Xcode catalog with the Apple CI. XLIFF scaffolding is intentionally not bundled as localized app resources.

Accessibility acceptance also includes VoiceOver descriptions, keyboard navigation, narrow Settings layout, long copy and localization of new UI strings. Any untranslated future locale falls back to English.
