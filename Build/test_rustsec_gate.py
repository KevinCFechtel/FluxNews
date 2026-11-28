#!/usr/bin/env python3
"""Offline regression tests: incomplete security evidence always blocks."""
from contextlib import redirect_stdout
from copy import deepcopy
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import rustsec_gate as gate


def finding(kind="unmaintained", advisory="RUSTSEC-2026-0374",
            package="basic-toml", version="0.1.10", source="registry+https://example.test"):
    return gate.Finding(kind, advisory, package, version, source, "Example | advisory")


def report(vulnerabilities=(), warnings=None):
    def entry(item):
        return {
            "package": {"name": item.package, "version": item.version, "source": item.source},
            "advisory": {"id": item.advisory, "title": item.title},
        }

    return {
        "database": {"advisory-count": 10, "last-commit": None, "last-updated": None},
        "lockfile": {"dependency-count": 5},
        "settings": {
            "ignore": [], "target_arch": [], "target_os": [], "severity": None,
            "informational_warnings": ["unmaintained", "unsound", "notice"],
        },
        "vulnerabilities": {
            "count": len(vulnerabilities), "found": bool(vulnerabilities),
            "list": [entry(item) for item in vulnerabilities],
        },
        "warnings": {
            kind: [entry(item) for item in items] for kind, items in (warnings or {}).items()
        },
    }


class ReportTests(unittest.TestCase):
    def test_clean_report(self):
        self.assertEqual(gate.parse_report(report(), 0), [])

    def test_complete_vulnerabilities_and_all_warning_kinds_are_visible(self):
        vulnerability = finding(kind="vulnerability")
        warnings = {kind: [finding(kind=kind)] for kind in ("unmaintained", "unsound", "notice")}
        parsed = gate.parse_report(report([vulnerability], warnings), 1)
        self.assertEqual({item.kind for item in parsed},
                         {"vulnerability", "unmaintained", "unsound", "notice"})

    def test_yanked_package_without_advisory_is_a_finding(self):
        data = report()
        data["warnings"]["yanked"] = [{"package": {
            "name": "example", "version": "1.0.0", "source": "registry+https://example.test",
        }}]
        item, = gate.parse_report(data, 1)
        self.assertEqual(item.advisory, "yanked:1.0.0")

    def test_unexpected_exit_codes_never_pass_even_with_complete_json(self):
        for code in (-15, 1, 2, 101):
            with self.subTest(code=code), self.assertRaises(gate.AuditError):
                gate.parse_report(report(), code)

    def test_findings_with_success_exit_are_rejected(self):
        with self.assertRaises(gate.AuditError):
            gate.parse_report(report(warnings={"unmaintained": [finding()]}), 0)

    def test_missing_fields_block_instead_of_becoming_an_empty_report(self):
        for key in report():
            data = report()
            del data[key]
            with self.subTest(key=key), self.assertRaises(gate.AuditError):
                gate.parse_report(data, 0)

    def test_error_report_blocks(self):
        with self.assertRaises(gate.AuditError):
            gate.parse_report({"error": "network failed"}, 1)

    def test_inconsistent_vulnerability_counts_block(self):
        for field, value in [("count", 1), ("count", True), ("found", True), ("list", {})]:
            data = report()
            data["vulnerabilities"][field] = value
            with self.subTest(field=field), self.assertRaises(gate.AuditError):
                gate.parse_report(data, 0)

    def test_unknown_or_malformed_warning_categories_block(self):
        for warnings in ({"new-category": []}, {"unmaintained": {}}, [], None):
            data = report()
            data["warnings"] = warnings
            with self.subTest(warnings=warnings), self.assertRaises(gate.AuditError):
                gate.parse_report(data, 0)

    def test_empty_or_malformed_database_and_lockfile_block(self):
        for section, key in [("database", "advisory-count"), ("lockfile", "dependency-count")]:
            for value in (0, -1, True, "5"):
                data = report()
                data[section][key] = value
                with self.subTest(section=section, value=value), self.assertRaises(gate.AuditError):
                    gate.parse_report(data, 0)

    def test_ignored_filtered_or_incomplete_audits_block(self):
        for field, value in [
            ("ignore", ["RUSTSEC-2026-0374"]), ("severity", "high"),
            ("target_os", ["linux"]), ("target_arch", ["aarch64"]),
            ("informational_warnings", ["notice"]),
        ]:
            data = report()
            data["settings"][field] = value
            with self.subTest(field=field), self.assertRaises(gate.AuditError):
                gate.parse_report(data, 0)

    def test_malformed_package_and_advisory_block(self):
        original = report(warnings={"unmaintained": [finding()]})
        for section, key, value in [
            ("package", "name", "bad\npackage"), ("package", "version", ""),
            ("package", "source", None), ("advisory", "id", ""),
            ("advisory", "title", None),
        ]:
            data = deepcopy(original)
            data["warnings"]["unmaintained"][0][section][key] = value
            with self.subTest(key=key), self.assertRaises(gate.AuditError):
                gate.parse_report(data, 1)


