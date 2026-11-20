#!/usr/bin/env python3
"""Audit committed lockfiles; PRs reject regressions, releases reject all findings."""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import html
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DATABASE_URL = "https://github.com/RustSec/advisory-db.git"
SHA = re.compile(r"[0-9a-f]{40}")
WARNING_KINDS = {"unmaintained", "unsound", "notice", "yanked"}


class AuditError(Exception):
    """Missing evidence must never become a passing security gate."""


@dataclass(frozen=True)
class Finding:
    kind: str
    advisory: str
    package: str
    version: str
    source: str
    title: str

    @property
    def identity(self) -> tuple[str, str, str, str]:
        # A version update is not a new advisory. Changed provenance is not
        # grandfathered, and compare() separately checks additional affected copies.
        return self.kind, self.advisory, self.package, self.source


def run(command: list[str], cwd: Path) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=180)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise AuditError(f"Could not execute {command[0]}: {error}") from error


def git(arguments: list[str], cwd: Path, strip: bool = True) -> str:
    result = run(["git", *arguments], cwd)
    if result.returncode:
        raise AuditError(f"git {' '.join(arguments)} failed: {result.stderr.strip()}")
    return result.stdout.strip() if strip else result.stdout


def revision(value: str) -> str:
    if not SHA.fullmatch(value):
        raise AuditError("Revision must be a full lowercase Git commit SHA")
    return value


def lockfile(repo: Path, commit: str, destination: Path) -> None:
    text = git(["show", f"{revision(commit)}:core/Cargo.lock"], repo, strip=False)
    if not text.strip():
        raise AuditError(f"Missing or empty core/Cargo.lock at {commit}")
    destination.write_text(text)


def parse_report(report: dict, returncode: int) -> list[Finding]:
    if not isinstance(report, dict) or "error" in report:
        raise AuditError("cargo-audit did not return a complete audit report")
    try:
        database_count = report["database"]["advisory-count"]
        dependency_count = report["lockfile"]["dependency-count"]
        settings = report["settings"]
        vulnerabilities = report["vulnerabilities"]
        warnings = report["warnings"]
        if any(type(count) is not int or count < 1
               for count in (database_count, dependency_count)):
            raise AuditError("Audit database or lockfile is empty")
        if (settings["ignore"] != [] or settings["target_arch"] != []
                or settings["target_os"] != [] or settings["severity"] is not None
                or not {"unmaintained", "unsound", "notice"} <=
                set(settings["informational_warnings"])):
            raise AuditError("Filtered audits or ignored advisories are not accepted")
        entries = vulnerabilities["list"]
        if (not isinstance(entries, list)
                or type(vulnerabilities["count"]) is not int
                or vulnerabilities["count"] != len(entries)
                or type(vulnerabilities["found"]) is not bool
                or vulnerabilities["found"] != bool(entries)
                or not isinstance(warnings, dict)
                or warnings.keys() - WARNING_KINDS):
            raise AuditError("Inconsistent or unsupported cargo-audit report")
        grouped = [("vulnerability", entries), *warnings.items()]
        findings = []
        for kind, items in grouped:
            if not isinstance(items, list):
                raise AuditError("Malformed audit findings")
            for item in items:
                package = item["package"]
                name, version = package["name"], package["version"]
                source = package["source"]
                if (not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", name)
                        or not isinstance(version, str) or not version
                        or not isinstance(source, str) or not source):
                    raise AuditError("Malformed audited package")
                if kind == "yanked":
                    advisory, title = f"yanked:{version}", "Yanked package version"
                else:
                    advisory = item["advisory"]["id"]
                    title = item["advisory"]["title"]
                    if (not isinstance(advisory, str)
                            or not re.fullmatch(r"RUSTSEC-\d{4}-\d{4,}", advisory)
                            or not isinstance(title, str) or not title):
                        raise AuditError("Malformed advisory identity")
                findings.append(Finding(kind, advisory, name, version, source, title))
        expected_status = 1 if findings else 0
        if returncode != expected_status:
            raise AuditError(
                f"cargo-audit exited {returncode}; complete report requires {expected_status}"
            )
        return sorted(set(findings), key=lambda finding: (finding.identity, finding.version))
    except (KeyError, TypeError, ValueError) as error:
        raise AuditError(f"Malformed cargo-audit report: {error}") from error


def audit(lock: Path, database: Path, output: Path, scratch: Path,
          refresh: bool = False) -> list[Finding]:
    # An isolated cwd prevents a PR's .cargo/audit.toml from suppressing findings.
    # Refreshes prepare both sparse-registry caches before the DB is frozen.
    # The two comparison audits never fetch independently.
    database_options = ["--url", DATABASE_URL] if refresh else ["--no-fetch"]
    result = run([
        "cargo", "audit", "--file", str(lock), "--db", str(database),
        *database_options, "--deny", "warnings", "--json",
    ], scratch)
    output.write_text(result.stdout)
    output.with_suffix(".stderr.txt").write_text(result.stderr)
    if result.stderr.strip():
        # In particular cargo-audit can report incomplete yanked-package checks
        # on stderr without making that failure fatal itself.
        raise AuditError(f"cargo-audit reported diagnostics: {result.stderr.strip()}")
    try:
        report = json.loads(result.stdout)
    except (ValueError, TypeError) as error:
        raise AuditError(f"cargo-audit returned invalid JSON: {result.stderr.strip()}") from error
    return parse_report(report, result.returncode)


