# Dependency maintenance and security policy

> **Decision: 18 October 2026; PR regression-gate amendment: 20 November 2026.**
> This policy applies to the active **FluxNews** repository. The old Flux
> repository is retired. This policy does not by itself approve a release,
> merge, dependency major-version upgrade, or official F-Droid submission.

## Why this is necessary

Green unit/integration tests are **not** an assertion that dependencies are
up-to-date or free of disclosed vulnerabilities. The dependency set has moved
substantially since the 18 October baseline (for example UniFFI and ureq are on
newer generations), so old inventory tables below must not be read as the
current resolved graph.

Use the current `core/Cargo.lock`, current Dependabot PRs and the strict
RustSec workflow as the source for present dependency status. Do **not** infer
that a crate is vulnerable merely because an old baseline listed it; investigate
the advisory and the actually resolved current version.

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
  migration gates and the PR security-regression gate are satisfied. Existing
  RustSec findings do not prevent independent improvements; new findings do.
  No untested bulk version bumps, skipped
  required CI, automatic merge or release. Apply current versions by
  **making the code compatible**, not by disabling tests or suppressing
  advisories.

## Normal PR acceptance: no new RustSec findings

Dependency maintenance must improve the repository without requiring a full
cleanup of unrelated inherited findings in every PR. This is the normal merge
policy, not an exception or a maintainer override.

`Build/rustsec_gate.py --base <full-PR-base-SHA> --output <report-directory>`
audits `core/Cargo.lock` from the exact PR base commit and the proposed GitHub
merge commit. It does not resolve manifests or execute dependency build scripts.
Both audits use one clean, private checkout of the current RustSec advisory
database, with independent fetching disabled. The source SHAs, database SHA,
complete JSON/stderr reports and comparison are retained as CI artifacts; the
job summary lists new, existing and resolved findings with advisory links.
Before freezing that database, preparation audits refresh crates.io metadata
for both lockfiles, including removed packages. This preserves yanked-package
checks rather than relying on whichever sparse-index entries a runner happens
to have cached. Preparation reports are retained too; reported registry-check
errors block the gate even if cargo-audit otherwise returns valid JSON.

- **Pass:** existing findings remain, findings are fixed, or both.
- **Fail:** a new advisory/package/provenance/kind combination appears, another
  affected version of an existing package is added, or a newly yanked version
  is introduced.
- A package version change alone is not a new advisory. Both resolved versions
  remain visible in the raw reports. The comparison is not a proof of general
  runtime safety or exploitability; affected platform/runtime checks still apply.
- A newly published advisory affecting both base and merge is reported as
  inherited, rather than attributed to an unrelated PR.
- Missing/deleted lockfiles, inaccessible commits/databases, malformed or
  filtered audit output, changed database snapshots and unexpected command
  failures **block the gate**. The comparison never treats missing evidence as
  zero findings.

No checked-in baseline, advisory ignore list or blanket warning suppression is
used. Audits run outside the repository configuration directory and reject
reported ignores, severity thresholds and target filters. The same rules apply
to human-authored and Dependabot PRs.

The selective PR workflow runs this check for Rust lockfile/manifests, audit
configuration and audit/CI-tooling changes. It is a dependency of the existing
required **CI Gate**; a selected missing/skipped/failed audit therefore blocks
merging without needing another GitHub ruleset exception. Docs-only or unrelated
UI changes do not start dependency scans or unnecessary native builds.

## Full monitoring and strict unmaintained-dependency release gate

A dependency which is no longer maintained is an **unacceptable release
risk** for Flux, even if no specific exploit has yet been disclosed. The
project must not ship a new release while RustSec reports a vulnerability
**or an unmaintained dependency** in the resolved dependency graph.
This includes **transitive** packages. Replacing the dependency or migrating
its parent crate is mandatory; no blanket ignore list, downgraded exit status
or permanent exception is accepted.

The daily/manual/main-push scan runs the full audit with
`cargo audit --deny warnings`, deliberately including RustSec's maintenance
warnings, through `Build/rustsec_gate.py` without `--base`. A red result remains
visible and actionable, but is not a blanket PR merge veto. Exit status is not
downgraded: the script exits 1 for findings and 2 for incomplete evidence.

The release workflow separately runs that same full audit on its exact candidate
SHA, without a PR baseline, for every platform and validation/release mode.
Android signing and all tag/publication paths explicitly require its successful
result. Passing a PR regression check is **not** release approval. A clean full
audit is necessary for release readiness, not proof of complete security or
up-to-date dependencies.

**Historical blocking findings (18 October 2026):** the then-resolved graph
contained `paste`, `rustls-pemfile`, `rustybuzz` and `ttf-parser` through
the dependency chains documented in the original audit. Those four findings
are **not the current baseline** and must not be used to describe today's
`Cargo.lock`.

