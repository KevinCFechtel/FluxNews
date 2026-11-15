#!/usr/bin/env python3
import tempfile
from pathlib import Path
import unittest
from prepare_native_recipe import prepare, parse_version_file, MARKER

SHA = "a" * 40
SOURCE = """Builds:
  - versionName: 2.3.2
    versionCode: 2026090504
    commit: v2.3.2
""" + MARKER + """
  - versionName: 3.0.0
    versionCode: 2026101801
    commit: FLUX_NATIVE_COMMIT
    subdir: android
    submodules: true
    gradleprops:
      - fluxBuildVersionCode=2026101801
      - fluxBuildVersionName=3.0.0

AllowedAPKSigningKeys:
  - historical-key
CurrentVersion: 2.3.2
CurrentVersionCode: 2026090504
"""

class Tests(unittest.TestCase):
    def test_rewrite_is_narrow_and_idempotent(self):
        updated = prepare(SOURCE, "3.1.0", 2026102001, SHA)
        self.assertEqual(updated.split(MARKER)[0], SOURCE.split(MARKER)[0])
        self.assertEqual(updated.split("\nAllowedAPKSigningKeys:")[1], SOURCE.split("\nAllowedAPKSigningKeys:")[1])
        self.assertIn("commit: " + SHA, updated)
        self.assertIn("submodules: true", updated)
        self.assertIn("fluxBuildVersionCode=2026102001", updated)
        self.assertEqual(updated, prepare(updated, "3.1.0", 2026102001, SHA))
    def test_reject_ambiguous(self):
        for source in [SOURCE.replace(MARKER, ""), SOURCE + MARKER, SOURCE.replace("    subdir: android", "")]:
            with self.subTest(source=source[-90:]), self.assertRaises(ValueError):
                prepare(source, "3.0.0", 1, SHA)
        with self.assertRaises(ValueError):
            prepare(SOURCE, "3.0.0", 1, "BAD-SHA")
    def test_version_file(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "android.properties"
            p.write_text("VERSION_NAME=3.0.0\nBUILD_NUMBER=2026101801\n")
            self.assertEqual(parse_version_file(p), ("3.0.0", 2026101801))
            p.write_text("VERSION_NAME=foo\nBUILD_NUMBER=0\n")
            with self.assertRaises(ValueError): parse_version_file(p)

if __name__ == "__main__":
    unittest.main()