class ComparisonTests(unittest.TestCase):
    def test_existing_findings_do_not_block(self):
        item = finding()
        self.assertEqual(gate.compare([item], [item]),
                         {"new": [], "existing": [item], "resolved": []})

    def test_removed_findings_are_resolved(self):
        item = finding()
        self.assertEqual(gate.compare([item], []),
                         {"new": [], "existing": [], "resolved": [item]})

    def test_new_advisory_blocks_even_for_an_existing_package(self):
        self.assertTrue(gate.compare([finding()], [finding(advisory="RUSTSEC-2026-0543")])["new"])

    def test_new_package_blocks_even_for_an_existing_advisory(self):
        self.assertTrue(gate.compare([finding()], [finding(package="another")])["new"])

    def test_affected_version_change_is_visible_but_not_a_new_advisory(self):
        updated = finding(version="0.1.11")
        self.assertEqual(gate.compare([finding()], [updated])["existing"], [updated])

    def test_additional_affected_version_blocks(self):
        self.assertTrue(gate.compare([finding()], [finding(), finding(version="0.1.11")])["new"])

    def test_duplicate_report_rows_are_not_extra_affected_copies(self):
        self.assertEqual(gate.compare([finding()], [finding(), finding()])["new"], [])

    def test_changed_provenance_is_not_grandfathered(self):
        self.assertTrue(gate.compare([finding()], [finding(source="git+https://example.test")])["new"])

    def test_warning_promoted_to_vulnerability_blocks(self):
        self.assertTrue(gate.compare([finding()], [finding(kind="vulnerability")])["new"])

    def test_newly_yanked_version_blocks(self):
        before = finding(kind="yanked", advisory="yanked:1.0.0", version="1.0.0")
        after = finding(kind="yanked", advisory="yanked:1.0.1", version="1.0.1")
        self.assertTrue(gate.compare([before], [after])["new"])

    def test_pr155_example_fixes_three_without_hiding_the_two_existing_warnings(self):
        existing = [finding(), finding(package="chrono", advisory="RUSTSEC-2026-0543")]
        fixed = [finding(kind="vulnerability", package=name, advisory=advisory)
                 for name, advisory in [
                     ("ctutils", "RUSTSEC-2026-0385"), ("libsqlite3-sys", "RUSTSEC-2026-0459"),
                     ("rustix", "RUSTSEC-2026-0486"),
                 ]]
        changes = gate.compare(existing + fixed, existing)
        self.assertEqual([len(changes[key]) for key in ("new", "existing", "resolved")], [0, 2, 3])

    def test_strict_mode_has_no_grandfathered_findings(self):
        self.assertEqual(gate.compare([], [finding()])["new"], [finding()])

    def test_summary_preserves_findings_without_markdown_injection(self):
        text = gate.summary("a" * 40, "b" * 40, "c" * 40,
                            gate.compare([finding()], [finding()]))
        self.assertIn("Existing findings: 1", text)
        self.assertIn("Example &#124; advisory", text)
        self.assertIn("https://rustsec.org/advisories/RUSTSEC-2026-0374.html", text)
        self.assertIn("**PASS:**", text)

    def test_release_security_fix_can_ship_with_existing_maintenance_warning(self):
        maintenance = finding()
        vulnerability = finding(kind="vulnerability", package="url", advisory="RUSTSEC-2026-0592")
        changes = gate.compare([maintenance, vulnerability], [maintenance])
        self.assertEqual(gate.blocking_findings("a" * 40, changes), [])
        full = gate.compare([], [maintenance])
        self.assertEqual(gate.blocking_findings(None, full), [])
        self.assertEqual(full["new"], [maintenance], "the raw finding is not filtered away")

    def test_new_unmaintained_dependency_still_blocks_a_pr(self):
        changes = gate.compare([], [finding()])
        self.assertEqual(gate.blocking_findings("a" * 40, changes), [finding()])
        self.assertIn("**FAIL:**", gate.summary("a" * 40, "b" * 40, "c" * 40, changes))

    def test_full_summary_distinguishes_maintenance_and_security_findings(self):
        vulnerability = finding(kind="vulnerability", package="url")
        text = gate.summary(None, "b" * 40, "c" * 40, gate.compare([], [finding(), vulnerability]))
        self.assertIn("Blocking findings: 1", text)
        self.assertIn("Maintenance warnings (non-blocking): 1", text)
        self.assertIn("**FAIL:**", text)

    def test_maintenance_annotations_are_visible_and_escape_advisory_text(self):
        item = gate.Finding("unmaintained", "RUSTSEC-2026-0374", "basic-toml", "0.1.10",
                            "registry+https://example.test", "100% unmaintained\n::error::injected")
        output = io.StringIO()
        with redirect_stdout(output):
            gate.publish_maintenance_warnings([item, finding(kind="vulnerability")])
        text = output.getvalue()
        self.assertEqual(len(text.splitlines()), 1)
        self.assertTrue(text.startswith("::warning title=RustSec maintenance warning::"))
        self.assertIn("100%25 unmaintained%0A::error::injected", text)