The strict **release** gate remains unchanged: every current RustSec vulnerability or
unmaintained-warning finding must actually disappear from the resolved
`core/Cargo.lock`; changing only a manifest constraint is insufficient.
At the current FluxNews baseline, the outstanding strict-RustSec work is tracked
against the resolved occurrences including `ctutils`, `libsqlite3-sys`,
`basic-toml` and `rustix`. The exact advisory chain must be taken from the
current RustSec output rather than copied forward from this historical table.

**Daily work:** an update which fixes three inherited findings and leaves two
unchanged is mergeable once the regression gate and affected platform checks
pass. The two remaining findings retain their tracked next actions/owners and
remain blocking for release. No per-PR policy override is needed.

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
3. Run the isolated **PR regression gate** for dependency/audit changes through
   `CI Gate`. Separately run the **daily strict RustSec scan** of
   `core/Cargo.lock`, after relevant changes land on `main`, via manual dispatch,
   and on exact release candidates. Neither audit builds Rust targets, Android
   apps or Apple apps; only the pinned audit tool is installed. Full scans
   **fail for vulnerabilities, unmaintained crates and other RustSec warnings**.
   Preserve output and do not suppress findings.
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

## Historical 18 October dependency inventory

The following table records the B2-branch inventory that motivated the update
work. It is **historical evidence, not the current dependency list**. Current
versions and blockers must be read from `core/Cargo.lock`, Dependabot and the
strict RustSec result.

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

## Implementation and repository boundaries

- The policy, Dependabot configuration and strict security CI have been carried
  into **FluxNews**; the repository cutover is complete.
- All active dependency monitoring and security/release CI now run in FluxNews.
  The retired Flux repository is historical reference only.
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


## Current maintenance ownership

This document is the single operational owner for dependency/security work.
The completed repository-migration record and historical post-replacement plans
must not maintain parallel dependency task lists.

Current maintenance rules include:

- review Dependabot updates individually or in small compatible groups, with
  security and unmaintained dependencies prioritized;
- resolve every current strict RustSec vulnerability/unmaintained warning where
  a maintained stable replacement or update is available;
- do not use ignore lists or warning suppression to clear `ctutils`,
  `libsqlite3-sys`, `basic-toml`, `rustix`, or successor findings;
- determine the actual current blocker set from `core/Cargo.lock`, Dependabot
  and the strict RustSec workflow rather than from historical inventories.

Release readiness depends on the required dependency/security gates passing; it
does not turn this policy into a release-publication authority.

### Reviewed PR #155 candidate — 20 November 2026

The candidate updates `rusqlite` to **0.43.0** with bundled
`libsqlite3-sys 0.40.0`, and refreshes the compatible transitive packages
`ctutils` to **0.4.8** and `rustix` to **1.1.6**. No application schema,
backup format, UniFFI version or platform trust policy changes are involved.
The strict local audit of this candidate reports **zero vulnerabilities** and
the two unmaintained-package findings below. It still exits unsuccessfully;
this record is not a security-gate waiver or permission to merge/release.

| Remaining finding | Affected path / concrete blocker | Next action | Owner | Review by |
| --- | --- | --- | --- | --- |
| `chrono 0.4.45` — [RUSTSEC-2026-0543](https://rustsec.org/advisories/RUSTSEC-2026-0543.html) | Direct Core dependency; no patched version. Used by Miniflux RFC 3339 parsing/UTC normalization, retention calculations, media timestamps and runtime retry metadata. | Replace with a maintained date/time crate in a separate focused change; preserve timestamp serialization, offset handling, retention cutoffs and the existing native API. | Repository maintainer / dependency maintenance | 2026-11-27 |
| `basic-toml 0.1.10` — [RUSTSEC-2026-0374](https://rustsec.org/advisories/RUSTSEC-2026-0374.html) | `flux-uniffi → uniffi 0.32.2 → uniffi_bindgen → askama 0.16.1 → askama_macros → askama_derive → basic-toml`. Current stable UniFFI and Askama still resolve it. Askama's replacement with `toml` is upstream in [3863808cf594054f7644979ed92caaafc878f378](https://github.com/askama-rs/askama/commit/3863808cf594054f7644979ed92caaafc878f378), but is not yet released. | Track/request a stable Askama release containing that fix and validate Swift/Kotlin binding generation. If a source pin is needed before that release, obtain explicit review of the exact upstream revision/provenance; do not silently add a Git patch, fork or advisory ignore. | Repository maintainer / dependency maintenance | 2026-11-27 |

Recheck the current advisory database before acceptance; this candidate snapshot
does not replace `cargo audit --file core/Cargo.lock --deny warnings`.
