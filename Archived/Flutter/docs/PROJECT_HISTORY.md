# Flux News Project History and Validation Notes

This file keeps implementation-history and validation breadcrumbs that may help explain why the current repository looks the way it does. It is not a list of current mandatory rules; current invariants live in `ARCHITECTURE_DECISIONS.md`.

## iOS dependency migration

## iOS dependency management

- The iOS Runner uses Flutter's Swift Package Manager integration exclusively. `FlutterGeneratedPluginSwiftPackage` remains linked to the Runner target and the shared Runner scheme retains Flutter's `xcode_backend.sh prepare` pre-action, which generates the ephemeral local Swift package containing `FlutterFramework` and every native Flutter plugin product.
- CocoaPods is no longer part of the tracked iOS build: `ios/Podfile` and `ios/Podfile.lock` are removed, the Runner project has no Pods framework/group/build phase, the Flutter xcconfigs no longer include Pods support files, and the workspace contains only `Runner.xcodeproj`. Do not run `pod install` or re-add CocoaPods files unless a future dependency cannot be consumed through Flutter's SwiftPM integration and the migration decision is explicitly revisited.
- The migration was validated with Flutter 3.44.8 by resolving the Xcode package graph, generating iOS build configuration, and completing `flutter build ios --simulator --debug`. The resulting `Runner.app` uses bundle identifier `dev.kevincfechtel.fluxNews`.
- Before adding or upgrading a plugin with native Apple code, confirm that its generated iOS plugin metadata participates in SwiftPM and run a simulator/device build. Flutter can otherwise fall back to CocoaPods for a plugin without SwiftPM support, which would violate the intended SPM-only project state.

## How to use this file

Prefer the current code, tests, `AGENTS.md`, and `ARCHITECTURE_DECISIONS.md` for present behavior. Use this history when investigating regressions, migrations, or why an apparently unusual configuration exists.
