import tempfile
import unittest
from pathlib import Path

from prepare_fdroid_metadata import MetadataError, prepare_metadata


DEVELOPER_KEY = "a" * 64
FDROID_KEY = "b" * 64
OLD_COMMIT = "1" * 40
NEW_COMMIT = "2" * 40


def metadata(build_codes=(101, 102, 103), include_keys=False):
    keys = ""
    if include_keys:
        keys = (
            "AllowedAPKSigningKeys:\n"
            f"  - {DEVELOPER_KEY}\n"
            f"  - {FDROID_KEY}\n\n"
        )
    return f"""Categories:
  - News

Builds:
  - versionName: 1.0.0
    versionCode: {build_codes[0]}
    commit: {OLD_COMMIT}
    output: build/app/outputs/flutter-apk/app-x86_64-release.apk
    build:
      - flutter build apk --target-platform="android-x64"

  - versionName: 1.0.0
    versionCode: {build_codes[1]}
    commit: {OLD_COMMIT}
    output: build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
    build:
      - flutter build apk --target-platform="android-arm"

  - versionName: 1.0.0
    versionCode: {build_codes[2]}
    commit: {OLD_COMMIT}
    output: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
    build:
      - flutter build apk --target-platform="android-arm64"

{keys}AutoUpdateMode: Version
UpdateCheckMode: Tags
VercodeOperation:
  - '%c + 1'
  - '%c + 2'
  - '%c + 3'
CurrentVersion: 1.0.0
CurrentVersionCode: {build_codes[2]}
"""


class PrepareMetadataTest(unittest.TestCase):
    def test_adds_three_builds_and_disables_fdroid_auto_update(self):
        updated, builds_added = prepare_metadata(
            metadata(),
            "1.1.0",
            200,
            NEW_COMMIT,
            DEVELOPER_KEY,
            FDROID_KEY,
        )

        self.assertTrue(builds_added)
        self.assertEqual(updated.count("versionName: 1.1.0"), 3)
        self.assertIn("versionCode: 201", updated)
        self.assertIn("versionCode: 202", updated)
        self.assertIn("versionCode: 203", updated)
        self.assertEqual(updated.count(f"commit: {NEW_COMMIT}"), 3)
        self.assertIn("AutoUpdateMode: None", updated)
        self.assertIn("CurrentVersion: 1.1.0", updated)
        self.assertIn("CurrentVersionCode: 203", updated)
        self.assertIn(f"  - {DEVELOPER_KEY}", updated)
        self.assertIn(f"  - {FDROID_KEY}", updated)

    def test_reuses_existing_release_builds(self):
        source = metadata((201, 202, 203), include_keys=True)
        source = source.replace("versionName: 1.0.0", "versionName: 1.1.0")
        source = source.replace(OLD_COMMIT, NEW_COMMIT)

        updated, builds_added = prepare_metadata(
            source,
            "1.1.0",
            200,
            NEW_COMMIT,
            DEVELOPER_KEY,
            FDROID_KEY,
        )

        self.assertFalse(builds_added)
        self.assertEqual(updated.count("versionCode:"), 3)
        self.assertIn("AutoUpdateMode: None", updated)
        self.assertEqual(updated.count(DEVELOPER_KEY), 1)
        self.assertEqual(updated.count(FDROID_KEY), 1)

    def test_rejects_partial_existing_release(self):
        source = metadata((201, 102, 103))

        with self.assertRaisesRegex(MetadataError, "Only part"):
            prepare_metadata(
                source,
                "1.1.0",
                200,
                NEW_COMMIT,
                DEVELOPER_KEY,
                FDROID_KEY,
            )

    def test_does_not_copy_disabled_build_templates(self):
        source = metadata().replace(
            f"    versionCode: 103\n    commit: {OLD_COMMIT}",
            f"    versionCode: 103\n    commit: {OLD_COMMIT}\n"
            "    disable: broken release",
        )

        with self.assertRaisesRegex(MetadataError, "different versions|Missing latest"):
            prepare_metadata(
                source,
                "1.1.0",
                200,
                NEW_COMMIT,
                DEVELOPER_KEY,
                FDROID_KEY,
            )

    def test_cli_writes_a_metadata_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "app.yml"
            path.write_text(metadata(), encoding="utf-8")
            updated, _ = prepare_metadata(
                path.read_text(encoding="utf-8"),
                "1.1.0",
                200,
                NEW_COMMIT,
                DEVELOPER_KEY,
                FDROID_KEY,
            )
            path.write_text(updated, encoding="utf-8")

            self.assertIn("CurrentVersionCode: 203", path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
