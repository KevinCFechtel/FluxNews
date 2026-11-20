#!/usr/bin/env python3
"""Fast, offline contract tests for selective CI and required gate behavior."""
import unittest

from ci_gate import JOBS, evaluate_needs, select_jobs


def selectors(*paths: str) -> dict[str, bool]:
    return select_jobs(list(paths))


def selected(*paths: str) -> set[str]:
    return {key for key, run in selectors(*paths).items() if run and key in JOBS}


def needs(selected_jobs: set[str]) -> dict:
    data = {
        "changes": {
            "result": "success",
            "outputs": {job: "true" if job in selected_jobs else "false" for job in JOBS},
        }
    }
    for job in JOBS:
        data[job] = {"result": "success" if job in selected_jobs else "skipped"}
    return data


class CISelectionTests(unittest.TestCase):
    def test_docs_only_has_no_expensive_jobs(self):
        self.assertEqual(selected("README.md", "docs/MOBILE_PRODUCT_SEMANTICS.md"), set())

    def test_rust_source_checks_all_consumers_and_armv7_without_full_fdroid(self):
        paths = selectors("core/crates/flux-core/src/lib.rs")
        self.assertEqual(
            {key for key, run in paths.items() if run and key in JOBS},
            {"rust", "android", "apple"},
        )
        self.assertTrue(paths["armv7"])

    def test_rust_dependencies_include_fdroid_without_duplicate_armv7(self):
        paths = selectors("core/Cargo.lock")
        self.assertEqual(
            {key for key, run in paths.items() if run and key in JOBS},
            {"rust", "android", "apple", "fdroid", "security"},
        )
        self.assertFalse(paths["armv7"])

    def test_android_ui_only(self):
        self.assertEqual(selected("android/app/src/main/example.kt"), {"android"})

    def test_apple_client_only(self):
        self.assertEqual(selected("apple/ios/FluxNews/App.swift"), {"apple"})

    def test_android_gradle_modification(self):
        self.assertEqual(
            selected("android/app/build.gradle.kts"), {"android", "fdroid"}
        )

    def test_android_release_tooling(self):
        self.assertEqual(
            selected("android/Build/build-app.sh"), {"android", "fdroid", "contracts"}
        )

    def test_apple_build_script(self):
        self.assertEqual(
            selected("apple/ios/Build/build-app.sh"), {"apple", "contracts"}
        )

    def test_fdroid_recipe_python(self):
        self.assertEqual(
            selected("fdroid/prepare_native_recipe.py"), {"fdroid", "contracts"}
        )

    def test_fdroid_recipe_yaml(self):
        self.assertEqual(
            selected("fdroid/metadata/de.circle_dev.flux_news.yml"), {"fdroid"}
        )

    def test_shared_submodule(self):
        self.assertEqual(
            selected(".gitmodules", "vendor/rustls-platform-verifier"),
            {"android", "fdroid"},
        )

    def test_android_version_bumps(self):
        self.assertEqual(
            selected("Build/versions/android.properties"),
            {"android", "fdroid", "contracts"},
        )

    def test_markdown_never_selects_technical_jobs(self):
        markdown_paths = (
            "README.md",
            "docs/ANDROID_WEBLATE_LOCALIZATION.md",
            "android/app/src/androidTest/README.md",
            "apple/macos/FluxNews/Assets/AppIconSource/README.md",
            "core/README.md",
            "fdroid/README.md",
            "Build/README.md",
            ".github/DEPENDENCY_AUTOMATION.md",
        )
        self.assertEqual(selected(*markdown_paths), set())
        self.assertFalse(any(selectors(*markdown_paths).values()))

    def test_markdown_does_not_mask_real_technical_changes(self):
        self.assertEqual(
            selected(
                "android/app/src/androidTest/README.md",
                "android/app/src/main/example.kt",
            ),
            {"android"},
        )

    def test_ci_control_always_exercises_all_jobs(self):
        self.assertEqual(selected(".github/workflows/ci.yml"), set(JOBS))
        self.assertEqual(selected("Build/ci_gate.py"), set(JOBS))
        self.assertTrue(selectors(".github/workflows/ci.yml")["armv7"])

    def test_leaf_workflow_change_only_affects_itself(self):
        self.assertEqual(selected(".github/workflows/rust.yml"), {"rust"})

    def test_security_tooling_selects_audit_and_cheap_contracts_only(self):
        for path in ("Build/rustsec_gate.py", "Build/test_rustsec_gate.py",
                     ".github/workflows/dependency-security.yml"):
            self.assertEqual(selected(path), {"security", "contracts"})

    def test_core_manifests_and_audit_config_require_security_gate(self):
        for path in ("core/Cargo.toml", "core/crates/flux-core/Cargo.toml",
                     ".cargo/audit.toml", "core/.cargo/audit.toml"):
            self.assertIn("security", selected(path))

    def test_archived_flutter_does_not_build_native(self):
        self.assertEqual(
            selected("Archived/Flutter/docs/OLD.md"), set()
        )


class CIGateTests(unittest.TestCase):
    def test_all_selected_success(self):
        self.assertEqual(evaluate_needs(needs(set(JOBS))), [])

    def test_docs_only_requires_skipped_jobs(self):
        self.assertEqual(evaluate_needs(needs(set())), [])

    def test_selected_failure_blocks(self):
        data = needs({"rust", "android"})
        data["android"]["result"] = "failure"
        self.assertTrue(evaluate_needs(data))

    def test_selected_skipped_blocks(self):
        data = needs({"rust"})
        data["rust"]["result"] = "skipped"
        self.assertTrue(evaluate_needs(data))

    def test_selected_cancelled_blocks(self):
        data = needs({"apple"})
        data["apple"]["result"] = "cancelled"
        self.assertTrue(evaluate_needs(data))

    def test_security_regressions_or_missing_audit_block_required_ci_gate(self):
        for result in ("failure", "skipped", "cancelled", None):
            data = needs({"security"})
            data["security"]["result"] = result
            self.assertTrue(evaluate_needs(data))

    def test_unexpected_job_execution_blocks(self):
        data = needs(set())
        data["fdroid"]["result"] = "success"
        self.assertTrue(evaluate_needs(data))

    def test_detection_error_blocks(self):
        data = needs(set())
        data["changes"]["result"] = "failure"
        self.assertTrue(evaluate_needs(data))

    def test_missing_output_blocks(self):
        data = needs({"rust"})
        del data["changes"]["outputs"]["rust"]
        self.assertTrue(evaluate_needs(data))


if __name__ == "__main__":
    unittest.main()
