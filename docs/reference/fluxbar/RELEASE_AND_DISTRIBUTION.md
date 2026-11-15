> **Status: historical product/reference evidence.** This document may describe FluxBar-specific current or legacy behavior. It is not authoritative for the shared Flux Rust-core target architecture. If it conflicts with `docs/ARCHITECTURE_DECISIONS.md`, the architecture decisions win.

# FluxBar Desktop Release and Distribution

## Intended macOS Channels

The macOS application may be distributed through:

-   Mac App Store
-   signed/notarized GitHub releases
-   Homebrew Cask

These channels can coexist.

## Current Native Build

`Build/build.sh` is the default developer build entry point. It dispatches
to `Build/build-rust.sh` (default) or `Build/build-go.sh` based on the
`FLUX_CORE` environment variable. Both scripts build the same SwiftUI/AppKit
target through Xcode; the Xcode build phase calls `Build/build-core.sh`,
which produces the implementation-neutral core artifacts
`libfluxcore.a` / `libfluxcore.h` from either the Go or Rust core.

`Build/build-rust.sh` builds the native application against the Rust core
in `rust-core/`. Rust is now the default for normal development and local
builds. All current public operations are implemented and Phase 10.2 cleared
it for development-default use.

`Build/build-go.sh` compiles and links the Go core from `go-core/` as a
C archive, copies `FluxBar.app` to `dist`, and applies an ad-hoc signature
for local execution. Go is deprecated for future development but remains the
explicit reference/fallback: `FLUX_CORE=go ./Build/build.sh` still works, and
`Build/release-go.sh` continues to build with Go.

`Build/release-go.sh` implements an explicit fallback direct-distribution path
for the Go-backed app as a Developer ID-signed, hardened, notarized ZIP. It
verifies the signature, notarization ticket, Gatekeeper assessment, and
re-extracted final artifact. The script remains intentionally pinned to Go.

`Build/release-rust.sh` is a signed/notarized release script that
builds the Rust-backed app using the same signing identity, hardened
runtime, notarization mechanism, versioning, packaging, and validation
sequence as `release-go.sh`. It produces a `-rust.zip` artifact to avoid
overwriting the Go release archive, while the app bundle inside remains
`FluxBar.app` with the same bundle identifier. It is the first-public-release
candidate path; this documentation change does not rename either script or
change their explicit core selection.

FluxBar has no public Go-backed installed base. A clean Rust-backed first public
release does not require a Go-to-Rust user-data migration. Go/Rust database
interoperability remains reference/regression coverage.

DMG packaging, universal release artifacts, Mac App Store packaging,
Homebrew publication, and release CI remain future work.

## Identity and Compatibility

The user-facing name is FluxBar. The app bundle/executable name
`FluxBar.app`, bundle identifier `dev.kevincfechtel.FluxBar`, and
current Keychain service retain the FluxBar identity for compatibility.
The native minimum system version is macOS 15.

Native app metadata lives in `macos/FluxBar/Info.plist`, while the
release script currently reads its version from `Build/Info.plist`.
Keeping these two version sources synchronized is an outstanding release
maintenance concern.

## Mac App Store

The App Store build must follow Apple's sandbox/signing/review
requirements.

The product should remain useful enough as a native Miniflux Menu Bar
companion to stand on its own rather than behaving as a trivial list of
links.

The native popover, synchronized read/star state, filtering/navigation,
previews/metadata, background sync, global shortcuts, Spotlight, and App
Intents provide the current standalone utility. Planned notifications
and podcast capabilities will strengthen it further.

## Direct Distribution

Direct GitHub releases should use the appropriate Developer ID signing
and Apple notarization process.

ZIP or DMG packaging can be used as appropriate.

## Homebrew

A Homebrew Cask can point to the official direct release artifact.

Initially, a project-owned tap may be used.

If the project later satisfies current Homebrew acceptance/notability
requirements, it may be proposed for the official Homebrew Cask
repository so users can install without a custom tap.

Always revalidate current Homebrew and Apple requirements before release
work because external policies change.

## Build Separation

Mac App Store and direct/Homebrew distribution may require separately
signed builds.

Do not assume one signed artifact can be used interchangeably across all
channels.

## Release Safety

Signing/notarization credentials and CI workflows are
security-sensitive.

Prefer minimal dependencies and narrowly scoped credentials in critical
release workflows.

The current direct ZIP path is documented above. App Store, Homebrew,
and CI details should be added only when established in the repository.

## Core Migration and Release Safety

The FluxBar compatibility migration has reached Rust-default development and a
signed/notarized Rust release-candidate path. `Build/build.sh` remains a
developer selector, not a release script.

`Build/release-go.sh` calls `Build/build-go.sh` with `FLUX_CORE=go` explicitly.
An inherited developer-shell value such as `FLUX_CORE=rust` cannot select Rust
for this fallback path.

`Build/release-rust.sh` is the parallel Rust release-candidate path and
calls `Build/build-rust.sh` with `FLUX_CORE=rust` explicitly. An inherited
developer-shell value such as `FLUX_CORE=go` cannot select Go for this
release path.

Both release scripts use the same signing identity, hardened runtime,
notarization mechanism, archive layout, and validation sequence. Rust must
not silently alter signing, notarization, archive layout, release
automation, or distribution channels.

Keep the explicit Go-backed fallback while it remains useful as a regression
oracle. Go deprecation and removal criteria, and the shortened first-release
proving phase, are defined in `SHARED_RUST_CORE_ROADMAP.md`.
