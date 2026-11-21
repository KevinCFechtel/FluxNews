#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
RELEASE = (ROOT / ".github/workflows/release.yml").read_text()
FDROID = (ROOT / ".github/workflows/fdroid-native.yml").read_text()
CANDIDATE = (ROOT / "Build/check-release-candidate.sh").read_text()
SIGN = (ROOT / "Build/sign-release-apk.sh").read_text()
CONTRACT_CI = (ROOT / ".github/workflows/release-scripts.yml").read_text()
GRADLE_WRAPPER = (ROOT / "android/gradle/wrapper/gradle-wrapper.properties").read_text()
SECURITY = (ROOT / ".github/workflows/dependency-security.yml").read_text()
CI = (ROOT / ".github/workflows/ci.yml").read_text()
DEPENDABOT = (ROOT / ".github/dependabot.yml").read_text()

def fail(message: str) -> None:
    print(f"release workflow contract: FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)

def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)

# Dependabot's breaking 0.x updates must use the same compatibility group as
# routine SVG updates; the catch-all routine group must never claim either crate.
cargo_updates = DEPENDABOT.split('package-ecosystem: "cargo"', 1)[-1].split(
    '  - package-ecosystem:', 1
)[0]
svg_group = re.search(r"^      svg-rendering:\n((?:        .*\n)+)", cargo_updates, re.MULTILINE)
routine_group = re.search(r"^      cargo-routine:\n((?:        .*\n)+)", cargo_updates, re.MULTILINE)
require(svg_group is not None and routine_group is not None, "Cargo SVG/routine update groups are required")
require("patterns:" in svg_group.group(1) and "update-types:" not in svg_group.group(1),
        "SVG compatibility group must include every update type, including breaking 0.x changes")
exclusions = re.search(
    r"^        exclude-patterns:\n((?:          .*\n)+)", routine_group.group(1), re.MULTILINE
)
require(exclusions is not None, "Routine Cargo updates must exclude the coupled SVG crates")
for package in ("resvg", "usvg"):
    require(f'- "{package}"' in svg_group.group(1),
            f"{package} must belong to the SVG compatibility group")
    require(f'- "{package}"' in exclusions.group(1),
            f"{package} must not be claimed by the routine group")

def job_blocks(source: str) -> dict[str, str]:
    marker = "\njobs:\n"
    require(marker in source, "workflow has no jobs section")
    body = source.split(marker, 1)[1]
    matches = list(re.finditer(r"^  ([A-Za-z0-9_-]+):\n", body, re.MULTILINE))
    blocks: dict[str, str] = {}
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(body)
        blocks[match.group(1)] = body[match.start():end]
    return blocks

jobs = job_blocks(RELEASE)
required_jobs = {
    "preflight", "rust", "ios", "macos", "android-tests", "fdroid",
    "fdroid-repeat", "compare", "sign-android", "publish", "security",
}
require(required_jobs <= jobs.keys(), f"missing jobs: {sorted(required_jobs - jobs.keys())}")

require(re.search(r"options:\s*\[android,\s*ios,\s*macos,\s*all\]", RELEASE) is not None,
        "scope choices must be android/ios/macos/all")
require(re.search(r"options:\s*\[validate,\s*release\]", RELEASE) is not None,
        "mode choices must be validate/release")
require("bash Build/check-release-candidate.sh" in jobs["preflight"],
        "preflight must call the candidate checker")
require("refs/heads/main" in jobs["preflight"],
        "release dispatch must be guarded to main")
require('"$GITHUB_REPOSITORY" != KevinCFechtel/FluxNews' in jobs["preflight"],
        "release orchestration must be restricted to the FluxNews repository")

require("needs: preflight" in jobs["rust"], "Rust gate must depend only on preflight")
require("inputs.scope" not in jobs["rust"], "Rust gate must run once for every candidate scope")
require(jobs["rust"].count("cargo test --locked") == 1, "Rust tests must appear exactly once")
require("needs: preflight" in jobs["security"], "Security audit must follow release preflight")
require("uses: ./.github/workflows/dependency-security.yml" in jobs["security"],
        "Release must reuse the full RustSec audit")