class ExecutionTests(unittest.TestCase):
    def test_audits_use_one_database_no_fetch_and_an_isolated_cwd(self):
        with tempfile.TemporaryDirectory() as directory:
            scratch = Path(directory)
            output = scratch / "report.json"
            completed = subprocess.CompletedProcess([], 0, json.dumps(report()), "")
            with patch.object(gate, "run", return_value=completed) as command:
                gate.audit(scratch / "Cargo.lock", scratch / "db", output, scratch)
            args, cwd = command.call_args.args
            self.assertEqual(cwd, scratch)
            self.assertIn("--no-fetch", args)
            self.assertEqual(args[args.index("--deny") + 1], "warnings")
            self.assertNotIn("--ignore", args)
            self.assertNotIn("--no-yanked", args)
            self.assertEqual(json.loads(output.read_text()), report())
            self.assertEqual(output.with_suffix(".exit-code.txt").read_text(), "0\n")

    def test_raw_unmaintained_exit_and_report_are_retained_before_policy_classification(self):
        data = report(warnings={"unmaintained": [finding()]})
        with tempfile.TemporaryDirectory() as directory:
            scratch = Path(directory)
            output = scratch / "report.json"
            completed = subprocess.CompletedProcess([], 1, json.dumps(data), "")
            with patch.object(gate, "run", return_value=completed):
                findings = gate.audit(scratch / "Cargo.lock", scratch / "db", output, scratch)
            self.assertEqual(findings, [finding()])
            self.assertEqual(json.loads(output.read_text()), data)
            self.assertEqual(output.with_suffix(".exit-code.txt").read_text(), "1\n")
            self.assertEqual(gate.blocking_findings(None, gate.compare([], findings)), [])

    def test_non_json_output_is_preserved_and_blocks(self):
        with tempfile.TemporaryDirectory() as directory:
            scratch = Path(directory)
            output = scratch / "report.json"
            with patch.object(gate, "run", return_value=subprocess.CompletedProcess([], 1, "oops", "failed")):
                with self.assertRaises(gate.AuditError):
                    gate.audit(scratch / "Cargo.lock", scratch / "db", output, scratch)
            self.assertEqual(output.read_text(), "oops")
            self.assertEqual(output.with_suffix(".stderr.txt").read_text(), "failed")

    def test_incomplete_registry_checks_on_stderr_block_even_with_valid_json(self):
        with tempfile.TemporaryDirectory() as directory:
            scratch = Path(directory)
            completed = subprocess.CompletedProcess(
                [], 0, json.dumps(report()), "error: couldn't check if the package is yanked",
            )
            with patch.object(gate, "run", return_value=completed), self.assertRaises(gate.AuditError):
                gate.audit(scratch / "Cargo.lock", scratch / "db", scratch / "report.json", scratch)

    def test_registry_preparation_fetches_only_the_official_advisory_source(self):
        with tempfile.TemporaryDirectory() as directory:
            scratch = Path(directory)
            completed = subprocess.CompletedProcess([], 0, json.dumps(report()), "")
            with patch.object(gate, "run", return_value=completed) as command:
                gate.audit(scratch / "Cargo.lock", scratch / "db", scratch / "report.json",
                           scratch, refresh=True)
            args, _ = command.call_args.args
            self.assertEqual(args[args.index("--url") + 1], gate.DATABASE_URL)
            self.assertNotIn("--no-fetch", args)
            self.assertNotIn("--no-yanked", args)

    def test_command_failures_and_timeouts_block(self):
        for error in (OSError("missing cargo"), subprocess.TimeoutExpired("cargo", 180)):
            with patch.object(subprocess, "run", side_effect=error), self.assertRaises(gate.AuditError):
                gate.run(["cargo", "audit"], Path.cwd())

    def test_only_full_shas_are_accepted(self):
        for value in ("main", "a" * 7, "A" * 40, "--help", "x" * 40):
            with self.subTest(value=value), self.assertRaises(gate.AuditError):
                gate.revision(value)

    def test_main_returns_error_not_success_for_incomplete_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(sys, "argv", ["rustsec_gate.py", "--output", directory]), \
                    patch.object(gate, "check", side_effect=gate.AuditError("network error")), \
                    redirect_stdout(io.StringIO()):
                self.assertEqual(gate.main(), 2)
            self.assertIn("gate is blocked", (Path(directory) / "summary.md").read_text())


class GitSnapshotTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.database = self.root / "database"
        self.database.mkdir()
        for path in (self.repo, self.database):
            self.git(path, "init", "--quiet")
            self.git(path, "config", "user.email", "test@example.test")
            self.git(path, "config", "user.name", "Test")
        (self.database / "README").write_text("database fixture")
        self.git(self.database, "add", ".")
        self.git(self.database, "commit", "--quiet", "-m", "database")
        (self.repo / "core").mkdir()
        (self.repo / "core/Cargo.lock").write_text("base lock\n")
        self.git(self.repo, "add", ".")
        self.git(self.repo, "commit", "--quiet", "-m", "base")
        self.base = self.git(self.repo, "rev-parse", "HEAD")
        (self.repo / "core/Cargo.lock").write_text("head lock\n")
        self.git(self.repo, "commit", "--quiet", "-am", "head")
        self.head = self.git(self.repo, "rev-parse", "HEAD")
        self.output = self.root / "reports"
        self.output.mkdir()

    def git(self, path, *args):
        return subprocess.check_output(["git", *args], cwd=path, text=True).strip()

    def test_exact_committed_base_and_head_are_audited_not_worktree_files(self):
        (self.repo / "core/Cargo.lock").write_text("uncommitted\n")
        contents, databases = [], []

        def audit(lock, database, output, scratch, refresh=False):
            contents.append(lock.read_text())
            databases.append(database)
            return [finding()]

        with patch.object(gate, "audit", side_effect=audit), redirect_stdout(io.StringIO()):
            self.assertEqual(gate.check(self.repo, self.output, self.base, self.database), 0)
        self.assertEqual(contents, ["base lock\n", "head lock\n"] * 2)
        self.assertEqual(databases, [self.database.resolve()] * 4)
        metadata = json.loads((self.output / "comparison.json").read_text())
        self.assertEqual(metadata["base"], self.base)
        self.assertEqual(metadata["head"], self.head)
        self.assertEqual(metadata["database"], self.git(self.database, "rev-parse", "HEAD"))

    def test_full_audit_warns_without_blocking_on_unmaintained(self):
        with patch.object(gate, "audit", return_value=[finding()]), redirect_stdout(io.StringIO()):
            self.assertEqual(gate.check(self.repo, self.output, None, self.database), 0)
        metadata = json.loads((self.output / "comparison.json").read_text())
        self.assertEqual(len(metadata["findings"]["new"]), 1)
        self.assertEqual(metadata["blocking_findings"], [])
        text = (self.output / "summary.md").read_text()
        self.assertIn("Maintenance warnings (non-blocking): 1", text)
        self.assertIn("Blocking findings: 0", text)
        self.assertIn("**PASS:**", text)

    def test_full_audit_still_blocks_vulnerabilities_and_other_warning_kinds(self):
        for kind in ("vulnerability", "unsound", "notice", "yanked"):
            with self.subTest(kind=kind), \
                    patch.object(gate, "audit", return_value=[finding(kind=kind), finding()]), \
                    redirect_stdout(io.StringIO()):
                self.assertEqual(gate.check(self.repo, self.output, None, self.database), 1)
                metadata = json.loads((self.output / "comparison.json").read_text())
                self.assertEqual([item["kind"] for item in metadata["blocking_findings"]], [kind])
                self.assertIn("**FAIL:**", (self.output / "summary.md").read_text())

    def test_new_advisory_blocks_real_snapshot_comparison(self):
        with patch.object(gate, "audit", side_effect=[[], [finding()], [], [finding()]]), redirect_stdout(io.StringIO()):
            self.assertEqual(gate.check(self.repo, self.output, self.base, self.database), 1)

    def test_missing_base_blocks_before_audit(self):
        with patch.object(gate, "audit") as audit, self.assertRaises(gate.AuditError):
            gate.check(self.repo, self.output, "0" * 40, self.database)
        audit.assert_not_called()

    def test_unrelated_base_cannot_be_used_to_grandfather_findings(self):
        tree = self.git(self.repo, "rev-parse", "HEAD^{tree}")
        unrelated = self.git(self.repo, "commit-tree", tree, "-m", "unrelated history")
        with patch.object(gate, "audit") as audit, self.assertRaises(gate.AuditError):
            gate.check(self.repo, self.output, unrelated, self.database)
        audit.assert_not_called()

    def test_deleted_lockfile_blocks_instead_of_looking_clean(self):
        self.git(self.repo, "rm", "core/Cargo.lock")
        self.git(self.repo, "commit", "--quiet", "-m", "remove lockfile")
        with patch.object(gate, "audit") as audit, self.assertRaises(gate.AuditError):
            gate.check(self.repo, self.output, self.base, self.database)
        audit.assert_not_called()

    def test_database_modified_between_audits_blocks(self):
        def audit(*args, refresh=False):
            if not refresh:
                (self.database / "README").write_text("changed")
            return []

        with patch.object(gate, "audit", side_effect=audit), self.assertRaises(gate.AuditError):
            gate.check(self.repo, self.output, self.base, self.database)

    def test_dirty_database_blocks_before_audit(self):
        (self.database / "README").write_text("changed")
        with patch.object(gate, "audit") as audit, self.assertRaises(gate.AuditError):
            gate.check(self.repo, self.output, self.base, self.database)
        audit.assert_not_called()

    def test_database_commit_change_blocks_even_with_a_clean_worktree(self):
        changed = False

        def audit(*args, refresh=False):
            nonlocal changed
            if not changed and not refresh:
                (self.database / "README").write_text("new database snapshot")
                self.git(self.database, "commit", "--quiet", "-am", "new snapshot")
                changed = True
            return []

        with patch.object(gate, "audit", side_effect=audit), self.assertRaises(gate.AuditError):
            gate.check(self.repo, self.output, self.base, self.database)


if __name__ == "__main__":
    unittest.main()
