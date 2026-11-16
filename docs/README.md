# FluxNews documentation

FluxNews is the active development repository for the shared Rust core and the
native Android, iOS/iPadOS, and macOS clients. The repository migration and the
Flutter-to-native replacement are complete. The previous Flutter implementation
is preserved only under [`Archived/Flutter/`](../Archived/Flutter/README.md).

This index is navigation, not a second roadmap. Current status and open work are
owned by the documents linked below.

## Start here

- [`AGENTS.md`](../AGENTS.md) — repository working rules and documentation
  authority hierarchy.
- [`ARCHITECTURE_DECISIONS.md`](ARCHITECTURE_DECISIONS.md) — primary
  cross-platform architecture authority.
- [`MOBILE_PRODUCT_SEMANTICS.md`](MOBILE_PRODUCT_SEMANTICS.md) — shared
  native-mobile product semantics for iOS/iPadOS and Android.
- [`NATIVE_DEVELOPMENT.md`](../NATIVE_DEVELOPMENT.md) — local native
  development entry point.
- [`MIGRATION.md`](../MIGRATION.md) — completed Flux-to-FluxNews repository
  migration record and provenance. It is not evidence that the migration remains
  open.

## Current authoritative documentation

These documents currently carry binding product or implementation contracts.
Some still combine a completed implementation sequence with rules that remain
valid. They stay active until those rules are explicitly transferred to smaller
current contracts in a later documentation step.

| Area | Current authority | Scope |
| --- | --- | --- |
| Architecture | [`ARCHITECTURE_DECISIONS.md`](ARCHITECTURE_DECISIONS.md) | Rust/Core–native ownership, platform boundaries, durable architecture decisions |
| Shared mobile behavior | [`MOBILE_PRODUCT_SEMANTICS.md`](MOBILE_PRODUCT_SEMANTICS.md) | Product semantics shared by Android and iOS/iPadOS |
| Shared media core | [`current/MEDIA_CORE.md`](current/MEDIA_CORE.md) | Current shared media/Core contract; completed Phase-B sequencing is archived |
| macOS media | [`PHASE_C_NATIVE_MACOS_AUDIO.md`](PHASE_C_NATIVE_MACOS_AUDIO.md) | Native macOS audio/media contract |
| iOS/iPadOS | [`platforms/ios/IOS.md`](platforms/ios/IOS.md) | Native iOS/iPadOS contract; replacement implementation is complete |
| iOS Timeline | [`platforms/ios/IOS.md`](platforms/ios/IOS.md) | Accepted UIKit Timeline contract and frozen implementation boundaries |
| iOS replacement completion | [`acceptance/ios/IOS_D9_FLUTTER_REPLACEMENT_COMPLETION.md`](acceptance/ios/IOS_D9_FLUTTER_REPLACEMENT_COMPLETION.md) | Retained/retired behavior and production-upgrade acceptance |
| Android | [`platforms/android/ANDROID.md`](platforms/android/ANDROID.md) | Current native Android product/platform contract; E1–E9 chronology is archived |
| macOS parity | [`MACOS_C3_FEATURE_PARITY_ROADMAP.md`](MACOS_C3_FEATURE_PARITY_ROADMAP.md) | Approved C3 decisions and completed parity scope |

A completed phase does not make its still-binding product or architecture rules
historical. Conversely, historical implementation sequencing in a current
contract is not an instruction to restart that phase.

## Operational / release documentation

Open operational work has a specific owner. Do not duplicate these task lists in
migration or historical phase documents.

- [`RELEASE_DISTRIBUTION.md`](RELEASE_DISTRIBUTION.md) — cross-platform
  release and distribution policy and remaining channel-specific release work.
- [`FDROID_OPEN_GATES.md`](FDROID_OPEN_GATES.md) — authoritative remaining
  native F-Droid gates. Normal developer-signing or production-upgrade evidence
  does not automatically close F-Droid-specific signature gates.
- [`DEPENDENCY_MAINTENANCE.md`](DEPENDENCY_MAINTENANCE.md) — dependency,
  vulnerability, maintenance, and CI-cost policy.
- [`.github/DEPENDENCY_AUTOMATION.md`](../.github/DEPENDENCY_AUTOMATION.md) —
  Dependabot/RustSec automation procedure.
- [`POST_REPLACEMENT_FOLLOWUP_PLAN.md`](POST_REPLACEMENT_FOLLOWUP_PLAN.md) —
  completed post-replacement package history plus remaining follow-up references;
  it is not a replacement for the dedicated release, F-Droid, or dependency
  owners above.

