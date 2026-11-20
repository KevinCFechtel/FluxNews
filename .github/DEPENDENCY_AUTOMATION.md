# Dependency update and security automation

This folder configures **visibility and review**, not automatic merges or
publishing. Cargo, Gradle and GitHub Actions version updates are proposed by
Dependabot. The separate `dependency-security.yml` workflow runs an isolated
RustSec advisory check daily and whenever the Rust manifests/lockfile change.

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
- The RustSec job uses `cargo audit --deny warnings`: **known vulnerabilities
  AND unmaintained dependency warnings are blocking**, including transitive
  crates. Do not add ignore lists, blanket allow rules, or downgrade the
  exit status to obtain a green check. A clean audit is still not proof that
  all libraries are current, safe or legally usable in F-Droid.
- The four-item red baseline recorded on 18 October 2026 (`paste`,
  `rustls-pemfile`, `rustybuzz`, `ttf-parser`) is historical and no
  longer describes the current resolved graph. Use the current
  `core/Cargo.lock` plus the strict RustSec job for present blockers.
  Outstanding current work includes resolved occurrences associated with
  `ctutils`, `libsqlite3-sys`, `basic-toml` and `rustix`; take the
  exact advisory/dependency chain from the current audit output. No finding is
  cleared by merely changing a parent manifest constraint.
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
