# iOS Localization Usage Audit

> **Status: COMPLETE / TEST-GATED**
>
> This audit exists because Xcode String Catalog `extractionState` is not a
> reliable runtime-usage authority for the native iOS app. Productive SwiftUI,
> interpolated and dynamically carried localization keys can be reported as
> `stale`, while some localization-aware call sites can also be absent from the
> catalog entirely.

## Scope

The binding D9-D completion scope is English and German. English is the String
Catalog source language and is protected by the source-to-catalog regression
contract; German is the maintained completion translation. Spanish, Galician,
Dutch, Tamil and Turkish remain preserved additional locales, but their
translation review is deferred and is not a D9-D completion gate.

The production usage gate scans localization-aware source in:

- `apple/ios/FluxNews/`
- `apple/ios/FluxNewsWidgets/`
- `apple/shared/FluxApple/`

It covers direct literals used by `String(localized:)`,
`LocalizedStringResource`, SwiftUI text/control initializers, navigation
titles, alerts, confirmation dialogs and progress views. The SwiftUI controls
covered explicitly include `LabeledContent`, `DisclosureGroup`, `Menu`,
`NavigationLink`, `Link`, `Stepper` and `DatePicker`; the scan also covers
literal accessibility labels, hints and values, WidgetKit configuration display
names/descriptions, plus search prompts. Dynamic or interpolated keys that
cannot be reliably reconstructed by static extraction are listed explicitly in
the test contract and retained as `manual` catalog entries.

`DeveloperDiagnosticsView.swift` is excluded from the production scan because
that surface is reachable only through DEBUG / performance-diagnostics builds.
Its diagnostic labels are intentionally not allowed to determine the production
translation set.

## Findings

The audit found two independent classes of regression introduced by the initial
D9-D cleanup:

1. 151 existing German entries had been removed because their Xcode extraction
   state was `stale`, even though many remained reachable at runtime.
2. 120 currently used iOS/widget/shared strings were absent from the String
   Catalog entirely, especially newer D9 Backup/Restore, Downloaded Data,
   About/Open Source and Support Diagnostics copy.

The audit also found five concrete localization bypasses where ordinary
`String` values were carried into user-facing presentation instead of being
resolved through a localization-aware API:

- the Search / Search Results dynamic navigation title;
- the Account / Set Up FluxNews dynamic navigation title;
- the no-subscription Feed Discovery error.
- the Add Feed / Choose a Feed dynamic navigation title;
- the Continue / Add dynamic toolbar button title.

Those call sites now resolve their product text explicitly through
`String(localized:)`.

The expanded gate also restored the source-proven `Build`, `Version`,
`Miniflux Version`, `Technical Details`, `Downloaded Files`, `Storage Used`,
`Stored Records` and `Search category or message` catalog keys. `Continue` is
source-proven by the Add Feed toolbar and is retained as a `manual` entry.

## Catalog classification

After the final measured usage pass the iOS catalog contains 465 keys:

- 271 `manual`: source-proven or dynamic runtime keys that must not be removed
  based on Xcode extraction state;
- 169 normally extracted active keys;
- 25 remaining `stale` keys.

The remaining 25 stale keys are not treated as an automatic deletion list.

### DEBUG / legacy-diagnostic only

These are consumed only by the legacy migration/developer diagnostic path and do
not belong to the production UI localization gate:

- API key
- App Group
- Base URL
- Compatible settings
- Custom headers
- Download metadata
- Feed preferences
- Keychain credentials
- Legacy cache
- Legacy database
- Legacy downloads
- Legacy migration feasibility
- Playback progress
- Production identity
- Rust Core
- Sandbox paths
- Smoke test
- Status

### No current productive iOS reference

Repository search found no current production iOS presentation use for:

- Article Action
- Comments available
- Connection Diagnostics
- Miniflux server returned an unexpected response.
- No results
- Showing %lld of %lld
- Unexpected

These remain preserved until a deliberate catalog cleanup is performed; they are
not needed to establish production localization coverage.

## Language state after the audit

English remains the catalog source language. The source-to-catalog gate derives
the production key set from the three production source roots and requires each
source-used key to exist in the catalog. German is the D9-D completion
translation, with 465/465 productive catalog entries translated:

- DE: 465 translated, 0 missing, 0 needs-review.

The following additional locales are preserved in the catalog. Their figures
are informational and deferred, not D9-D completion criteria:

- ES: 186 translated, 254 needs-review, 25 missing structures.
- GL: 186 translated, 254 needs-review, 25 missing structures.
- NL: 186 translated, 254 needs-review, 25 missing structures.
- TA: 186 translated, 254 needs-review, 25 missing structures.
- TR: 186 translated, 254 needs-review, 25 missing structures.

The usage audit exposed that the previous seven-language completion count was
incorrect: it counted only the reduced catalog after productive keys had been
removed or omitted.

ES/GL/NL/TA/TR `needs_review` entries remain deliberately unverified rather
than being marked translated. They are deferred to the planned
Weblate/community localization workflow and do not block D9-D completion.

## Regression contract

The iOS XCTest gate now:

- derives production localization keys from source rather than trusting
  `extractionState`;
- requires every source-used key to exist in the catalog;
- preserves the production locale structures without treating deferred locale
  review as a D9-D completion requirement;
- requires every production key to have a non-empty translated German value;
- protects interpolated/dynamic runtime keys explicitly;
- keeps placeholder/plural compatibility checks;
- excludes the DEBUG-only Developer Diagnostics surface from production
  localization completeness.

Future catalog cleanup must use repository/source evidence. Xcode
`extractionState == stale` alone is never sufficient evidence that a key is
unused.

The technical gate passed with 556 tests and 0 failures. Deferred
`needs_review` values remain evidence of outstanding language review for the
additional locales, not a D9-D blocker.