### Localization / Weblate

- [Android localization](ANDROID_WEBLATE_LOCALIZATION.md)
- [iOS localization](IOS_WEBLATE_LOCALIZATION.md)
- [macOS localization](MACOS_WEBLATE_LOCALIZATION.md)
- [Shared Weblate glossary](WEBLATE_GLOSSARY.md)

The platform runtime resources remain authoritative for application strings.
Weblate handoff files and the glossary support the translation workflow; they do
not create a second product specification.

### Publication-facing documents

- [`PRIVACY.md`](../PRIVACY.md) — public privacy statement.
- Root [`README.md`](../README.md), store metadata, screenshots, and privacy
  copy require their own native-release review before publication. That review
  is release work, not an unfinished repository migration.

## Current status at a glance

This is a derived orientation only; the linked owner documents remain
authoritative.

- **Flutter-to-native replacement:** complete.
- **Flux-to-FluxNews repository cutover:** complete.
- **Native Android E1–E9:** complete, including the signed production
  Flutter-to-native upgrade acceptance.
- **Native iOS/iPadOS replacement:** complete, including D9 production-upgrade
  acceptance.
- **macOS native implementation and approved parity work:** complete at the
  documented accepted scopes.
- **Distribution:** still has channel- and candidate-specific release gates,
  especially F-Droid and Apple/store distribution.
- **Maintenance:** dependency/security and translation work continue as normal
  project maintenance.

Do not turn this section into an independent checklist. Update the owning
document first when operational status changes.

## Acceptance evidence

Acceptance records document exactly what was checked for a particular scope,
candidate, device, or owner decision. They are evidence, not general roadmaps.

- [`acceptance/`](acceptance/) — acceptance records already separated from
  active plans, including the Apple UniFFI integration record.
- [`acceptance/ios/IOS_D5_FINAL_ACCEPTANCE.md`](acceptance/ios/IOS_D5_FINAL_ACCEPTANCE.md)
- [`acceptance/ios/IOS_D6_FINAL_ACCEPTANCE.md`](acceptance/ios/IOS_D6_FINAL_ACCEPTANCE.md)
- [`acceptance/ios/IOS_D7_NOW_PLAYING_REMOTE_COMMANDS_CARPLAY.md`](acceptance/ios/IOS_D7_NOW_PLAYING_REMOTE_COMMANDS_CARPLAY.md)
- [`acceptance/ios/IOS_D9_FLUTTER_REPLACEMENT_COMPLETION.md`](acceptance/ios/IOS_D9_FLUTTER_REPLACEMENT_COMPLETION.md)
- [`MACOS_SANDBOX_ACCEPTANCE.md`](MACOS_SANDBOX_ACCEPTANCE.md)

Owner acceptance, automated CI, local tests, and physical-device validation are
different evidence types. Do not infer that every historical matrix item was run
merely because a broader replacement phase is complete.

## Historical plans and analyses

- [`analysis/`](analysis/) — dated performance, localization, and parity
  investigations. Findings remain useful, but recommendations are not
  automatically current backlog.
- [`archive/`](archive/) — completed plans, phase snapshots, and migration
  records that no longer own current work.
- [`reference/`](reference/) — historical FluxBar and FluxNews product
  evidence. It is not an implementation roadmap.
- [`Archived/Flutter/`](../Archived/Flutter/README.md) — complete archived
  Flutter implementation and its historical documentation.

Historical commit SHAs, failed experiments, old test counts, and superseded
implementation descriptions should remain intact when they are evidence of the
state at that time.

## How to read status and authority

- **Completed** does not mean **published**.
- **Implemented** does not mean **accepted for every distribution channel**.
- **Deferred** is not an open mandatory implementation task.
- **Historical analysis** is not the current backlog.
- Code can demonstrate the implementation that exists, but it does not silently
  override an explicit architecture or product decision.
- A newer document is not automatically more authoritative; use its stated
  scope and the authority hierarchy.

## Documentation tools

[`tools/`](tools/) contains supporting analysis tooling. Its measurements must
be interpreted with the limitations documented by the corresponding analysis;
tool output is not automatically a release gate.

## Working rule

Use current authoritative documentation to answer implementation questions and
the operational owner documents to track open work. Preserve historical evidence
without promoting old plans, gaps, or recommendations into new tasks.

When a historical document conflicts with a current authority, keep the
historical record intact and correct or clarify the current authority through a
separate reviewed change.
