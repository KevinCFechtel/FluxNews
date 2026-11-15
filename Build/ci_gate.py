#!/usr/bin/env python3
"""Select impacted native CI jobs and verify the single required status gate.

PR selection compares the exact checkout tree (GitHub's pull-request merge ref)
with the event's base commit. No external action, token, or API is required.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
JOBS = ("rust", "android", "apple", "fdroid", "contracts")
CONTROL_FILES = {
    ".github/workflows/ci.yml",
    "Build/ci_gate.py",
    "Build/test_ci_gate.py",
}
FDROID_BUILD_FILES = {
    "Build/versions/android.properties",
    "Build/release.sh",
    ".gitmodules",
    "android/build.gradle.kts",
    "android/settings.gradle.kts",
    "android/gradle.properties",
    "android/app/build.gradle.kts",
    "android/app/src/main/AndroidManifest.xml",
    "core/Cargo.lock",
    "core/Cargo.toml",
    ".github/workflows/fdroid-native.yml",
}


def select_jobs(paths: list[str]) -> dict[str, bool]:
    result = {name: False for name in JOBS}
    if any(path in CONTROL_FILES for path in paths):
        return {name: True for name in JOBS}

    for path in paths:
        core = path.startswith("core/")
        android = path.startswith("android/")
        apple = path.startswith("apple/")
        scripts = path.startswith("Build/")
        verifier = path == "vendor/rustls-platform-verifier"
        gitmodules = path == ".gitmodules"

        result["rust"] |= core or path == ".github/workflows/rust.yml"
        result["android"] |= (
            android or core or verifier or gitmodules
            or path == ".github/workflows/android.yml"
            or path == "docs/ANDROID_WEBLATE_LOCALIZATION.md"
            or path == "Build/versions/android.properties"
        )
        result["apple"] |= (
            apple or core or path == ".github/workflows/apple.yml"
            or path in {"Build/versions/ios.properties", "Build/versions/macos.properties"}
        )

        native_manifest = (
            path.startswith("core/crates/") and
            (path.endswith("/Cargo.toml") or path.endswith("/build.rs"))
        )
        result["fdroid"] |= (
            path.startswith("fdroid/")
            or path.startswith("android/Build/")
            or path.startswith("android/gradle/")
            or path.startswith("android/rustls-platform-verifier/")
            or path in FDROID_BUILD_FILES
            or native_manifest or verifier
        )
        result["contracts"] |= (
            scripts
            or path.startswith("android/Build/")
            or path.startswith("apple/ios/Build/")
            or path.startswith("apple/macos/Build/")
            or path in {
                ".github/workflows/release-scripts.yml",
                ".github/workflows/release.yml",
                ".github/workflows/fdroid-native.yml",
            }
            or (path.startswith("fdroid/") and path.endswith(".py"))
        )

    return result


def changed_paths(base: str) -> list[str]:
    if not re.fullmatch(r"[0-9a-f]{40}", base):
        raise ValueError("PR base must be a full lowercase Git commit SHA")
    subprocess.run(
        ["git", "cat-file", "-e", f"{base}^{{commit}}"],
        cwd=ROOT, check=True, stdout=subprocess.DEVNULL,
    )
    # --no-renames includes BOTH the removed and added paths for a rename.
    # This is intentionally conservative: no job may disappear due to a move.
    output = subprocess.check_output(
        ["git", "diff", "--name-only", "--no-renames", "-z", base, "HEAD"],
        cwd=ROOT,
    )
    return [
        name for name in output.decode("utf-8", errors="surrogateescape").split("\0")
        if name
    ]


def evaluate_needs(needs: dict) -> list[str]:
    failures: list[str] = []
    changed = needs.get("changes", {})
    if changed.get("result") != "success":
        return [f"Change detection did not succeed: {changed.get('result')}"]
    flags = changed.get("outputs", {})
    for job in JOBS:
        selected = flags.get(job)
        if selected not in ("true", "false"):
            failures.append(f"{job}: missing or invalid selector output {selected!r}")
            continue
        observed = needs.get(job, {}).get("result")
        expected = "success" if selected == "true" else "skipped"
        if observed != expected:
            failures.append(
                f"{job}: selected={selected}, expected={expected}, got={observed}"
            )
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    detect = commands.add_parser("detect")
    detect.add_argument("--base", required=True)
    commands.add_parser("verify")
    args = parser.parse_args()

    if args.command == "detect":
        try:
            paths = changed_paths(args.base)
        except (ValueError, subprocess.CalledProcessError) as exc:
            print(f"::error::CI file detection failed: {exc}", file=sys.stderr)
            return 1
        chosen = select_jobs(paths)
        print(f"CI changed files: {len(paths)}")
        for name in JOBS:
            value = "true" if chosen[name] else "false"
            print(f"{name}={value}")
            if "GITHUB_OUTPUT" in os.environ:
                with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as out:
                    out.write(f"{name}={value}\n")
        return 0

    try:
        needs = json.loads(os.environ["NEEDS_JSON"])
    except (KeyError, ValueError) as exc:
        print(f"::error::Missing or malformed CI needs: {exc}", file=sys.stderr)
        return 1
    failures = evaluate_needs(needs)
    if failures:
        for message in failures:
            print(f"::error::{message}", file=sys.stderr)
        return 1
    print("CI Gate: all selected jobs succeeded; non-selected jobs were skipped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
