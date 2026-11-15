# FluxNews native repository migration

## Status

The native repository migration is complete on `main`.

The migration was prepared on 15 November 2026 and subsequently merged into
`KevinCFechtel/FluxNews`. Native Android, iOS, macOS, Rust core, release
automation, F-Droid preparation and localization tooling now live in the
FluxNews repository. The former Flutter implementation remains preserved under
`Archived/Flutter/`.

The current post-cutover baseline for this document is:

- FluxNews `main`: `44a2497aaa654be7b40aebbdcd6f2ff82a6676d5`
- old Flux `main`: `6778a3b08e7c052ef8c67f867eae9dd67b772bbe`
- active main ruleset: `main-Protection`
- required status check: `CI Gate`
- `android/v3.0.0` is intentionally **not** present in FluxNews yet; creation
  remains a separate manual release step and must not be performed by migration
  work.

## Source and commit provenance

| Item | Exact commit |
| --- | --- |
| Original FluxNews `main` | `dfe92486a709cfadea9b44f516261db3eed390be` |
| Original Flux `main` | `65bb8eba008ddb3a66711ecba3e624068883f8d1` |
| Flutter archive commit | `ce0faf10c490a961aaaba883d3f0728d82867edc` |
| Two-parent history merge | `0959dbe84c5b77ee86699b9e93861621a62c1472` |

The archive commit is the first parent of the history merge; the original Flux
`main` is its second parent. Neither original history was rewritten, rebased or
squashed.

All historical FluxNews tags remain preserved, including the distinct
`v.1.12.1` and `v1.12.1` tags. The native Android release tag
`android/v3.0.0` was deliberately not migrated from Flux and is not currently
present in FluxNews. It must only be created manually for the approved release
candidate.

In addition to the merged main histories, 38 local archive branches were
prepared to preserve original reference targets:

- `archive/fluxnews/heads/*` and `archive/fluxnews/remotes/origin/*`:
  8 references, including local-only Flutter development history;
- `archive/flux/heads/*`, `archive/flux/remotes/origin/*` and
  `archive/flux/other/opencode/pr78`: 30 references, including stale local
  remote-tracking history and the extra commit reference.

These archive references are provenance only, not active development branches.
Before removing any local backup refs, create a durable Git bundle or equivalent
offline archive.

## File ownership

- `core/`, `android/`, `apple/`, `Build/`, `fdroid/` and native workflows
  are active at the repository root.
- Root `AGENTS.md` and `docs/` contain the native project documentation.
- The tracked Flutter implementation, editor configuration, helper scripts and
  historical workflows are under `Archived/Flutter/`.
- The 13 separately security-reviewed local Flutter text files are archived
  unchanged as `Archived/Flutter/AGENTS.md` and `Archived/Flutter/docs/`.
  Native and Flutter documentation contents were not mixed.
- `metadata/` and `screenshots/` retain the original FluxNews product assets
  at their root paths.
- Root `PRIVACY.md` and `.github/FUNDING.yml` were retained.
- Root `README.md` retains the historical Flutter presentation with native
  development links; release-facing documentation still requires a final
  native-product review before publication.
- Root `LICENSE` retains both original BSD-3-Clause copyright notices.
- No `.DS_Store` file was added.
- Tracked Xcode `xcuserdata` files were removed from the current tree and ignore
  rules prevent reintroducing local IDE state or credentials.

No local signing properties, keystores, environment files, generated native
bindings, caches, application packages or build outputs were copied.
Intentional versioned source inputs, including the Gradle Wrapper and Android
transport-test fixtures, remain part of the native source.

## Submodules and unchanged application identity

The current Gitlink `vendor/rustls-platform-verifier` remains pinned to
`252e25161a91af476cbea620e29d277592d27ec7` with its upstream URL.

Flutter is no longer part of the active `.gitmodules` or native source tree.
Historical commits and tags retain their original `vendor/flutter` Gitlinks.

Application IDs, bundle IDs, app groups, entitlements, signing identities,
certificate expectations, version files and native project build settings were
not changed by the migration itself.

`core/crates/flux-core/src/saved_media_sync.rs` and `init.xml` retained the
old Bootstrap URL during the cutover. Saved Media replication remains a
separate compatibility topic.

## CI and repository protection

The migration and CI cutover have been completed.

- Native workflows and Dependabot configuration are active in FluxNews.
- Flutter workflows remain archived only under `Archived/Flutter/`.
- Selective CI is implemented with a mandatory fail-closed `CI Gate`.
- The active `main-Protection` ruleset applies to `main`.
- Pull requests are required.
- `CI Gate` is the required status check.
- Branch deletion and non-fast-forward updates are blocked.
- Signed-commit enforcement is currently not part of the active ruleset.
- Android, Apple, Rust, F-Droid and release-contract checks are selected by
  changed paths rather than running every platform on every change.

The selective CI still requires a final coverage audit for ordinary `core/**`
changes, especially whether F-Droid/ABI validation is triggered wherever it is
actually required. The goal is to close gaps without reintroducing unnecessary
CI fan-out.

The native verifier Gitlink triggers Android and F-Droid validation where
required. Android localization checks use the imported native source as the
historical-debt baseline only for pre-cutover bases; normal post-cutover changes
are checked against the ordinary PR/push base.

