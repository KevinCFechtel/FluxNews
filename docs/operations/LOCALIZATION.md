# Localization and Weblate operations

> **Status: ACTIVE / OPERATIONAL**
>
> This document is the single cross-platform owner for localization workflow,
> supported-language policy, review boundaries and Weblate integration. Platform
> runtime resources remain authoritative for application strings.

## Shared language policy

English is the source language. The native project currently carries the same
six target locales across Android, iOS/iPadOS and macOS:

- German (`de`)
- Spanish (`es`)
- Galician (`gl`)
- Dutch (`nl`)
- Tamil (`ta`)
- Turkish (`tr`)

A locale being present in the repository or in Weblate does not by itself mean
that its translations are complete, reviewed or release-supported. Do not fill
missing translations with fabricated or machine-generated values merely to make
coverage appear complete.

## Sources of truth

- **Android:** `android/app/src/main/res/values/strings.xml` is the English
  source; target resources live under `values-*/strings.xml`.
- **iOS/iPadOS:** `apple/ios/FluxNews/Localizable.xcstrings` is the runtime
  source of truth. Weblate XLIFF files are handoff files, not bundled runtime
  resources.
- **macOS:** `apple/macos/FluxNews/Localizable.xcstrings` is the runtime source
  of truth. Weblate XLIFF files are handoff files, not bundled runtime resources.
- **Glossary:** `Weblate/Glossary/*.tbx` stores shared translator terminology;
  it guides translation but never replaces platform runtime resources.

Application development owns source strings and keys. Translation reviewers own
target-language quality. Weblate must not become a second product specification.

## Weblate integration

The Hosted Weblate project contains Android, iOS, macOS and a shared Glossary.
The repository-wide GitHub webhook is shared across components and translation
changes are delivered through reviewed pull requests. Automatic pull-request
merge remains disabled.

Android is directly repository-backed. iOS, macOS and the Glossary share the
existing repository connection through `weblate://flux-news/android`.

## Review and validation rules

- Preserve placeholders, plural structure and semantic meaning across locales.
- Keep product/technical identifiers explicitly non-translatable where
  appropriate.
- User/server-provided feed titles, category names and other remote content are
  not application translations.
- Green structural CI proves resource/XLIFF integrity, not linguistic quality.
- New user-visible strings must enter the platform's source resource rather than
  being hardcoded in UI, notifications, widgets, accessibility or background
  code.
- Locale-aware date, number and plural formatting belongs to native platform
  APIs.
- Translation defects discovered after the completed migration/localization
  milestones are normal maintenance bugs; they do not reopen C1/C3/D9.

## Platform procedures

Detailed platform procedures remain in their operational guides:

- [Android localization](../ANDROID_WEBLATE_LOCALIZATION.md) — the established Android localization guide; its location is not a requirement of CI path selection.
- [iOS Weblate handoff](localization/IOS_WEBLATE_LOCALIZATION.md)
- [macOS Weblate handoff](localization/MACOS_WEBLATE_LOCALIZATION.md)
- [Shared glossary](localization/WEBLATE_GLOSSARY.md)

When platform-specific procedure conflicts with this shared policy, preserve the
platform's runtime source-of-truth mechanics but resolve cross-platform
language/review policy here through a reviewed documentation change.