def compare(base: list[Finding], head: list[Finding]) -> dict[str, list[Finding]]:
    def groups(findings):
        result = {}
        for finding in findings:
            result.setdefault(finding.identity, set()).add(finding.version)
        return result

    previous, current = groups(base), groups(head)
    regressions = {
        identity for identity, versions in current.items()
        if identity not in previous or len(versions) > len(previous[identity])
    }
    return {
        "new": [finding for finding in head if finding.identity in regressions],
        "existing": [finding for finding in head if finding.identity not in regressions],
        "resolved": [finding for finding in base if finding.identity not in current],
    }


def markdown(value: str) -> str:
    return html.escape(value).replace("|", "&#124;").replace("\n", " ").replace("\r", " ")


def summary(base: str | None, head: str, database: str,
            changes: dict[str, list[Finding]]) -> str:
    mode = "regression gate" if base else "strict audit"
    lines = [
        f"## RustSec {mode}", "",
        f"Source: `{head}`",
        f"Base: `{base}`" if base else "No baseline: every finding blocks this check.",
        f"Advisory database: `{database}`", "",
    ]
    labels = {"new": "Blocking findings", "existing": "Existing findings", "resolved": "Resolved findings"}
    for group, label in labels.items():
        findings = changes[group]
        lines.extend([f"### {label}: {len(findings)}", ""])
        if findings:
            lines.extend(["| Advisory | Kind | Package | Version | Title |",
                          "| --- | --- | --- | --- | --- |"])
            for finding in findings:
                link = (f"[{finding.advisory}](https://rustsec.org/advisories/{finding.advisory}.html)"
                        if finding.advisory.startswith("RUSTSEC-") else markdown(finding.advisory))
                lines.append(
                    f"| {link} | {finding.kind} | {finding.package} | "
                    f"{markdown(finding.version)} | {markdown(finding.title)} |"
                )
            lines.append("")
    lines.append(
        "**FAIL:** new findings or additional affected copies."
        if base and changes["new"] else
        "**FAIL:** strict audit requires zero findings."
        if changes["new"] else
        "**PASS:** no security regressions; existing findings remain actionable."
        if base else "**PASS:** no findings."
    )
    return "\n".join(lines) + "\n"


def publish_summary(text: str, output: Path) -> None:
    (output / "summary.md").write_text(text)
    print(text)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as stream:
            stream.write(text)


def check(repo: Path, output: Path, base: str | None, database: Path | None) -> int:
    head = revision(git(["rev-parse", "HEAD"], repo))
    if base:
        revision(base)
        git(["merge-base", "--is-ancestor", base, head], repo)
    with tempfile.TemporaryDirectory(prefix="flux-rustsec-") as directory:
        scratch = Path(directory)
        if database is None:
            database = scratch / "advisory-db"
            git(["clone", "--quiet", "--depth", "1", DATABASE_URL, str(database)], scratch)
        database = database.resolve()
        if git(["status", "--porcelain"], database):
            raise AuditError("Advisory database checkout is not clean")
        head_lock = scratch / "head.lock"
        lockfile(repo, head, head_lock)
        previous = []
        if base:
            base_lock = scratch / "base.lock"
            lockfile(repo, base, base_lock)
            # --no-fetch also disables sparse-index refresh in cargo-audit.
            # Warm both lockfiles first, including packages removed by the PR,
            # so absent cache entries cannot masquerade as non-yanked packages.
            audit(base_lock, database, output / "base-refresh.json", scratch, refresh=True)
            audit(head_lock, database, output / "head-refresh.json", scratch, refresh=True)
        else:
            current = audit(head_lock, database, output / "head.json", scratch, refresh=True)
        database_sha = revision(git(["rev-parse", "HEAD"], database))
        if git(["status", "--porcelain"], database):
            raise AuditError("Advisory database refresh did not leave a clean checkout")
        if base:
            previous = audit(base_lock, database, output / "base.json", scratch)
            current = audit(head_lock, database, output / "head.json", scratch)
        if (git(["rev-parse", "HEAD"], database) != database_sha
                or git(["status", "--porcelain"], database)):
            raise AuditError("Advisory database changed during the audit")
    changes = compare(previous, current)
    metadata = {
        "mode": "regression" if base else "strict",
        "base": base, "head": head, "database": database_sha,
        "findings": {
            kind: [finding.__dict__ for finding in findings]
            for kind, findings in changes.items()
        },
    }
    (output / "comparison.json").write_text(json.dumps(metadata, indent=2) + "\n")
    publish_summary(summary(base, head, database_sha, changes), output)
    return 1 if changes["new"] else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", help="Exact PR base SHA; omit for strict daily/release audit")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--database", type=Path, help="Existing clean database checkout for local validation")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    try:
        return check(ROOT, output, args.base, args.database)
    except AuditError as error:
        publish_summary(f"## RustSec audit\n\n**ERROR: audit incomplete; gate is blocked.**\n\n"
                        f"{markdown(str(error))}\n", output)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
