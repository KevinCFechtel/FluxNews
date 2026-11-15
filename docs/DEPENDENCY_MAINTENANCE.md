# Dependency maintenance and security policy

> **Decision: 18 October 2026.** Applies to native Flux development now and
> to **FluxNews after repository migration**. This policy does not approve a
> release, merge, dependency major-version upgrade, or official F-Droid submission.

## Why this is necessary

Green unit/integration tests are **not** an assertion that dependencies are
up-to-date or free of disclosed vulnerabilities. In the 18 October inventory,
the Cargo workspace still pins `rustls-platform-verifier = "=0.5.3"`,
`jni = "0.21"`, `ureq = "2.12"`, `rusqlite = "0.37"`, `uniffi = "0.29"`
and other older API generations. Unlike most of the recent Android Gradle
dependencies, these versions had not received an independently recorded
freshness/compatibility assessment.

Do **not** declare all such versions vulnerable: `Cargo.lock` shows the
versions actually built, and a RustSec advisory check plus investigation of
each finding is required before making security claims.

## Update-first maintenance policy

**Default: regularly adopt the newest stable upstream dependency generations, including
major-version changes.** A build that happens to work on an old version is not a
reason to retain it. Compatibility work is part of dependency maintenance,
not an indefinite blocker or a separate optional project. Security-only patching
is emergency mitigation, **not** completion of an outdated dependency upgrade.

- At least weekly, compare all direct Rust, Gradle/Kotlin/Android and GitHub
  Actions dependencies against the latest **stable** releases, and review the
  actually resolved lockfile and relevant transitive dependencies. Include
  compiler/SDK/NDK/Xcode and the rustls Kotlin/Rust subcomponent relationship
  in a periodic toolchain review; Dependabot alone cannot cover all of them.
- **Do not exclude major upgrades.** Offer them in Dependabot and work through
  API/source/FFI migrations, adapting code, tests and generation scripts.
  Group dependencies according to compatibility boundaries rather than
  applying the largest number of unrelated upgrades in one unreviewable PR.
- Every outdated major version must have an active upgrade PR or a tracked
  actionable blocker, with affected APIs, a concrete next action, owner and
  review date. A green CI or vague fear of breakage is **not** an accepted
  blocker. Revisit blockers at least weekly; do not roll them over silently.
- Urgent advisories receive an immediate targeted fix if required, followed
  by the ordinary **current-stable upgrade**. Security fixes and currency
  are two separate success criteria.
- Merge only after affected Rust, Android, Apple, F-Droid and runtime trust/
  migration gates are satisfied. No untested bulk version bumps, skipped
  required CI, automatic merge or release. Apply current versions by
  **making the code compatible**, not by disabling tests or suppressing
  advisories.

## Strict unmaintained-dependency release gate

A dependency which is no longer maintained is an **unacceptable release
risk** for Flux, even if no specific exploit has yet been disclosed. The
project must not ship a new release while RustSec reports a vulnerability
**or an unmaintained dependency** in the resolved dependency graph.
This includes **transitive** packages. Replacing the dependency or migrating
its parent crate is mandatory; no blanket ignore list, downgraded exit status
or permanent exception is accepted.

The workflow therefore enforces `cargo audit --file core/Cargo.lock --deny
warnings`, deliberately including RustSec's maintenance warnings. A red
result is actionable and must remain visible until the dependency is replaced.
Passing this check is necessary for release readiness, not sufficient
proof of complete security or up-to-date dependencies.

**Current blocking findings (18 October 2026):**

| Unmaintained crate | Locked version | Direct dependency chain |
| --- | --- | --- |
| `paste` | 1.0.15 | `lofty 0.22.4` |
| `rustls-pemfile` | 2.2.0 | `ureq 2.12.1` → `rustls-native-certs 0.7.3` |
| `rustybuzz` | 0.20.1 | `usvg 0.45.1` |
| `ttf-parser` | 0.25.1 | `usvg 0.45.1` → `fontdb 0.23.0` and `rustybuzz 0.20.1` |

These **must actually disappear from `core/Cargo.lock`** after upgrading or
replacing `lofty`, `ureq`, `usvg`, or transitive dependencies. Updating a
manifest constraint without rebuilding and verifying the lockfile does not
satisfy the gate.

**One-time transition:** landing the strict policy/CI into `main` makes
already-present findings visible and can initially create an expected red
security check. This is not a waiver for any release or later dependency
acceptance. Work on dependency updates continues as the highest priority
until the strict security check AND all affected platform checks pass.

## Automated monitoring and CI costs

1. Configure GitHub Dependabot **version updates including major versions**
   for `cargo` at `/core`, `gradle` at `/android` and `github-actions`
   at `/`. Review Cargo/Gradle weekly and Actions monthly, with a meaningful
   PR budget that does **not** hide unreviewed majors behind a two-PR queue.
