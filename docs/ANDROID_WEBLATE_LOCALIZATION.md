# Android localization: Weblate-ready resource contract

Status: **Android C1 was owner-accepted and closed for the post-replacement roadmap on 17 October 2026. German source-resource coverage is complete; Weblate review and additional target-language translations continue separately.**

## Product languages

The established `MOBILE_PRODUCT_SEMANTICS.md` contract calls for seven native-mobile languages:

| Language | Android resource folder | Translation status |
| --- | --- | --- |
| English (source) | `values/strings.xml` | Canonical English |
| German | `values-de/strings.xml` | Source-resource coverage complete; device review pending |
| Spanish | `values-es/strings.xml` | Review/translation pending |
| Galician | `values-gl/strings.xml` | Review/translation pending |
| Dutch | `values-nl/strings.xml` | Review/translation pending |
| Tamil | `values-ta/strings.xml` | Review/translation pending |
| Turkish | `values-tr/strings.xml` | Review/translation pending |

The German catalog has completed the accepted source-resource coverage milestone and awaits on-device review. Exact resource counts change as source strings evolve. The other five target catalogs are intentionally empty until reviewed translations exist. Android uses canonical English defaults for missing entries. **Empty language catalogs are scaffolding, not translated UI.** Do not turn on an in-app language picker or advertise complete translation coverage for these five languages before review.

## Weblate component configuration (when service is connected)

- **Format:** Android String Resource (monolingual).
- **Repository:** `KevinCFechtel/FluxNews`.
- **Branch:** `main`, with Weblate changes delivered through reviewed commits/PRs.
- **Source language:** English (`en`).
- **Monolingual base:** `android/app/src/main/res/values/strings.xml`.
- **File mask:** `android/app/src/main/res/values-*/strings.xml`.
- **Languages:** `de`, `es`, `gl`, `nl`, `ta`, `tr` (English comes from the base).
- **Template for new translations:** Empty.
- **Translation workflow:** Translation reviewers own target catalogs; application changes own the English source catalog. No generated pseudo-translations or automatic writes to translation files as part of code changes.

The native Android component is configured on Hosted Weblate using this contract. Repository updates use the repository-wide GitHub Weblate webhook, and translation changes are delivered through reviewed pull requests.

## Developer rules

1. All user-visible UI, settings, notification, error, widget and accessibility copy belongs in Android `strings.xml` files. Compose uses `stringResource(R.string.key)`; callbacks/background workers use `context.getString(R.string.key)`; plural messages use Android `plurals` and `pluralStringResource`/ `getQuantityString`.
2. Use semantic, stable snake_case keys such as `feed_discovery_empty`. Never reuse a key for changed meaning; update source English when the wording genuinely changes.
3. Format arguments must be positional and typed: `%1$s`, `%2$d`; preserve exact placeholders across languages. Do not concatenate fragments into sentences or assume identical plural rules.
4. Use `translatable="false"` for literal product/technical values, URLs, identifiers and tokens; do not translate user/server-provided feed titles or category names.
5. Do not fabricate machine translations to make the directory look complete. Weblate translations should be reviewed before they become release-supported.
6. The C1.1–C1.6 extraction sequence below is retained as implementation history: navigation/feed creation; settings and Timeline controls; settings/download/Reader surfaces; Listening List/Player/Search/bulk-feed/diagnostics; common Account/migration/backup/About/background settings; and Search plus Widget configuration. **C1 is already owner-accepted and must not be reopened by this historical sequence.** Newly discovered user-visible hardcoded strings remain localization defects and should be fixed through the normal resource/Weblate workflow.
7. Locale formatting belongs to Android's locale-aware date/number APIs, not English-only string concatenation. Validate all seven locales for truncated text, RTL where applicable, correct plurals, accessibility and fallback.
8. Add or update tests for placeholders and source/translation parity when target catalogs are populated.

C1 closure does not mean every Weblate target language is fully translated or
linguistically reviewed. Translation completeness and future locale work remain
separate from the closed Android C1 implementation milestone.


## Continuous localization guard

The Android GitHub Actions workflow runs `python3 android/Build/check-localization.py --base <base-sha>` before its build and lint steps. It checks **newly added or edited Kotlin lines** in `android/app/src/main` for high-confidence UI literals (Compose `Text`, content descriptions, certain UI labels, and snackbar helpers), while allowing existing localization debt to be cleaned up incrementally. It intentionally does not treat every quoted string as user-visible (URLs, API values, log tags, and keys are not UI translations).

For a local, non-blocking **full inventory** run `python3 android/Build/check-localization.py --all`; output is file:line plus rule. The full inventory is reporting-only and does not declare C1 complete. When a flagged literal genuinely cannot be translated, document a narrow exception on that line with `// l10n-ignore: reason`. Avoid blanket suppression. This guard is heuristic and **does not cover every dynamically constructed user-facing message**; continue manual review for notifications, workers and formatted messages.

The CI step uses full Git history and the pull-request base SHA (or the previous push SHA on main) so the diff check is reproducible; it fails on new violations.

## Latest C1 audit

See [analysis/android/ANDROID_LOCALIZATION_AUDIT.md](analysis/android/ANDROID_LOCALIZATION_AUDIT.md) for the dated source-level findings and the distinction between the blocking incremental guard and informational full inventory. That audit is historical evidence and does **not** reopen accepted C1. Green CI still does not imply complete linguistic review or translation coverage.

### Expanded source-level audit (2026-10-12)

A follow-up audit of the 71 production Kotlin files identified additional English fallback labels, snackbar text, error states and settings labels after PR #46. Findings and categories are documented in [analysis/android/ANDROID_LOCALIZATION_AUDIT.md](analysis/android/ANDROID_LOCALIZATION_AUDIT.md). The CI scanner now checks more literal forms; it remains an incremental guard, not evidence of complete linguistic review. These findings are retained as dated implementation evidence; subsequent defects are handled without reopening owner-accepted C1.

Android Auto/MediaTransfer follow-up: user-visible Media3 browse/command labels and foreground download notification copy are now supplied through resources; see [analysis/android/ANDROID_LOCALIZATION_AUDIT.md](analysis/android/ANDROID_LOCALIZATION_AUDIT.md). Validate host-side locale changes and original fallback behavior on Android Auto separately.


## Android Lint and staged Weblate locales (2026-10-12)

The base resources contain all canonical English source strings, and **missing target translations intentionally fall back to them**. Android Lint's `MissingTranslation` rule reports every missing entry in the five deliberately empty target catalogs (501 errors in the October 12 CI), including the Development app-name override. The app module therefore disables **only** `MissingTranslation` while these languages are populated through Weblate. All other lint rules remain active. This does not mark blank catalogs translated: the CI source/incremental localization checks, resource structure tests and reviewer/device acceptance still apply. When all supported locales are populated, remove this one-rule exception to restore automatic missing-translation enforcement.
