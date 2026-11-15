# F-Droid: Status und verbindliche offene Abnahmen

> Stand: 20. Oktober 2026. **Vorbereitung ist mergefähig; Veröffentlichung
> ist gesperrt.** Diese Liste ist die einzige operative Restpunkt-Übersicht
> für die erste native F-Droid-Veröffentlichung. Der Merge von PR #66 erzeugt
> weder eine Veröffentlichung noch eine F-Droid-Einreichung.

## Bereits technisch nachgewiesen

- Native Rust-/UniFFI-Erzeugung inklusive `arm64-v8a`, `x86_64` und
  `armeabi-v7a`, mit `de.circle_dev.flux_news` und geprüftem APK-Inhalt.
- Zwei erfolgreiche F-Droid-`fdroidserver`-Rezept-Builds/Lint- und
  Scanner-Durchläufe: [#39140681750](https://github.com/KevinCFechtel/Flux/actions/runs/39140681750)
  und [#39145172707](https://github.com/KevinCFechtel/Flux/actions/runs/39145172707).
  **Nicht** derselbe Commit und daher **kein** Reproduzierbarkeitsbeweis.
- Finaler PR-#66-CI-Zyklus für
  [`c934e1afa`](https://github.com/KevinCFechtel/Flux/commit/c934e1afa8926edb2736a8ca450f392069eb6ef3):
  F-Droid-Rezept, Rust, Android, Apple und Release-Vertrag erfolgreich.
- Native Kandidatenmetadaten können mit exakter Quell-SHA und den
  Android-Versionsdateien vorbereitet werden. Historische Flutter-Builds
  und bisherige `AllowedAPKSigningKeys` werden dabei nicht überschrieben.
- `rustls-platform-verifier 0.7.1` und dessen Android-Komponente `0.2.0`
  stammen aus derselben verifizierten Upstream-Revision
  `252e25161a91af476cbea620e29d277592d27ec7`. Der Kotlin-Teil wird als
  Gradle-Library aus dem darauf fixierten Git-Submodul gebaut; die frühere
  lokale Maven-/AAR-Einbindung ist entfernt. Gradle bricht bei abweichender
  Rust-Version, Android-Komponentenversion oder Quell-SHA ab.
- Android-Unit-Tests und Lint, die UniFFI-0.32-Binding-Erzeugung, Rust-
  Cross-Compilation für `arm64-v8a`, `x86_64` und `armeabi-v7a` sowie
  Development- und Production-Release-Builds mit NDK `29.0.14206865` sind
  lokal erfolgreich. Die Release-APKs enthalten die erwarteten Rust-
  Bibliotheken; R8 erhält die JNI-erreichbaren Verifier-Klassen.
- **FD-02 erfüllt:** Der native Metadateneintrag enthält keine
  `scanignore`-Ausnahme mehr. `fdroidserver 2.4.5 lint` war erfolgreich; der
  Scanner meldete für den frischen Checkout von `5f16003e` **0 Probleme**.
  Die Gradle-Wrapper-JARs des Hauptprojekts und des Submoduls wurden dabei
  regelkonform automatisch aus der Scan-Arbeitskopie entfernt. Das
  veröffentlichte Cargo-Hilfspaket enthält selbst keine AAR- oder JAR-Datei.
- **Keine** aktive Veröffentlichung/automatische F-Droid-Einreichung;
  der F-Droid-Workflow bleibt ein lokaler/CI-Feasibility-Test.

## Offen vor einer offiziellen F-Droid-Einreichung

| ID | Muss erledigt werden | Konkretes Abnahmekriterium |
| --- | --- | --- |
| FD-01 – Android-TLS-Laufzeitabnahme | Der Quellbuild, die Versions-/SHA-Prüfung sowie die Migration auf JNI 0.22 sind implementiert und kompilieren. Offen bleibt die erneute Laufzeitabnahme der aktualisierten Bibliotheken auf einem Gerät/Emulator mit dem reproduzierbaren Zweiphasentest `android/Build/test-transport-runtime.sh`. | Öffentliche System-CA erfolgreich; dieselbe private Test-CA ohne Installation abgelehnt und nach Installation im Android-Benutzerspeicher akzeptiert; falscher Hostname und nicht vertrauenswürdige Kette weiterhin abgelehnt |
| FD-03 – Reproduzierbarkeit | **Für den Flux-Kandidaten 3.0.0 / SHA `75022c00` technisch nachgewiesen:** zwei unabhängige Builds derselben SHA und erfolgreicher APK-Bytevergleich im Release-Workflow [#39410044142](https://github.com/KevinCFechtel/Flux/actions/runs/39410044142). | Für spätere FluxNews-/offizielle F-Droid-Kandidaten erneut an deren exakter Release-SHA prüfen; offizieller F-Droid-Build und historische Update-Signaturen sind dadurch nicht abgenommen |
| FD-04 – Signatur & Upgrade | Bestehende Flutter-F-Droid-Installationen beider überlieferten Signaturpfade identifizieren; native Upgrade-Pfade auf Geräten prüfen. | Update mit gleicher Package-ID, monotonem `versionCode`, passendem Signaturschlüssel und erhaltenen Nutzerdaten für jeden tatsächlich unterstützten Kanal nachgewiesen |
| FD-05 – Repository-Cutover | Nach nativer Übernahme von Flux nach **FluxNews** die alte Flutter-Workflows ersetzen und das endgültige F-Droid-`Repo` auf FluxNews umstellen. Import-Commit ist **kein Release-Commit**. | Historische Flutter-Tags/Builds bleiben erreichbar; neues Rezept baut die **spätere** explizit freigegebene FluxNews-Release-SHA |
| FD-06 – Release-Gate/Publish | Erst nach FD-01 bis FD-05 finale Android-Version, F-Droid-Quellbuild und Release-SHA freigeben. | Die Release-Orchestrierung läuft **nur in FluxNews**; separater autorisierter Publikationsschritt. Kein vorzeitiger Tag, Store-Upload oder automatischer GitLab-MR |

## In dieser lokalen Phase ausdrücklich nicht ausgeführt

- Kein vollständiger lokaler `fdroid build`: auf ausdrückliche Anweisung
  übersprungen; der nächste Lauf erfolgt gezielt über
  `.github/workflows/fdroid-native.yml` mit Submodulen, Rust 1.99.1, NDK
  `29.0.14206865` und allen drei ABIs.
- Keine aktualisierte Android-TLS-Geräteabnahme: Es war kein Gerät oder
  Emulator verbunden; `test-transport-runtime.sh` beendete sich deshalb mit
  `No usable Android device is connected`.
- Keine Apple-Builds oder Apple-Tests, keine vollständige GitHub-Actions-
  Matrix und keine Veröffentlichung.

FD-03 ist für den genannten Flux-Release-Kandidaten technisch erfüllt, nicht pauschal für künftige FluxNews-/offizielle F-Droid-Releases. FD-04 bleibt eine reale Abnahmeprüfung und werden
nicht durch `cargo audit`, `cargo test`, Scanner oder einen einzelnen
F-Droid-Rezept-Build ersetzt. FD-05/06 folgen erst beim expliziten
FluxNews-Cutover beziehungsweise einer später genehmigten Veröffentlichung.

Ressourcen:
[F-Droid-Plan](POST_REPLACEMENT_FOLLOWUP_PLAN.md),
[Release-Architektur](RELEASE_DISTRIBUTION.md),
[Dependency-Policy](DEPENDENCY_MAINTENANCE.md),
[Ruffle rustls-Quellbuild](https://github.com/ruffle-rs/ruffle-android/pull/866).

**Kein Punkt dieser Liste ist ein Grund, die erfolgreiche technische
Vorarbeit in einem dauerhaft offenen F-Droid-Branch zu halten.**

## Nachtrag: erfolgreicher Flux-Android-Release (20. Oktober 2026)

Der [Release-Workflow #39410044142](https://github.com/KevinCFechtel/Flux/actions/runs/39410044142) für Android 3.0.0 / Build `2026101801` / Quell-SHA `75022c001b5ad0d0f3935c0846fb5c59f5faac87` ist vollständig grün: Rust- und Android-Tests, zwei unabhängige F-Droid-Rezept-Builds, APK-Bytevergleich, Entwickler-Signierung und [GitHub-Release `android/v3.0.0`](https://github.com/KevinCFechtel/Flux/releases/tag/android/v3.0.0). Dies belegt die Reproduzierbarkeit **dieses** Kandidaten. Es erfolgte **keine** offizielle F-Droid-Einreichung und **kein** FluxNews-Cutover. Die historische Signatur-/Upgrade-Abnahme (FD-04) und weitere oben genannte Schritte bleiben separat.

Der temporäre Signierungsdiagnose-Workflow wurde mit Commit [`1e51a6e`](https://github.com/KevinCFechtel/Flux/commit/1e51a6e96ff43f09d84d25de0c8723815cc07153) entfernt. Details zum fehlgeschlagenen Versuch mit veralteter Source-SHA und zum erfolgreichen Release stehen in [FLUX_ANDROID_RELEASE_CANDIDATES.md](FLUX_ANDROID_RELEASE_CANDIDATES.md).
