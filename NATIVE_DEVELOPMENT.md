# FluxNews

FluxNews is a native RSS reader for [Miniflux](https://miniflux.app/) with a shared Rust core and native Android, iOS/iPadOS and macOS clients.

## Requirements

- macOS 15 or later
- Rust
- Xcode Command Line Tools
- An accessible Miniflux instance with an API key

## Development

The Rust workspace is contained in `core/`. Run its checks from the repository root:

```bash
cargo fmt --manifest-path core/Cargo.toml --all --check
cargo test --manifest-path core/Cargo.toml --workspace
cargo build --manifest-path core/Cargo.toml --workspace
```

Generate the canonical Apple UniFFI package, including macOS and iOS slices:

```bash
bash apple/Build/build-uniffi.sh
```

The ignored output package at `apple/Build/Products/FluxUniFFI/` contains
`FluxUniFFI.xcframework` and the single generated Swift binding source. Verify
the iOS device and Apple Silicon simulator Swift compile/link integration with:

```bash
bash apple/Build/verify-ios-uniffi.sh
```

Build the macOS app for normal development. The script defaults to the
`Release` configuration **with Apple Development signing**
(`DEVELOPMENT_SIGNING=1`). The app is written to
`dist/macos/FluxNews.app`. Use `CONFIGURATION=Debug` when needed. This
signed build requires the Xcode-managed Apple Development identity and the
configured team/provisioning for the host and WidgetKit extension:

```bash
bash apple/macos/Build/build-app.sh
```

Install **that exact Development build** (rather than the default Developer ID
release ZIP) with an explicit source and installation mode:

```bash
INSTALL_MODE=development SOURCE_APP="$PWD/dist/macos/FluxNews.app" \
  bash apple/macos/Build/install-local.sh
```

`install-local.sh` otherwise defaults to `INSTALL_MODE=developer-id` and
selects the newest Developer ID ZIP from `dist/macos/developer-id/`. That
default is intended for the separate notarized outside-store release path,
**not** for installing the ordinary development build. In both modes the
installer verifies its source and staged app and preserves application data.

Only when deliberately producing an ad-hoc signed artifact, opt out of Xcode
Development signing:

```bash
DEVELOPMENT_SIGNING=0 bash apple/macos/Build/build-app.sh
```

Ad-hoc signing is **not** a valid B1 signed Development runtime acceptance or
a supported `INSTALL_MODE=development` installer input. The build script uses
its Xcode-configured team and Apple Development identity in Development mode;
it does not consume `DEVELOPMENT_TEAM` or
`DEVELOPMENT_SIGNING_IDENTITY` as configurable signing inputs.

Before signed Development builds, configure the Apple Developer portal for the
matching team:

- Register the macOS App ID `dev.kevincfechtel.fluxNews` and WidgetKit
  extension App ID `dev.kevincfechtel.fluxNews.FluxNewsWidgets`.
- Register App Group `group.dev.kevincfechtel.fluxNews` and associate it
  with both App IDs.
- Enable App Groups for both IDs and provide matching Apple Development
  provisioning profiles through Xcode automatic signing.
- Keep Developer ID/notarization separate; the outside-store channel is owned
  by `apple/macos/Build/release-developer-id.sh`.

## Diagnostics

FluxNews forwards structured Rust Core diagnostics to macOS Unified Logging. Stream all application activity with:

```bash
log stream --style compact --predicate 'process == "FluxNews"'
```

Limit output to Core diagnostics with:

```bash
log stream --style compact --predicate 'process == "FluxNews" AND subsystem == "dev.kevincfechtel.fluxNews"'
```

Use the same production configuration without signing or notarization to prepare a release build:

```bash
CONFIGURATION=Release bash apple/macos/Build/build-app.sh
```

## Create a Release

A release uses a Developer ID signing identity and a `notarytool` Keychain profile. Keep those local or supply them through the environment:

```bash
xcrun notarytool store-credentials FluxNews-notary
cp apple/macos/Build/.env.example apple/macos/Build/.env
bash apple/macos/Build/release-developer-id.sh
```

`apple/macos/Build/.env` is ignored by Git. `release-developer-id.sh` builds the Rust/UniFFI-backed app, signs it with hardened runtime, notarizes and staples it, then creates and validates `dist/macos/developer-id/FluxNews-<version>-macos-<architecture>.zip`.

Changes should be covered by appropriate tests. Pull requests should focus on a clearly described problem or feature.

## License

FluxNews is released under the [BSD 3-Clause License](LICENSE).
