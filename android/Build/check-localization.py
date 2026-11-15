#!/usr/bin/env python3
"""Incremental Android hardcoded-UI-copy guard.

Checks added Kotlin lines only: pre-existing UI literals are technical debt, not
permission to introduce more. Run with --base <git ref> in CI or --all for audit.
An intentional exception requires an inline '// l10n-ignore: <reason>'.
"""
from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
ANDROID = ROOT / "android"
SOURCE = ANDROID / "app" / "src"
# Deliberately targeted to UI copy, not logs, Miniflux API keys, URLs or persistence.
RULES = [
    ("Compose Text", re.compile(r'\bText\s*\(\s*"(?=[A-Za-z])')),
    ("Accessibility", re.compile(r'\bcontentDescription\s*=\s*"(?=[A-Za-z])')),
    ("UI title", re.compile(r'\b(?:title|subtitle|placeholder|actionLabel|message)\s*=\s*"(?=[A-Z])')),
    ("UI section", re.compile(r'\b(?:SettingsSectionTitle|SettingsSwitchRow|SettingsPickerRow|WidgetRadioRow|WidgetConfigurationSection)\s*\(\s*"(?=[A-Za-z])')),
    ("Snackbar", re.compile(r'\b(?:showMessage|showSnackbar|Toast\.makeText)\s*\(\s*"(?=[A-Za-z])')),
    ("Fallback user text", re.compile(r'\bifBlank\s*\{\s*"(?=[A-Za-z])')),
    ("State error", re.compile(r'\b(?:error|errorMessage|statusMessage)\s*=\s*"(?=[A-Z])')),
    ("System or media label", re.compile(r'\b(?:setTitle|setSubtitle|setDisplayName|setContentTitle|setContentText|setContentDescription)\s*\(\s*"(?=[A-Za-z])')),
    ("Notification channel", re.compile(r'\bNotificationChannel\s*\(.*"(?=[A-Za-z])')),
    ("Pane accessibility", re.compile(r'\bpaneTitle\s*=\s*"(?=[A-Za-z])')),
    ("Conditional content description", re.compile(r'\bcontentDescription\s*=\s*if\s*\([^)]*\)\s*"(?=[A-Za-z])')),
    ("Conditional display text", re.compile(r'\b(?:text|title|message)\s*=\s*if\s*\([^)]*\)\s*"(?=[A-Za-z])')),
    ("User-facing feedback", re.compile(r'\b(?:mutableActionMessages|actionMessages)\.emit\s*\(\s*(?:if\s*\([^)]*\)\s*)?"(?=[A-Za-z])')),
    ("Dynamic timer label", re.compile(r'\bText\s*\(\s*\w+\.toString\(\)\s*\+\s*"(?=[A-Za-z ])')),

]
EXCEPTION = re.compile(r'//\s*l10n-ignore:\s*\S+')

def run_git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True)

def source_file(name: str) -> bool:
    p = pathlib.PurePosixPath(name)
    return (name.startswith("android/app/src/") and name.endswith(".kt")
            and "/main/" in name and "/test/" not in name and "/androidTest/" not in name)

def added_lines(base: str) -> dict[str, set[int]]:
    # Git's unified=0 diff ranges refer to positions in HEAD, including newly created files.
    diff = run_git("diff", "--unified=0", "--no-ext-diff", "--diff-filter=ACMR", f"{base}...HEAD", "--", "android/app/src")
    result: dict[str, set[int]] = {}
    name = None
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            name = line[6:]
        elif line.startswith("@@ ") and name is not None and source_file(name):
            match = re.search(r"\+(\d+)(?:,(\d+))?\s", line)
            if match:
                first = int(match.group(1))
                count = int(match.group(2) or "1")
                result.setdefault(name, set()).update(range(first, first + count))
    return result

def scan(targets: dict[str, set[int]] | None) -> tuple[list[str], int]:
    violations: list[str] = []
    scanned = 0
    for file in sorted(SOURCE.rglob("*.kt")):
        relative = file.relative_to(ROOT).as_posix()
        if not source_file(relative):
            continue
        lines = file.read_text(encoding="utf-8").splitlines()
        for index, line in enumerate(lines, 1):
            if targets is not None and index not in targets.get(relative, set()):
                continue
            if EXCEPTION.search(line):
                continue
            scanned += 1
            for label, pattern in RULES:
                if pattern.search(line):
                    violations.append(f"{relative}:{index}: {label}: {line.strip()[:160]}")
                    break
    return violations, scanned

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--base", help="Git base SHA/ref for newly added lines")
    group.add_argument("--all", action="store_true", help="Report all current violations (audit)")
    args = parser.parse_args()
    try:
        targets = None if args.all else added_lines(args.base)
        violations, scanned = scan(targets)
    except (subprocess.CalledProcessError, OSError) as exc:
        print(f"Localization check could not run: {exc}", file=sys.stderr)
        return 2
    print(f"Android localization: checked {scanned} Kotlin lines; found {len(violations)} hardcoded UI strings.")
    for item in violations:
        print(item)
    if violations and not args.all:
        print("Move new UI copy to strings.xml/plurals.xml; or justify an exceptional technical literal with // l10n-ignore: reason", file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
