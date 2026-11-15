# Flux

Flux is a native-client RSS reader for [Miniflux](https://miniflux.app/) built around one shared Rust core. FluxNews is the current macOS client.

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

Build the macOS app for normal development. The resulting ad-hoc-signed app is at `dist/FluxNews.app`:

```bash
bash apple/macos/Build/build-app.sh
```

Install that exact build into `/Applications` and launch it, including its embedded WidgetKit extension:

```bash
bash apple/macos/Build/install-local.sh
```

For WidgetKit and App Group testing, use Xcode automatic Apple Development signing rather than ad-hoc signing. This requires a local Apple Development certificate and a signed-in Xcode account that belongs to the supplied team:

```bash
DEVELOPMENT_SIGNING=1 \
DEVELOPMENT_TEAM=<TEAM_ID> \
bash apple/macos/Build/build-app.sh

bash apple/macos/Build/install-local.sh
```

Set `DEVELOPMENT_SIGNING_IDENTITY` only when Xcode must use a specific Apple Development identity; it defaults to `Apple Development`. The Development build retains Xcode's target-specific signatures and validates Apple Development authority, the supplied team identifier, both App Group entitlements, the widget sandbox, and recursive code signing. The default remains the fast ad-hoc build.

Before building, configure the Apple Developer portal for the same team:

- Register the macOS App ID `dev.kevincfechtel.fluxNews` and the App Extension App ID `dev.kevincfechtel.fluxNews.widgets`.
- Register App Group `group.dev.kevincfechtel.fluxNews` and associate it with both App IDs.
- Enable the App Groups capability for both IDs and let Xcode Automatic Signing create or update the matching Apple Development provisioning profiles. If automatic signing cannot do so, create and download matching development profiles manually.
- Keep Developer ID/notarization separate from this development setup; `release.sh` continues to perform that distribution flow.

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

`apple/macos/Build/.env` is ignored by Git. `release.sh` builds the Rust/UniFFI-backed app, signs it with hardened runtime, notarizes and staples it, then creates and validates `dist/release/FluxNews-<version>-macos-<architecture>.zip`.

Changes should be covered by appropriate tests. Pull requests should focus on a clearly described problem or feature.

## License

FluxNews is released under the [BSD 3-Clause License](LICENSE).
