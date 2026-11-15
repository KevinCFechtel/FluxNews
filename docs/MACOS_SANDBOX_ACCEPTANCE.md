# macOS App Sandbox — B1 implementation and acceptance

**Status (17 October 2026): B1 OWNER-ACCEPTED / CLOSED following successful macOS device tests, by explicit project-owner decision.** The macOS app has **not been released**. The developer
has explicitly accepted losing existing local macOS development data when the
app switches to sandboxed storage. There is **no migration or compatibility path**.

## Implemented in `main` (PR #38 and PR #53)

- Host entitlements: `com.apple.security.app-sandbox`, `com.apple.security.network.client`, `com.apple.security.files.user-selected.read-write`, and the existing `group.dev.kevincfechtel.fluxNews` App Group.
- Widget entitlements remain separate and keep their existing sandbox and App Group.
- Internal podcast downloads are now under sandbox-local `Application Support/FluxNews/Media` instead of `~/Movies/FluxNews`. The existing `BrowserStore` persistent/core cache locations resolve under the app container when sandboxed.
- `apple/macos/Build/build-app.sh` now verifies that the signed host has the new entitlements rather than asserting that the host is unsandboxed.
- XCTest checks verify source entitlements and that the derived media path uses Application Support.
- PR [#53](https://github.com/KevinCFechtel/Flux/pull/53) added
  `apple/macos/Build/verify-sandbox.sh`, enforcing signed host/widget versions,
  bundle IDs, App Group/provisioning, Apple Development team and effective signed
  Sandbox/file/network entitlements.
- `build-app.sh` uses Apple Development signing for the real verification path;
  `install-local.sh` validates both source and staged application before
  replacing the local app, without deleting persistent data.
- [Apple CI #164](https://github.com/KevinCFechtel/Flux/actions/runs/38924332033)
  passed for PR #53; combined `main`
  [Apple CI #167](https://github.com/KevinCFechtel/Flux/actions/runs/38934397341)
  also passed. Neither constitutes an on-Mac acceptance run.

## Not implemented

No old data, Keychain, download or account migration. The existing Developer ID/notarization script remains separate from the future Mac App Store export script. No claim of successful App Store provisioning or review is made.

## Decision history — signed acceptance deferred on 12 October 2026

The owner previously **deferred signed, real-device Sandbox acceptance** until
after feature-parity implementation. That work (C3.1–C3.7) has since merged.
PRs #38 and #53 establish source, signature and installation checks, but do
**not** prove that a provisioned/signed app can start, access Keychain and the
App Group, sync, play, download or export/import backups. B1 is **now the next
real-Mac acceptance gate**, not waived or already passed.

C3.8 functional acceptance may use the same signed test installation, but
each phase must have its own pass/fail evidence.
Before any Mac App Store production export, submission or release-readiness
claim, complete and record the signed-app checklist below. No migration from
the unreleased, unsandboxed macOS development app is required.

## Signed-app acceptance checklist (owner sign-off recorded 17 October 2026)

1. Sign the app with an actual development/distribution profile supporting its host+widget App Group. Inspect **signed** entitlements, not only XML sources.
2. Start with a fresh sandbox container and fresh account credentials. Confirm that Core database and caches persist across relaunch.
3. Verify sync, image/media networking, remote podcast playback, downloaded podcast playback, and the Listening List with local file access.
4. Verify Settings backup import/export via `NSOpenPanel` and `NSSavePanel`, including read/write permissions and actual encrypted backup round-trip.
5. Verify WidgetKit snapshots and the App Group across app/widget process boundaries.
6. Verify Keychain save/load after relaunch, periodic sync, menu bar controls, login-item registration and media remote controls.
7. Test existing Developer ID packaging separately if it is retained; implement and validate the Mac App Store archive/Transporter path only after acceptance.
8. Keep a record of sandbox-denial logs and resolve actual missing capabilities without granting broad filesystem access.

**Acceptance evidence:** On 17 October 2026 the project owner confirmed the macOS tests were good and explicitly instructed that B1 be closed. Individual signed fresh-container checklist results and sandbox-denial logs were not separately supplied in this handoff; do not misrepresent them as independently verified. Follow up on any later reproducible Sandbox defect as a regression.

CI compilation and source-plist tests alone **do not prove** end-to-end sandbox behavior.

**Gate separation:** Sign off **B1** after a signed development build passes
the fresh-container runtime checklist and relevant denials are resolved.
Mac App Store provisioning, archive/export and Transporter validation are a
**subsequent R deliverable**, not an unfulfilled condition inside B1.
The existing Developer ID/notarization script is also separate.

## B1 signed macOS development build acceptance

On a Mac with Apple Development signing and App Groups provisioned for both targets:

```bash
CONFIGURATION=Debug DEVELOPMENT_SIGNING=1 ./apple/macos/Build/build-app.sh
./apple/macos/Build/verify-sandbox.sh ./dist/FluxNews.app development
./apple/macos/Build/install-local.sh
```

The verifier checks actual signatures, host/widget IDs and versions, Sandbox and App Group entitlements, signing team and embedded development provisioning. The installer validates both source and staged copy **before** replacing the application; no app container or Keychain data is deleted. A truly fresh-container test requires a clean macOS user or separately approved manual cleanup. The project owner has explicitly accepted B1 as complete following device testing; the individual fresh-container checks above were not separately documented here. Unsigned CI checks alone do not establish signed Sandbox acceptance. Developer ID and Mac App Store distribution remain separate.