## F-Droid and release automation

The F-Droid CI clone and metadata `Repo`/`SourceCode` target FluxNews.
Historical Flutter recipes remain preserved and continue to reference their
historical root layout. The native recipe removes `Archived/Flutter` only from
its disposable build workspace before scanning; the repository archive itself
is retained. No scanner-ignore exception was added.

The native `FLUX_NATIVE_COMMIT` placeholder remains a release-preparation
template and is replaced only with an explicitly selected source SHA.

Release orchestration is scoped to `KevinCFechtel/FluxNews`, remains manually
dispatched, and retains validation mode, main-only release rules, per-job
permissions, reproducibility checks and immutable-tag checks.

The FluxNews `release-testing` environment exists and is restricted to
`main`. Signing credentials remain repository/environment configuration and
were not copied through Git history. A real isolated signing run is still
required before release acceptance.

The first native Android tag is intentionally a manual operation:
`android/v3.0.0` is not present yet. The release workflow must therefore be
used in an order that does not attempt to create an already existing manual tag.

## Weblate localization

Weblate migration is complete.

The Hosted Weblate project now contains the active native components:

- Android
- iOS
- macOS
- shared Glossary

Android remains the repository-backed component. iOS, macOS and Glossary share
that repository connection via `weblate://flux-news/android`.

The repository-wide Weblate webhook is active and the previous webhook warning
has cleared.

### Android

- source language: English
- translations: DE/ES/GL/NL/TA/TR
- mask: `android/app/src/main/res/values-*/strings.xml`
- source: `android/app/src/main/res/values/strings.xml`
- GitHub Pull Request workflow
- source-string management disabled

### iOS

- source of truth: `apple/ios/FluxNews/Localizable.xcstrings`
- XLIFF handoff: `apple/ios/Weblate/*.xliff`
- XLIFF 1.2 with Apple extensions
- DE/ES/GL/NL/TA/TR exposed to Weblate
- existing translation/review states preserved
- structural XLIFF validation is part of the iOS CI gate

### macOS

- source of truth: `apple/macos/FluxNews/Localizable.xcstrings`
- XLIFF handoff: `apple/macos/Weblate/*.xliff`
- XLIFF 1.2 with Apple extensions
- DE/ES/GL/NL/TA/TR exposed to Weblate
- German XLIFF targets are populated from the existing reviewed macOS catalog
- ES/GL/NL/TA/TR remain target-free until human review
- the macOS validator checks source-unit parity and exact German target parity

### Glossary

A shared repository-backed TBX glossary is stored under
`Weblate/Glossary/*.tbx` and used project-wide. It contains a small set of
cross-platform product terminology and non-translatable product/project names.

The optional Hosted Weblate GitHub App migration may still be considered as a
maintenance improvement, but it is not required for the completed Weblate
cutover.

## Old Flux repository retirement

The old `KevinCFechtel/Flux` repository has been retired from active automation.

At commit `6778a3b08e7c052ef8c67f867eae9dd67b772bbe` its root GitHub Actions
workflows and Dependabot configuration were moved to
`Archived/GitHubAutomation/2026-11-15/`. They are retained only as historical
reference and are no longer active GitHub automation.

The previously open Flux pull requests were closed; there are currently no open
pull requests in the old repository.

## Completed migration milestones

The remote cutover is no longer pending. Relevant completed milestones include:

- native migration merged into FluxNews
- selective CI and mandatory `CI Gate` introduced
- Android signing-property ignore protection added
- old Flux automation archived and old open PRs closed
- FluxNews branch protection/ruleset configured
- repository security settings reviewed
- Weblate Android/iOS/macOS components completed
- shared Weblate glossary added
- German macOS translations exposed to Weblate

## Remaining release-readiness work

The remaining work is no longer repository migration; it is release readiness.

Before the first native application release:

1. Audit selective CI coverage for `core/**`, including appropriate
   F-Droid/ABI coverage, without broadening CI unnecessarily.
2. Review and merge current Dependabot updates one by one, prioritizing security
   and maintained dependencies.
3. Resolve the strict RustSec baseline where fixes are available. Do not add
   ignore lists or suppressions for `ctutils`, `libsqlite3-sys`,
   `basic-toml` or `rustix`.
4. Run an isolated Android signing verification and confirm the expected signing
   fingerprint without exposing secret values.
5. Test upgrade/signature compatibility from the last published Flutter Android
   build to the native Android build.
6. Complete the native F-Droid acceptance gates in
   `docs/FDROID_OPEN_GATES.md`, including reproducibility and fdroiddata
   cutover.
7. Validate iOS TestFlight/App Store archive/export behavior.
8. Validate macOS App Sandbox/App Group/signing and Mac App Store
   archive/export/Transporter behavior.
9. Decide the exact release/tag ordering. The user creates
   `android/v3.0.0` manually; automation must not independently create the same
   tag.
10. Create a durable backup of the 38 local historical archive refs before any
    cleanup.
11. Review `README.md`, `PRIVACY.md`, store metadata and screenshots against
    the native 3.0.0 behavior before publication.
12. Revisit the Saved Media bootstrap compatibility URL separately.

No tag, GitHub Release, store upload or F-Droid submission is authorized merely
by completion of this migration document.
