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
- **Known red baseline (18 October 2026)**: `paste 1.0.15` via `lofty 0.22.4`;
  `rustls-pemfile 2.2.0` via `ureq 2.12.1` /
  `rustls-native-certs 0.7.3`; `rustybuzz 0.20.1` via
  `usvg 0.45.1`; and `ttf-parser 0.25.1` via
  `usvg 0.45.1` (`fontdb` and `rustybuzz`).
  All four require removal from the **resolved Cargo.lock** before
  dependency remediation is complete, not just bumping parent manifest
  version requirements.
- Do not skip required Android/Rust/Apple gates for Dependabot PRs, nor add
  automatic full F-Droid, device or release builds to this security workflow.
- Before merging changes to `rustls-platform-verifier`, `jni`, `uniffi`,
  `ureq` or other major dependency versions, assess API changes, rebuild and
  validate all affected clients, and preserve Android system/user CA trust.
- GitHub scheduled workflows execute from the default branch only.
  Dependabot version updates must also be activated on the default branch.
  After migration, install the same setup in **FluxNews**, where the
  authoritative development/release workflow will reside.

Policy detail: `docs/DEPENDENCY_MAINTENANCE.md` (documentation PR #67).
