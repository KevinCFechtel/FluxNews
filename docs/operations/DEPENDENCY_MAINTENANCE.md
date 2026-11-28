# Dependency maintenance and security policy

> **Decision: 18 October 2026; PR regression-gate amendment: 20 November 2026;
> non-blocking release maintenance warnings: 28 November 2026.**
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

## Full monitoring and release security gate

**Release policy amended on 28 November 2026:** an unmaintained dependency is
tracked maintenance debt, not by itself a reason to withhold a security update.
Full daily/manual/main-push and exact-candidate release audits use these rules:

- **Block:** vulnerabilities, unsoundness, notices and yanked packages.
- **Warn, do not block:** findings whose kind is exactly `unmaintained`,
  including transitive dependencies.
- **Block:** failed or incomplete audits, filtered reports, missing evidence or
  registry/database errors. Missing evidence is never a clean audit.

`Build/rustsec_gate.py` still invokes `cargo audit --deny warnings` and retains
the complete, unfiltered JSON and raw exit status. The parser validates that
status against all reported findings. The gate then explicitly classifies
`unmaintained` as non-blocking **only in full-audit mode**; it does not ignore
advisories or suppress their reporting. Full summaries separate blocking
findings from maintenance warnings, and GitHub warning annotations make every
current unmaintained dependency visible even when the job succeeds.
`comparison.json` retains all findings and also records the blocking subset.
The script exits 1 for policy-blocking findings, 0 for a complete audit with
no blockers (possibly with maintenance warnings), and 2 for incomplete evidence.

The PR regression gate is unchanged: new findings of **any** kind, including
new maintenance warnings or additional affected copies, block the PR. Existing
findings may remain while an independent security fix proceeds.

The release workflow runs the full audit on its exact candidate SHA, without a
PR baseline, for every platform and validation/release mode. Android signing and
all tag/publication paths still require its successful result. A PR comparison
cannot waive an existing vulnerability for release. A passing full gate is
necessary for release readiness, not proof of complete security or currency.

**Historical blocking findings (18 October 2026):** the then-resolved graph
contained `paste`, `rustls-pemfile`, `rustybuzz` and `ttf-parser` through
the dependency chains documented in the original audit. Those four findings
are **not the current baseline** and must not be used to describe today's
`Cargo.lock`.

Every blocking finding must disappear from the resolved `core/Cargo.lock`;
changing only a manifest constraint is insufficient. PR #155 resolved the
inherited `ctutils`, `libsqlite3-sys` and `rustix` findings. Dated audit evidence
and the current `chrono` replacement, `url` fix and remaining `basic-toml`
maintenance ownership are recorded below.
Determine the exact current advisory set from fresh audit output, not from
the historical inventory.

**Daily work:** an update which fixes three inherited findings and leaves two
unchanged is mergeable once the regression gate and affected platform checks
pass. Remaining findings retain their tracked next actions/owners; only the
release-blocking kinds above prevent release. No per-PR policy override is needed.

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
   **fail for vulnerabilities and other blocking kinds**, while unmaintained
   crates remain explicit non-blocking warnings. Preserve all output.
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
- The initial compatibility-focused upgrade sequence and 18 October inventory
  are historical, not an active taskboard. Further current-stable updates
  should use small compatible groups and the current resolved graph; do not
  reopen completed verifier/JNI, transport, storage or binding migrations from
  that inventory. The November PR dispositions are recorded below.
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
- do not use ignore lists or warning suppression to clear `chrono`,
  `basic-toml`, or successor findings;
- determine the actual current blocker set from `core/Cargo.lock`, Dependabot
  and the strict RustSec workflow rather than from historical inventories.

Release readiness depends on the required dependency/security gates passing; it
does not turn this policy into a release-publication authority.

### November dependency PR closure review — 21 November 2026

GitHub PR states and the resolved lockfile were checked on 21 November.
The merged updates and superseded proposals below are **not open dependency
tasks**. Routine future dependency review continues under the policy above.

