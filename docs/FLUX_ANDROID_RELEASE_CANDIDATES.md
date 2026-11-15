# Flux: Unified release process (Android, iOS, macOS)

The manual `.github/workflows/release.yml` runs in **Flux**, prior to the FluxNews repository cutover. It accepts the exact `scope` (android, ios, macos, all), `version_name`, immutable full `source_sha` on main, and `mode` (validate or release). Selected version names must match the respective committed `Build/versions/<platform>.properties`; existing date-based versionCodes remain unchanged.

- validate: run the Rust workspace regression gate once, iOS/macOS tests for selected platforms, and for Android the existing F-Droid recipe/scanner/unsigned source-build gate.
- release: the same selected gates; Android additionally runs two independent same-SHA F-Droid builds, compares their exact APK bytes, signs the unsigned APK with the developer key and checks package/version/fingerprint; only then publish to GitHub Releases in **Flux**.
- Tags: android/vX.Y.Z, ios/vX.Y.Z, macos/vX.Y.Z independently. Scope all requires identical version and SHA for all platforms and creates all three tags plus vX.Y.Z, **one** combined GitHub Release.
- Android release assets are signed APK and checksum. iOS/macOS Releases contain test status and notes, not an unverified IPA/PKG. App Store exports and uploads remain manual.
- No F-Droid GitLab submission or Play publication. Cutover to FluxNews remains separate and requires explicit authorization.

## Signing secrets

The `release-testing` GitHub Environment should be restricted to main and require manual deployment approval. In Flux, the following **existing FluxNews names are currently configured as Repository Secrets** and are consumed only by the signer job, which is bound to `release-testing`. This is acceptable for the pre-cutover test; long term, move them to Environment Secrets for tighter exposure:

- `KEYSTORE_BASE64`
- `KEYSTORE_PASSWORD`
- `KEY_PASSWORD`
- `KEY_ALIAS`

The signing job explicitly checks the existing developer certificate SHA-256 `fee5401bc9d59cf5a8a461ba9698c482e87ed8ffb9258786a3d01d0356ea2ebb`. **Do not use a Play upload key if it has a different fingerprint.** Secret configuration and trust are controlled in GitHub settings, not by this PR.

The full release mode requires a successful exact same-SHA reproducibility comparison; it can fail if native source builds are not byte-identical. That is a blocker to that release mode, not permission to bypass the comparison. A normal CI/validation run uses no signing secrets. No release or tag is created from a push or PR.

## Safety and preflight

- Choose a full immutable SHA on `main`. Old tags are never moved. Each failed build requires a new fixed SHA and new mandatory checks.
- Only the publishing job gets `contents: write`, and only the signer gets the four environment secrets.
- Partial promotion is fail-closed. If tag creation has begun and a later GitHub operation fails, the workflow reports the tags it can observe and requires manual recovery. A rerun is rejected by preflight while any immutable target tag exists; never reuse, move, delete, or overwrite tags automatically.
- FD-01 user-installed CA is owner-accepted residual risk. This release process does not reopen that device test.

## Automated workflow contract

`Release script contracts` validates the release-related workflow YAML with pinned `actionlint` v1.7.12 and runs `Build/test-release-workflow-contract.py`. These checks are intentionally build-free: they cover the four scopes, selective gates, one Rust gate, Android F-Droid reproducibility/signing dependencies, tag sets, restricted write permissions, signing secret names, and partial-promotion fail-closed behavior without starting Android, F-Droid, or Apple builds.

## Verified Android release — 20 October 2026

The **Flux** pre-cutover release workflow completed successfully for Android 3.0.0. This is a verified GitHub release in Flux, **not** an official F-Droid submission, Google Play publication, or FluxNews repository cutover.

- Successful workflow: [Flux scoped release #39410044142](https://github.com/KevinCFechtel/Flux/actions/runs/39410044142).
- Source SHA and workflow revision: `75022c001b5ad0d0f3935c0846fb5c59f5faac87`; version `3.0.0`, Android build number `2026101801`.
- Passed jobs: preflight, Rust tests, Android tests, both independent F-Droid source builds, byte-for-byte comparison, APK developer signing, and GitHub publication. iOS/macOS jobs were correctly skipped for Android scope.
- Published GitHub release: [android/v3.0.0](https://github.com/KevinCFechtel/Flux/releases/tag/android/v3.0.0). The release job completed successfully; this does not assert acceptance by the official F-Droid repository.
- Signing uses the developer certificate SHA-256 `fee5401bc9d59cf5a8a461ba9698c482e87ed8ffb9258786a3d01d0356ea2ebb`. An isolated signing verification had already passed in [#39382484009](https://github.com/KevinCFechtel/Flux/actions/runs/39382484009).

### Failed attempt and corrective action

[Release run #39406899392](https://github.com/KevinCFechtel/Flux/actions/runs/39406899392) used workflow revision `75022c00` but an older **source_sha** `11f7b35e5052ee6e6e9b1a9bad93c1d5a9b3eafd`. Rust, Android, both F-Droid builds and comparison passed, but signing failed with `Wrong developer signing certificate`: the signing job checks out **source_sha**, so it ran the older fingerprint parser from that source commit. The parser fix is included in `75022c00`, and using that SHA for the successful release resolved the mismatch. Do not confuse the workflow revision (`head_sha`) with the dispatched `source_sha`; verify both before starting a release.

The temporary `.github/workflows/signing-diagnostics.yml` was removed from `main` in [`1e51a6e`](https://github.com/KevinCFechtel/Flux/commit/1e51a6e96ff43f09d84d25de0c8723815cc07153) after successful end-to-end verification. The regular `.github/workflows/release.yml` remains in place. No diagnostic workflow should be run for routine releases.

### Remaining boundaries

The successful Flux release demonstrates same-SHA reproducibility, signing and GitHub promotion for this candidate. It **does not** close F-Droid's historical Flutter-to-native signature/update acceptance, official upstream submission, or FluxNews cutover. Consult [FDROID_OPEN_GATES.md](FDROID_OPEN_GATES.md) before declaring official F-Droid readiness. A follow-up hardening task is to prevent a stale source SHA from silently selecting an outdated release signing script; do not change the source SHA of an existing immutable tag.