require("source_sha: ${{ needs.preflight.outputs.sha }}" in jobs["security"],
        "Release security audit must inspect the exact candidate SHA")
require("base_sha:" not in jobs["security"], "Release audit must not grandfather existing findings")
require("if:" not in jobs["security"], "Release security audit must run for every platform/mode")

for platform, job_id in (("ios", "ios"), ("macos", "macos"), ("android", "android-tests")):
    block = jobs[job_id]
    require(f"inputs.scope == '{platform}'" in block and "inputs.scope == 'all'" in block,
            f"{job_id} must be selected only by its scope or all")

for job_id in ("fdroid", "fdroid-repeat"):
    block = jobs[job_id]
    require("uses: ./.github/workflows/fdroid-native.yml" in block,
            f"{job_id} must reuse fdroid-native.yml")
    require("needs.preflight.outputs.sha" in block,
            f"{job_id} must build the preflight SHA")
require("inputs.mode == 'release'" in jobs["fdroid-repeat"],
        "repeat F-Droid build must run only in release mode")
require("artifact_name: fdroid-native-repeat" in jobs["fdroid-repeat"],
        "repeat F-Droid build needs a distinct artifact")
require("needs: [fdroid, fdroid-repeat]" in jobs["compare"],
        "reproducibility comparison must depend on both F-Droid builds")
require("cmp --" in jobs["compare"], "reproducibility gate must compare APK bytes")

sign = jobs["sign-android"]
for gate in ("needs.security.result == 'success'", "needs.rust.result == 'success'", "needs.fdroid.result == 'success'",
             "needs.android-tests.result == 'success'", "needs.compare.result == 'success'"):
    require(gate in sign, f"Android signing is missing gate: {gate}")
require("environment: release-testing" in sign, "signer must use release-testing environment")
for secret in ("KEYSTORE_BASE64", "KEYSTORE_PASSWORD", "KEY_PASSWORD", "KEY_ALIAS"):
    require(f"secrets.{secret}" in sign, f"signer is missing secret {secret}")
require("Build/sign-release-apk.sh" in sign, "signer must call the canonical signing script")
require("needs: [preflight, security," in sign, "Signer must depend on strict security result")

publish = jobs["publish"]
require("always() && !cancelled()" in publish,
        "publisher must evaluate explicit results even when unselected jobs are skipped")
require("permissions: {contents: write}" in publish,
        "only publisher should request contents:write")
require(RELEASE.count("contents: write") == 1,
        "contents:write must be restricted to exactly one job")
for gate in ("needs.preflight.result == 'success'", "needs.security.result == 'success'", "needs.rust.result == 'success'",
             "needs.android-tests.result == 'success'", "needs.sign-android.result == 'success'",
             "needs.ios.result == 'success'", "needs.macos.result == 'success'"):
    require(gate in publish, f"publisher is missing selective gate: {gate}")
require("needs: [preflight, security," in publish, "Publisher must depend on strict security result")

ci_jobs = job_blocks(CI)
require("security" in ci_jobs and "security]" in ci_jobs["gate"],
        "Required CI Gate must depend on the security regression gate")
require("uses: ./.github/workflows/dependency-security.yml" in ci_jobs["security"],
        "PR security job must reuse the audited workflow")
require("base_sha: ${{ github.event.pull_request.base.sha }}" in ci_jobs["security"],
        "PR audit must compare with the exact event base SHA")
require("source_sha: ${{ github.sha }}" in ci_jobs["security"],
        "PR audit must inspect GitHub's proposed merge commit")
require("pull_request:" not in SECURITY, "PR audits must be owned by the required CI workflow")
require("schedule:" in SECURITY and "workflow_dispatch:" in SECURITY and "workflow_call:" in SECURITY,
        "Full security audit must support daily, manual and release runs")
require("cargo install cargo-audit --version 0.23.0 --locked" in SECURITY,
        "Audit parser must use the pinned cargo-audit JSON format")
require('args+=(--base "$BASE_SHA")' in SECURITY,
        "Only an explicit PR base may enable regression mode")
require("if: always()" in SECURITY and "actions/upload-artifact@" in SECURITY,
        "Failed full/regression audits must preserve evidence")
