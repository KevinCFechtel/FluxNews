# iOS localization: Weblate XLIFF handoff

The native iOS/iPadOS runtime source of truth remains
`apple/ios/FluxNews/Localizable.xcstrings`. Weblate does **not** replace the
String Catalog and the XLIFF handoff files are not bundled into the app.

English (`en`) is the source language. The handoff contains the six existing
target locales:

- German (`de`)
- Spanish (`es`)
- Galician (`gl`)
- Dutch (`nl`)
- Tamil (`ta`)
- Turkish (`tr`)

Existing translations and their review state are exported from the String
Catalog. In particular, the deferred `needs_review` values for ES/GL/NL/TA/TR
remain review work instead of being promoted to translated content.

## Weblate component

Use one component named **iOS**:

- **Repository:** `weblate://flux-news/android` (share the already configured
  FluxNews repository connection)
- **Version control:** GitHub Pull Request
- **Repository branch:** inherited from the linked Android component (`main`)
- **File format:** XLIFF 1.2 with Apple extensions
- **File mask:** `apple/ios/Weblate/*.xliff`
- **Source language:** English
- **Monolingual base language file:** empty
- **Template for new translations:** empty
- **Add new translation:** disabled
- **Manage strings/source keys:** disabled
- **Create pull requests:** enabled
- **Automatic pull-request merge:** disabled
- **Push on commit:** inherited/enabled
- **Push on update:** inherited/disabled
- **Git strategy:** inherited Rebase
- **Lock on repository error:** inherited/enabled

The repository-wide GitHub Weblate webhook is shared by all components; do not
create a separate webhook for iOS.

## Handoff files

The committed files under `apple/ios/Weblate/` are bilingual XLIFF 1.2
handoffs. Plural variants use the Apple XLIFF plural unit convention so Weblate's
Apple-XLIFF parser can keep the plural forms together.

Regenerate the handoff from the current String Catalog with:

```bash
python3 apple/ios/Build/weblate-xliff.py export
```

This intentionally rewrites the XLIFF targets from the current catalog. Import
or otherwise preserve outstanding Weblate work before regenerating.

Validate the XLIFF source side without requiring Weblate targets to match the
catalog with:

```bash
python3 apple/ios/Build/weblate-xliff.py check
```

The normal iOS test gate runs this check before compiling the app.

## Bringing reviewed Weblate translations into the app

A Weblate pull request changes the XLIFF handoff; it does not directly modify the
runtime String Catalog. After reviewed XLIFF changes have landed, import them:

```bash
python3 apple/ios/Build/weblate-xliff.py import
```

The import updates only the six target localizations in
`Localizable.xcstrings`; English source ownership remains in application code
and the String Catalog. XLIFF targets marked as needing localization remain
`needs_review`; other non-empty targets become `translated`.

Commit the resulting String Catalog update through the normal reviewed PR flow
and run the canonical iOS regression gate. Do not use Xcode
`extractionState` alone to remove catalog entries; the source-usage audit
remains authoritative.

## Translation rules

- Preserve placeholders and plural variants exactly.
- Do not fabricate translations to make a locale appear complete.
- Keep source keys controlled by application development, not Weblate.
- German remains a release-complete target; ES/GL/NL/TA/TR review can proceed
  incrementally through Weblate.
- A green Weblate handoff check proves structural/source integrity, not
  linguistic review.
