# Dependency update and security automation

This folder configures **visibility and review**, not automatic merges or
publishing. Cargo, Gradle and GitHub Actions version updates are proposed by
Dependabot. The reusable `dependency-security.yml` workflow performs PR
regression checks through the required `CI Gate`, plus independent full
daily/main-push/manual scans and full exact-SHA release security checks.

**Operational requirements**

- Enable GitHub Dependency Graph, Dependabot Alerts and Dependabot Security
  Updates in repository settings. The YAML file alone cannot activate alerts.
- Version-update PRs are bounded to 8 open PRs per ecosystem to keep major
  upgrades visible, with routine patch/minor updates grouped. New stable
  major versions are actively targeted (including necessary source migrations),
  rather than skipped to protect existing pins. An old major needs an active
  upgrade PR or a concrete, dated blocker; do not rely on green CI as proof
  that using an old version is acceptable. Dependabot security updates
  may have independent behavior and must be reviewed immediately.
- `resvg` and `usvg` share the `svg-rendering` Cargo group for every update
  type, including breaking 0.x updates. They exchange `usvg::Tree` directly
  and must be upgraded together; the routine Cargo group excludes both.
- `dtolnay/rust-toolchain` pins a reviewed commit from upstream `master`, not
  a compiler-named ref. Dependabot can update the Action SHA independently;
  `with.toolchain` explicitly selects Rust `1.99.1`, with an immediate runtime
  version assertion in every consuming job. Compiler upgrades are separate,
  deliberate changes. `Build/test_rust_toolchain_contract.py` checks this
  separation, including release and diagnostic workflows; every workflow change
  selects the cheap contract gate. No Action updates are ignored or disabled.
- PRs compare base and proposed merge lockfiles against the **same** current
  advisory-database checkout. Existing findings remain visible but do not block
  independent improvements; new findings, additional affected versions, changed
  provenance and audit/comparison failures block `CI Gate`. No committed
  baseline or ignore list is used.
- Full daily and release audits retain `cargo audit --deny warnings` as the raw
  evidence source. `Build/rustsec_gate.py` validates the complete report and
  classifies only `unmaintained` as **non-blocking maintenance warnings**.
  Vulnerabilities, unsoundness, notices, yanked packages and incomplete audits
  still block. All findings remain in artifacts and summaries; unmaintained
  crates also produce GitHub warning annotations. PR regression rules above are
  unchanged, including newly introduced maintenance warnings.
  Signing/publication still require a successful full candidate-SHA gate.
  A passing PR comparison is not release approval or proof of dependency safety.
- The four-item red baseline recorded on 18 October 2026 (`paste`,
  `rustls-pemfile`, `rustybuzz`, `ttf-parser`) is historical and no
  longer describes the current resolved graph. Use the current
  `core/Cargo.lock` plus the strict RustSec job for present blockers.
  The November PR batch resolved the inherited `ctutils`, `libsqlite3-sys`
  and `rustix` findings in #155. The 28 November follow-up replaces `chrono`
  with `time`, patches `url`, and keeps `basic-toml` visible as non-blocking
  maintenance debt. These changes require affected Actions, not a repetition
  of the earlier merged PR batch. Current PR dispositions, audit
  evidence and remaining ownership are recorded only in
  `docs/operations/DEPENDENCY_MAINTENANCE.md`. No finding is cleared by merely
  changing a parent manifest constraint.
- Do not skip required Android/Rust/Apple gates for Dependabot PRs, nor add
  automatic full F-Droid, device or release builds to this security workflow.
- Before merging changes to `rustls-platform-verifier`, `jni`, `uniffi`,
  `ureq` or other major dependency versions, assess API changes, rebuild and
  validate all affected clients, and preserve Android system/user CA trust.
- GitHub scheduled workflows execute from the default branch only.
  Dependabot version updates are active in **FluxNews**, which is now the
  authoritative development/release repository. The old Flux repository is
  retired and must not be treated as the place to configure current automation.

Policy detail: `docs/operations/DEPENDENCY_MAINTENANCE.md`.