| PR | Scope | Verified disposition |
| --- | --- | --- |
| [#158](https://github.com/KevinCFechtel/FluxNews/pull/158) | Gradle wrapper and F-Droid pin to 9.9.2, official checksums and alignment contract | Merged 20 November |
| [#187](https://github.com/KevinCFechtel/FluxNews/pull/187) | Required PR RustSec regression gate; separate strict monitoring/release audits | Merged 20 November; no per-PR policy exception remains |
| [#155](https://github.com/KevinCFechtel/FluxNews/pull/155) | `rusqlite 0.43.0`, `libsqlite3-sys 0.40.0`, `ctutils 0.4.8`, `rustix 1.1.6` | Merged 20 November; inherited findings for the latter three packages resolved |
| [#153](https://github.com/KevinCFechtel/FluxNews/pull/153) | Locked `ureq 3.5.2` and `ureq-proto 0.7.1` | Merged 20 November; #155 fixes retained |
| [#156](https://github.com/KevinCFechtel/FluxNews/pull/156) / [#157](https://github.com/KevinCFechtel/FluxNews/pull/157) | Coupled `resvg` / `usvg 0.50.0`, SVG regression tests and Dependabot compatibility group | #156 merged 20 November; #157 closed as superseded |
| [#188](https://github.com/KevinCFechtel/FluxNews/pull/188) | Locked `rand 0.10.4` | Merged 20 November |
| [#189](https://github.com/KevinCFechtel/FluxNews/pull/189) | Android Gradle Plugin 9.5.2 for application, library and test plugins | Merged 20 November |
| [#154](https://github.com/KevinCFechtel/FluxNews/pull/154) / [#192](https://github.com/KevinCFechtel/FluxNews/pull/192) | Replace the invalid compiler-ref update with independent Action SHA and explicit Rust 1.99.1 input, plus contract tests | #154 closed without merge; replacement #192 merged 21 November after full affected CI passed on `f4fdf604` ([run #44879665743](https://github.com/KevinCFechtel/FluxNews/actions/runs/44879665743)) |

No PR acceptance or implementation tasks remain for this reviewed batch.
The independent security/maintenance follow-ups below remain tracked. No automatic merge,
signing, publication or release approval is authorized by this closure record.

### Dated findings and current follow-up — 28 November 2026

The merged #155 update uses `rusqlite` **0.43.0** with bundled
`libsqlite3-sys 0.40.0`, and refreshes the compatible transitive packages
`ctutils` to **0.4.8** and `rustix` to **1.1.6**. No application schema,
backup format, UniFFI version or platform trust policy changes are involved.
The later strict monitoring audit
[#44795290191](https://github.com/KevinCFechtel/FluxNews/actions/runs/44795290191),
on the #188 merge SHA `0f710a528149f69fa54db607cbf49f32a4d2130d`,
still reports the two unmaintained-package findings below and exits
unsuccessfully. Both versions remain in the reviewed lockfile.
This is dated evidence under the former release policy, not a PR merge veto or
release approval. A fresh audit of commit `b3d7e9f17331e217dbf8b9b5831b9f0cf1cffa56`
on 28 November additionally reported `url 2.5.8`
([RUSTSEC-2026-0592](https://rustsec.org/advisories/RUSTSEC-2026-0592.html)).
The [27 November CI run](https://github.com/KevinCFechtel/FluxNews/actions/runs/46034675295)
reports the same three findings. The implementation changes below still require
the affected Actions to pass; no local build/test run or release approval is
implied by updating this record.

| Remaining finding | Affected path / concrete blocker | Next action | Owner | Review by |
| --- | --- | --- | --- | --- |
| `chrono 0.4.45` — [RUSTSEC-2026-0543](https://rustsec.org/advisories/RUSTSEC-2026-0543.html) | Replaced in Core and the lockfile with maintained `time 0.3.55`, using only UTC/standard RFC 3339 parsing. Existing publication keys, operational timestamp encodings, fixed-day retention and UniFFI records remain unchanged. | Validate timestamp, retention, sync/media and native regression coverage in Actions. | Repository maintainer / dependency maintenance | 2026-12-05 |
| `url 2.5.8` — [RUSTSEC-2026-0592](https://rustsec.org/advisories/RUSTSEC-2026-0592.html) | Manifest and lockfile updated to patched `2.5.9`; regression coverage for deeply nested `blob:` origins added. | Validate affected Actions and the full security audit before release. | Repository maintainer / dependency maintenance | 2026-12-05 |
| `basic-toml 0.1.10` — [RUSTSEC-2026-0374](https://rustsec.org/advisories/RUSTSEC-2026-0374.html) | `flux-uniffi → uniffi 0.32.2 → uniffi_bindgen → askama 0.16.1 → askama_macros → askama_derive → basic-toml`. Still maintenance debt, **not a full-audit release blocker**. Askama's replacement with `toml` is upstream in [3863808cf594054f7644979ed92caaafc878f378](https://github.com/askama-rs/askama/commit/3863808cf594054f7644979ed92caaafc878f378), but stable Askama remains `0.16.1` at this review. | Track a stable Askama release containing the fix and validate Swift/Kotlin generation. No unreleased Git pin, fork or advisory ignore. | Repository maintainer / dependency maintenance | 2026-12-05 |

Recheck the current advisory database before release acceptance; this dated snapshot
does not replace the complete audit and policy decision from `Build/rustsec_gate.py`.
