# Apple-UniFFI-0.32-Migration

> Stand: 19. Oktober 2026. Dieser Nachweis betrifft den Branch
> `maintenance/rust-dependencies-current-2026-10` und UniFFI `0.32.2`.

## Bindings und Swift-API

Die Bindings werden weiterhin ausschließlich aus der gebauten
`flux-uniffi`-Bibliothek erzeugt. `uniffi-bindgen generate` erkennt die
Bibliothek seit UniFFI 0.31 automatisch; der veraltete Schalter `--library`
wird nicht mehr verwendet. Alle Cargo-Aufrufe des Apple-Paketierers verwenden
`--locked`, sodass Generator, Header, Modulemap, Swift-Quelle und Rust-Binary
aus demselben `core/Cargo.lock` stammen.

UniFFI 0.32 ersetzt für beidseitig implementierbare Traits
`#[uniffi::export(with_foreign)]` durch
`#[uniffi::export(rust, foreign)]`. Dies ist für `EventListener` und
`DiagnosticListener` umgesetzt. Die frisch erzeugten Swift-Protokolle sind
`AnyObject, Sendable`; die vorhandenen nativen Listener erfüllen diesen Vertrag
bereits. Records, Enums, optionale Werte, typisierte Fehler und Core-Objekte
blieben für die vorhandenen Swift-Aufrufer quellkompatibel. Deshalb waren keine
manuellen Änderungen an generierter Swift-Quelle und keine Änderungen an
iOS-/macOS-Aufrufstellen erforderlich.

Der Core bleibt gemäß Architekturentscheidung synchron. Swift Concurrency und
die vorhandenen bounded Apple worker lanes kapseln die synchronen Aufrufe.
UniFFI-generierte Objekt- und Subscription-Wrapper behalten ihre generierte
`deinit`-/Free-Logik; Callback-Handles werden von den generierten VTables
freigegeben. Es wurden keine parallelen Async-Core-APIs oder eigenen
Lebenszyklus-Wrapper eingeführt.

Offizielle Grundlage:

- [UniFFI 0.32 changelog](https://github.com/mozilla/uniffi-rs/blob/v0.32.2/CHANGELOG.md)
- [UniFFI Swift bindings documentation](https://mozilla.github.io/uniffi-rs/latest/swift/overview.html)

## Kanonisches Apple-Paket

`apple/Build/build-uniffi.sh` baut weiterhin genau diese vier Release-Targets:

- `aarch64-apple-darwin`
- `x86_64-apple-darwin`
- `aarch64-apple-ios`
- `aarch64-apple-ios-sim`

Der Paketierer erzeugt die Artefakte zunächst vollständig in einem temporären
Verzeichnis und ersetzt `apple/Build/Products/FluxUniFFI/` erst nach
erfolgreicher Prüfung. Dadurch kann kein vorhandenes Paket stillschweigend mit
teilweise neuen oder fehlenden Bindings vermischt werden.

Die Rust-Mach-O-Mindestversionen sind jetzt explizit mit den Xcode-Projekten
und Framework-Plists abgestimmt:

| Artefakt | Architekturen | Plattform / Mindestversion |
| --- | --- | --- |
| `MacOS/libflux_uniffi.dylib` | arm64, x86_64 | macOS 15.0 |
| XCFramework `ios-arm64` | arm64 | iOS 17.0 |
| XCFramework `ios-arm64-simulator` | arm64 | iOS Simulator 17.0 |

Das Skript bricht bei fehlenden Targets oder Artefakten, falschen
Architekturen, abweichenden Mindestversionen oder falschen Install-Names ab.
Erwartet werden `@rpath/libflux_uniffi.dylib` auf macOS und
`@rpath/FluxUniFFI.framework/FluxUniFFI` auf iOS. Die direkte Xcode-Einbindung
bleibt unverändert: iOS konsumiert XCFramework plus die einmal erzeugte
Swift-Quelle; macOS übernimmt Swift/Header/Modulemap und bettet die universelle
Dynamic Library über `apple/macos/Build/build-uniffi.sh` ein. Es existiert kein
separates Swift-Package-Manifest und es wurde keines als paralleler Buildpfad
eingeführt.

## Lokale Validierung

Verwendete vorhandene Umgebung: Xcode 27.0, SDK 27.0 und Rust 1.98.0. Die lokal
bereits installierte Toolchain `stable-aarch64-apple-darwin` enthielt alle vier
Apple-Targets und wurde über `RUSTUP_TOOLCHAIN=stable` nur für die Prozesse
ausgewählt; es wurde keine Toolchain und kein Target installiert und der
globale Default nicht verändert.

Erfolgreich:

- frische Erzeugung des vollständigen Apple-UniFFI-Pakets aus UniFFI 0.32.2;
- `apple/Build/verify-ios-uniffi.sh` für iOS-Gerät und arm64-Simulator;
- unsignierter iOS-Debug-Compile-/Link-Build für den vorhandenen iPhone-11-Pro-
  Max-Simulator einschließlich App, Widget, generierter Bindings und
  eingebettetem XCFramework;
- unsignierter universeller macOS-Debug-Compile-/Link-Build;
- `apple/macos/Build/test.sh`: 175 Tests, 0 Fehler, `TEST SUCCEEDED`;
- macOS-Test-App und eingebettetes `libflux_uniffi.dylib`: jeweils arm64 und
  x86_64, App-Link auf `@rpath/libflux_uniffi.dylib`.

Der vollständige Lauf von `apple/ios/Build/test.sh` erreichte Build und den
Startversuch des Test-Runners, scheiterte aber vor dem ersten XCTest am nach
einem Serverneustart ausgefallenen Simulator-Dienst mit
`NSMachErrorDomain -308 (ipc/mig server died)`. Ein weiterer vollständiger Lauf
wurde wegen der erheblichen lokalen Rechnerbelastung auf ausdrücklichen Wunsch
nicht gestartet. Der iOS-Laufzeittest bleibt daher offen; der Simulator wurde
heruntergefahren und nicht gelöscht oder verändert.

## Sandbox, Signierung und Distribution

Sandbox-Entitlements, App Group, Bundle-IDs, Xcode-Signing-Konfigurationen und
die vorhandenen Development-, Ad-hoc-, Distribution- und Developer-ID-Pfade
sind unverändert. Die lokalen Compile-/Test-Builds verwendeten
`CODE_SIGNING_ALLOWED=NO`; sie sind ausdrücklich kein Nachweis für
Apple-Development-, Developer-ID- oder App-Store-Signierung. Ein zusätzlicher
Ad-hoc-/Release-Build mit `DEVELOPMENT_SIGNING=0` und die Prüfung eines so
signierten App-Bundles wurden nach dem Hinweis auf die Rechnerbelastung nicht
mehr ausgeführt. Produktive Archive, Installation, Export, Notarisierung und
Veröffentlichung bleiben ungeprüft und wurden nicht angestoßen.

## CI- und Toolchain-Status

Die lokale Apple-Abnahme erfolgte mit Rust 1.98.0. Die anschließende gemeinsame
Toolchain-Integration fixiert `.github/workflows/apple.yml` auf Rust 1.99.1 und
alle vier Apple-Targets.
Die in Dependabot-PR #72 genannte Rust-Version 1.120.0 ist am 19. Oktober 2026
kein offizieller Rust-Release. Die offizielle Release-Liste führt Rust 1.99.1
als aktuelle Version. Deshalb wurde kein ungültiger Toolchain-Pin übernommen;
die plattformübergreifende Toolchain-Vereinheitlichung verwendet stattdessen
Rust 1.99.1.

- [Offizielle Rust-Releases](https://blog.rust-lang.org/releases/)