2. Group patch/minor updates to control CI load, and actively migrate **major
   updates** as small compatibility-related batches, not postponed indefinitely.
   No auto-merge and no auto-release. Dependabot
   **security updates** and GitHub vulnerability alerts must remain enabled
   in repository settings; verify that their alert visibility and notification
   routing actually work after cutover.
3. Run an isolated, **daily strict RustSec scan** of `core/Cargo.lock`
   (`cargo audit --deny warnings`), without building Rust targets, Android
   apps, or Apple apps. Run it after `core/Cargo.lock` changes and via
   manual dispatch. **Fail for vulnerabilities, unmaintained crates and
   other RustSec warnings.** Preserve output, do not suppress findings.
4. Dependabot's routine PRs should not themselves cascade redundant full
   test suites. Limit open PRs, group updates and use existing per-workflow
   `concurrency.cancel-in-progress` behavior; Rust/Android/Apple CI remain
   mandatory for changes they actually affect. Never weaken required
   merge gates simply because a change comes from Dependabot.
   Use paths to avoid unrelated platform builds. Do not start an
   additional F-Droid source build when another equivalent immutable-SHA
   F-Droid gate is already running.
5. Dependabot creates suggested patches **rather than evaluating** Kotlin/
   Rust JNI alignment, UniFFI-generated code, build IDs or the exact
   required source revision of external Git submodules. Enforce those
   relationships through project tests and human review.

## Mandatory dependency review before acceptance

For each dependency version change, verify:
- **latest release and date** from the upstream registry/release notes,
  including security advisories and any documented MSRV, Gradle, Kotlin,
  Swift, Xcode, or Android SDK constraints;
- actual locked versions (`core/Cargo.lock`, Gradle dependencies),
  including relevant transitive dependencies and build toolchains;
- direct and indirect license/provenance suitability (especially F-Droid
  restrictions on prebuilt binaries);
- source API and behavioral changes, with particular attention to
  Android CA store, **user-installed CA trust**, TLS failure behavior,
  networking, database migration, media decoding and playback;
- relevant tests on all affected targets, both routine CI and specific
  device/integration checks when required.

Prioritize both security **and latest stable versions**. Do not create one
unreviewable PR that changes all unrelated major APIs at once, but also do not
keep old major generations solely to avoid adapting product code. For any
necessary temporary pin, require a reproducible blocker, a concrete follow-up
and a dated review; keep its owner-visible status current. Release promotion
must not rely on a skipped, missing, or failed required gate.

## Baseline findings to investigate (inventory, not accepted upgrades)

| Component | `Cargo.lock` on B2 branch, 18 October | Initial decision |
| --- | --- | --- |
| rustls-platform-verifier / Android companion | 0.5.3 / 0.1.1 | **P0:** evaluate 0.7.1 / 0.2.0 alongside JNI 0.22 and rebuilding Kotlin component from source, then rerun Android CA-trust cases |
| ureq | 2.12.1 | **P1:** newer v3 has an incompatible transport API: evaluate independently of verifier |
| rusqlite | 0.37.0 | **P1:** database/runtime compatibility and migrations |
| uniffi | 0.29.5 | **P1:** generated Swift/Kotlin bindings and release scripts must change together |
| jni | 0.21.1 | **Coupled to verifier:** no isolated update |
| lofty | 0.22.4 | **P2:** media metadata and artwork extraction regression checks |
| rand, argon2, html5ever | 0.8.8, 0.5.3, 0.39.0 | **P2:** check API changes / security findings, do not assume vulnerabilities |
| AGP, Kotlin, Gradle | 9.4.0, 2.4.20, 9.7.1 | Recently refreshed, still monitor updates and wrapper provenance |

The original pinned verifier was accepted for **Android TLS behavior**,
not for being the newest version. A documented compatibility proof must
not be misread as a dependency freshness assessment.

## Implementation and migration boundaries

- Prepare the policy, Dependabot configuration and lightweight security CI
  in `Flux`; carry them over during the non-publishing migration.
- After cutover, all dependency monitoring and security/release CI run in
  `FluxNews` (and can no longer be controlled from `Flux`).
- Keep documentation separate from source version changes so docs-only
  commits do not trigger costly Rust/Apple/F-Droid CI.
- Carry out a tracked series of compatibility-focused current-stable updates:
  (a) rustls-platform-verifier + Android JNI/Kotlin source and TLS trust,
  (b) ureq transport, (c) rusqlite/storage, (d) UniFFI bindings across all
  platforms, then other audio/rendering/crypto dependencies. These are **upgrade
  tasks**, not indefinite recommendations to remain on old versions.
- Changes to critical or coupled dependencies should be tested on isolated
  PRs with **one consolidated verification cycle per candidate SHA**.
- A passing F-Droid recipe/build on a version is not a substitute for the
  AAR provenance, same-SHA reproducibility or Flutter-to-native signed
  upgrade acceptance gate.
