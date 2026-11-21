#!/usr/bin/env python3
"""Offline checks that Action updates cannot silently change the Rust compiler.

Check the repository's block-style steps without a YAML dependency. Actionlint
validates YAML syntax separately; unrecognized toolchain step layouts fail closed.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMPILER = "1.99.1"
ACTION = "dtolnay/rust-toolchain@"
VERIFY = f"run: rustc --version | grep -F 'rustc {COMPILER} '"


def step_blocks(source: str) -> list[tuple[int, str]]:
    lines = source.splitlines()
    blocks = []
    for index, line in enumerate(lines):
        start = re.match(r"^( +)- [\w-]+:", line)
        if not start:
            continue
        indent = len(start[1])
        end = index + 1
        while end < len(lines):
            following = lines[end]
            if following.strip() and not following.lstrip().startswith("#"):
                if len(following) - len(following.lstrip()) <= indent:
                    break
            end += 1
        blocks.append((indent, "\n".join(lines[index:end])))
    return blocks


def violations(source: str) -> list[str]:
    errors = []
    found = 0
    blocks = step_blocks(source)
    for index, (indent, block) in enumerate(blocks):
        action = re.search(
            rf"(?m)^ +(?:- )?uses:\s*['\"]?{re.escape(ACTION)}([^'\"\s#]+)",
            block,
        )
        if not action:
            continue
        found += 1
        if not re.fullmatch(r"[0-9a-f]{40}", action[1]):
            errors.append("Action must use a full commit SHA, not a compiler tag or branch")
        inputs = re.search(rf"(?m)^{' ' * (indent + 2)}with:\s*$", block)
        compiler = re.search(
            rf"(?m)^{' ' * (indent + 4)}toolchain:\s*([^#\n]+)", block,
        )
        if not inputs or not compiler or compiler[1].strip().strip("'\"") != COMPILER:
            errors.append(f"Action must explicitly select toolchain {COMPILER}")
        following = blocks[index + 1][1] if index + 1 < len(blocks) else ""
        if VERIFY not in following:
            errors.append("Installation must be followed by the exact compiler version assertion")
        if "continue-on-error:" in block + following:
            errors.append("Toolchain installation and verification must not bypass failures")
    if found != source.count(ACTION):
        errors.append("Unrecognized toolchain step layout")
    return errors


FIXTURE = f"""jobs:
  rust:
    steps:
      - uses: {ACTION}{'a' * 40} # master
        with:
          toolchain: "{COMPILER}"
          components: rustfmt,clippy
      - name: Verify pinned Rust compiler
        {VERIFY}
"""


class RustToolchainContractTests(unittest.TestCase):
    def test_repository_workflows(self):
        counts = {}
        for path in sorted((ROOT / ".github/workflows").glob("*.y*ml")):
            source = path.read_text()
            with self.subTest(workflow=path.name):
                self.assertEqual(violations(source), [])
            if ACTION in source:
                counts[path.name] = source.count(ACTION)
        self.assertEqual(counts, {
            "android-signing-diagnostic.yml": 1,
            "android.yml": 1,
            "apple.yml": 2,
            "dependency-security.yml": 1,
            "fdroid-native.yml": 1,
            "release.yml": 4,
            "rust.yml": 1,
        })

    def test_sha_only_update_keeps_compiler(self):
        self.assertEqual(violations(FIXTURE.replace("a" * 40, "b" * 40)), [])

    def test_named_installation_step(self):
        named = FIXTURE.replace("      - uses:", "      - name: Install Rust\n        uses:")
        self.assertEqual(violations(named), [])

    def test_rejects_tags_branches_and_short_shas(self):
        for ref in ("1.120.0", "1.99.1", "stable", "master", "abcdef1"):
            with self.subTest(ref=ref):
                self.assertTrue(violations(FIXTURE.replace("a" * 40, ref)))

    def test_rejects_implicit_compiler(self):
        self.assertTrue(violations(FIXTURE.replace(f'          toolchain: "{COMPILER}"\n', "")))

    def test_rejects_compiler_changes_even_with_matching_assertion(self):
        self.assertTrue(violations(FIXTURE.replace(COMPILER, "1.120.0")))

    def test_rejects_floating_or_expression_compiler(self):
        for compiler in ("stable", "nightly", "${{ vars.RUST_VERSION }}"):
            with self.subTest(compiler=compiler):
                self.assertTrue(violations(FIXTURE.replace(f'"{COMPILER}"', compiler)))

    def test_rejects_missing_runtime_verification(self):
        self.assertTrue(violations(FIXTURE.replace(VERIFY, "run: cargo test")))

    def test_rejects_failure_bypass(self):
        source = FIXTURE.replace("        with:", "        continue-on-error: true\n        with:")
        self.assertTrue(violations(source))

    def test_rejects_unrecognized_inline_step(self):
        self.assertTrue(violations(f"      - {{uses: {ACTION}{'a' * 40}}}"))


if __name__ == "__main__":
    unittest.main()
