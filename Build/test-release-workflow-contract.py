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

def fail(message: str) -> None:
    print(f"release workflow contract: FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)

def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)

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
    "fdroid-repeat", "compare", "sign-android", "publish",
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

require("needs: preflight" in jobs["rust"], "Rust gate must depend only on preflight")
require("inputs.scope" not in jobs["rust"], "Rust gate must run once for every candidate scope")
require(jobs["rust"].count("cargo test --locked") == 1, "Rust tests must appear exactly once")

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
for gate in ("needs.rust.result == 'success'", "needs.fdroid.result == 'success'",
             "needs.android-tests.result == 'success'", "needs.compare.result == 'success'"):
    require(gate in sign, f"Android signing is missing gate: {gate}")
require("environment: release-testing" in sign, "signer must use release-testing environment")
for secret in ("KEYSTORE_BASE64", "KEYSTORE_PASSWORD", "KEY_PASSWORD", "KEY_ALIAS"):
    require(f"secrets.{secret}" in sign, f"signer is missing secret {secret}")
require("Build/sign-release-apk.sh" in sign, "signer must call the canonical signing script")

publish = jobs["publish"]
require("always() && !cancelled()" in publish,
        "publisher must evaluate explicit results even when unselected jobs are skipped")
require("permissions: {contents: write}" in publish,
        "only publisher should request contents:write")
require(RELEASE.count("contents: write") == 1,
        "contents:write must be restricted to exactly one job")
for gate in ("needs.preflight.result == 'success'", "needs.rust.result == 'success'",
             "needs.android-tests.result == 'success'", "needs.sign-android.result == 'success'",
             "needs.ios.result == 'success'", "needs.macos.result == 'success'"):
    require(gate in publish, f"publisher is missing selective gate: {gate}")

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

require('".github/workflows/release.yml"' in CONTRACT_CI,
        "release workflow changes must trigger cheap contract CI")
require("actionlint" in CONTRACT_CI and "test-release-workflow-contract.py" in CONTRACT_CI,
        "cheap CI must run actionlint and the project release contract")
for forbidden in ("git push --force", "git tag -f", "update-ref -f"):
    require(forbidden not in RELEASE + CANDIDATE + SIGN,
            f"forbidden tag rewrite primitive present: {forbidden}")

print("Scoped release workflow contract: PASS")