for forbidden in ("continue-on-error", "pull_request_target", "--ignore", "|| true"):
    require(forbidden not in SECURITY, f"Security workflow must not use {forbidden}")

exact_all_tags = 'tags=("android/v$VERSION" "ios/v$VERSION" "macos/v$VERSION" "v$VERSION")'
require(exact_all_tags in publish, "all scope must create exactly the four documented tags")
require('tags=("$SCOPE/v$VERSION")' in publish,
        "single-platform scopes must use platform/vX.Y.Z tags")
require(publish.count("gh release create") == 1 and RELEASE.count("gh release create") == 1,
        "there must be exactly one GitHub Release creation path")
for marker in ('git/refs', "gh release create"):
    require(RELEASE.count(marker) == publish.count(marker),
            f"{marker} must exist only in the publisher")
require("promotion_started=1" in publish and "report_partial_promotion" in publish,
        "publisher must diagnose a failure after tag creation begins")
require("automation will not rewrite or delete tags" in publish,
        "partial promotion diagnostic must preserve tag immutability")

require("workflow_call:" in FDROID, "F-Droid workflow must be reusable")
gradle_distribution = re.search(
    r"^distributionUrl=https\\://services\.gradle\.org/distributions/gradle-(\d+\.\d+\.\d+)-bin\.zip$",
    GRADLE_WRAPPER, re.MULTILINE,
)
require(gradle_distribution is not None, "Android wrapper must pin an official stable Gradle distribution")
gradle_version = gradle_distribution.group(1)
require(f'gradle-version: "{gradle_version}"' in FDROID,
        "F-Droid Gradle pin must match the Android wrapper")
require(f"gradle --version | grep -F 'Gradle {gradle_version}'" in FDROID,
        "F-Droid version check must match the pinned Gradle version")
require("git clone --no-checkout https://github.com/KevinCFechtel/FluxNews.git" in FDROID,
        "F-Droid must check out sources from FluxNews")
require('builds[0]["rm"] == ["Archived/Flutter"]' in FDROID,
        "native F-Droid validation must exclude the archived Flutter source")
require(re.search(r"source_sha:\n\s+required: true", FDROID) is not None,
        "reusable F-Droid workflow must require source_sha")
require("ref: ${{ inputs.source_sha || github.event.pull_request.head.sha || github.sha }}" in FDROID,
        "F-Droid checkout must honor the candidate SHA")
require("name: ${{ inputs.artifact_name || 'fdroid-native-recipe-diagnostics' }}" in FDROID,
        "F-Droid artifact must support independent build names")

require("[0-9a-f]{40}" in CANDIDATE, "candidate checker must require a full SHA")
require("git merge-base --is-ancestor" in CANDIDATE, "candidate SHA must be reachable from main")
for tag in ('"android/v$version"', '"ios/v$version"', '"macos/v$version"', '"v$version"'):
    require(tag in CANDIDATE, f"candidate checker is missing tag {tag}")
require("Partial combined release state detected" in CANDIDATE,
        "candidate checker must identify partial combined promotion state")

expected_fingerprint = "fee5401bc9d59cf5a8a461ba9698c482e87ed8ffb9258786a3d01d0356ea2ebb"
require(expected_fingerprint in SIGN, "developer signing fingerprint changed or is missing")
require("apksigner" in SIGN and "aapt" in SIGN,
        "signing script must verify certificate and APK identity")

require('".github/workflows/**"' in CONTRACT_CI,
        "all workflow changes must trigger cheap toolchain/release contract CI")
require("test_rust_toolchain_contract.py" in CONTRACT_CI,
        "cheap CI must verify independent Action and Rust compiler pins")
require("actionlint" in CONTRACT_CI and "test-release-workflow-contract.py" in CONTRACT_CI,
        "cheap CI must run actionlint and the project release contract")
for forbidden in ("git push --force", "git tag -f", "update-ref -f"):
    require(forbidden not in RELEASE + CANDIDATE + SIGN,
            f"forbidden tag rewrite primitive present: {forbidden}")

print("Scoped release workflow contract: PASS")
