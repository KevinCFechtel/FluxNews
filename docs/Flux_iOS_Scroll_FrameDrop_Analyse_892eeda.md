# Flux iOS Timeline — Frame-Drop-Analyse aus Bildschirmaufnahme

> **Die Kernannahme dieses Dokuments ist widerlegt (19. September 2026).**
> Ein pixelidentisch wiederholter Frame ist **nicht** zuverlässig ein
> verworfener Display-Frame. Eine Kontrollmessung an **Apple Kalender ergab mit
> derselben Methode rund 13 %**, Flux lag bei etwa 5 %. Die absolute Rate wird
> also von der Aufnahmemechanik bestimmt, nicht vom Scrollverhalten der App.
>
> **Der unten genannte Zielwert „< 1 % bei Bewegung" ist damit kein gültiges
> Freigabekriterium und darf nicht als Regressionsmetrik verwendet werden.**
> Die Messwerte bleiben als Vergleichsgröße zwischen zwei Armen **einer**
> Sitzung brauchbar, als Qualitätszahl nicht.
>
> Das Dokument bleibt als datierter Befund zu `892eeda` stehen. Die
> abschließende Einordnung steht in
> `IOS_TIMELINE_PERFORMANCE_DIAGNOSTIC_CLEANUP.md`.

Geprüfter Stand: `892eeda` (`main`, 14. September 2026)
Grundlage: `docs/ScreenRecording1.MP4` (45,81 s, 1180 × 2556, 60,09 fps, 2754 Frames) plus Quelltextprüfung.
Gerät laut vorherigem Review: iPhone 15, iOS 26. **60 Hz ⇒ Frame-Budget 16,7 ms.**
Vorgänger: `docs/Flux_iOS_Timeline_Stutter_Review_a40e377.md`. Dieses Dokument ersetzt dessen *Diagnose*, nicht dessen Befundliste.

---

## 0. Kurzfassung

Die Aufnahme lässt sich quantitativ auswerten, weil das Display 60 Hz hat und die Aufnahme mit exakt 60 fps und lückenlosem Frame-Abstand (16,7 ms, kein einziger Encoder-Gap) geschrieben wurde. Ein im Video **pixelidentisch wiederholter Frame ist damit genau ein verworfener Display-Frame.**

Das Ergebnis widerspricht der bisherigen Arbeitshypothese:

* **Es gibt keine langen Hitches.** Kein einziges Mehr-Frame-Halten während echter Bewegung. Die vermeintlichen 84–150-ms-Blöcke sind Finger-Pausen zwischen Wischern (Geschwindigkeit davor ≈ 0, danach 1700–6500 px/s).
* **Es gibt einen konstanten Grundregen einzelner verworfener Frames:** **5,6 % aller Bewegungsframes**, davon 62 von 63 Ereignissen exakt ein Frame lang.
* **Die Drop-Rate pro Frame ist über die Scrollgeschwindigkeit hinweg flach** (300–700 px/s: 6,1 %; 700–1200: 5,0 %; 1200–1800: 6,6 %; 1800–2500: 3,9 %). Sie steigt *nicht* mit der Zahl neu erscheinender Zellen.
* **Die Drop-Rate wächst nicht mit der Listenlänge** (8 Tiefenfenster über 23 273 pt Scrollweg, kein Trend).
* Einzige systematische Erhöhung: die ersten 5 Frames nach Gestenbeginn (10,3 % statt 5,6 %).

Damit ist das Problem **kein Einzelereignis und keine Fan-out-Kaskade, sondern fehlender Kopfraum**: die Pro-Frame-Kosten des Scrollens liegen auf diesem Gerät dauerhaft dicht an 16,7 ms, und die normale Streuung (eine erscheinende Zelle, ein fertig dekodiertes Bild, ein Allokator-Burst) kippt rund jeden 18. Frame darüber. Genau das erzeugt den Eindruck „stockt manchmal etwas“ statt „hängt“.

**Konsequenz für die Priorisierung:** Nicht ein Hotspot ist zu suchen, sondern die *gesamte Pro-Frame-Kurve* muss gesenkt werden. Die größten von der App kontrollierten Pro-Frame-Terme sind Kompositionskosten (Offscreen-Pässe, durchgehende Alpha-Komposition) und der Scrollover-Sampler — nicht die Zell-Konfiguration.

**Ehrliche Einschränkung:** ReplayKit kodiert während der Aufnahme 1180 × 2556 @ 60 fps und kostet selbst CPU und GPU. Ein Teil der 5,6 % geht auf das Aufnehmen zurück. Die *Form* des Befundes (flach über Geschwindigkeit, keine langen Hitches, leichte Erhöhung am Gestenbeginn) ist davon nicht betroffen, das Niveau schon.

---

## 1. Messmethode

Reproduzierbar, ohne Instruments und ohne Entwicklerprofil auf dem Gerät.

1. `AVAssetReader` liest den Videotrack, skaliert auf 64 × 640 BGRA.
2. Pro Frame wird ein Zeilen-Luminanzprofil (640 Werte) gebildet.
3. Zwischen aufeinanderfolgenden Frames wird die vertikale Verschiebung `dy` per SAD-Kreuzkorrelation (± 120 skalierte Zeilen) geschätzt → Scrollgeschwindigkeit in Punkten/s (1 skalierte Zeile = 3,99 Gerätepixel = 1,333 pt).
4. `mad` = mittlere absolute Profildifferenz. `mad < 0,06` ⇒ pixelidentischer Frame ⇒ **verworfener Frame**.
5. „Bewegung“ = geglättete Nachbargeschwindigkeit > 300 pt/s (Median über ± 4 Frames, Frame selbst ausgeschlossen — sonst würde der Drop seine eigene Klassifikation verfälschen).

Das Werkzeug liegt unter `docs/tools/scroll-frame-analysis.swift` (nicht committet, einzelne Datei, keine Abhängigkeiten):

```
swiftc -O docs/tools/scroll-frame-analysis.swift -o /tmp/sfa
/tmp/sfa docs/ScreenRecording1.MP4 > frames.csv
```

~~**Das ist die Regressionsmetrik für alle folgenden Änderungen.** Gleiche Liste, gleicher Wischablauf, Drop-Rate vorher/nachher. Zielwert: < 1 % bei Bewegung.~~
**Zurückgezogen** — siehe den Kasten am Dokumentanfang. Weder die Metrik noch
der Zielwert sind gültig.

---

## 2. Messergebnisse

Gesamter Scrollweg: **23 273 pt** über 45,81 s.

| Schwelle | Bewegungsframes | verworfen | Rate | Ereignisse | 1 Drop je |
|---|---|---|---|---|---|
| v > 300 pt/s | 1329 | 75 | **5,6 %** | 74 | 281 pt |
| v > 1000 pt/s | 522 | 28 | 5,4 % | 28 | 475 pt |
| v > 2000 pt/s | 87 | 3 | 3,4 % | 3 | 1018 pt |

Ereignislängen: 62 × ein Frame, 1 × zwei Frames. **Kein Ereignis ≥ 3 Frames während Bewegung.**

Drop-Rate nach Momentangeschwindigkeit — flach:

| Geschwindigkeit | Frames | Drops | Rate |
|---|---|---|---|
| 300–700 pt/s | 570 | 35 | 6,1 % |
| 700–1200 pt/s | 362 | 18 | 5,0 % |
| 1200–1800 pt/s | 256 | 17 | 6,6 % |
| 1800–2500 pt/s | 129 | 5 | 3,9 % |

Drop-Rate nach Listentiefe (3000-pt-Fenster): 9,4 % / 4,3 % / 6,1 % / 2,1 % / 4,1 % / 6,1 % / 6,7 % / 6,5 % — **kein Wachstum**, nur das erste Fenster (kalte Caches, DVFS-Anlauf) ist erhöht.

Drop-Rate nach Frames seit Gestenbeginn (21 Wischer): Frames 0–4 = **10,3 %**, danach 2–11 % ohne Trend.

Kontrolltest „passiert beim Drop etwas Sichtbares?“: Das Rest-Residuum nach Verschiebungskompensation ist im Frame direkt nach einem Drop, **geschwindigkeitsbereinigt**, nicht erhöht (Median 1,06 gegenüber Kontrolle 1,01). Ein einlaufendes Bild oder ein neu gerenderter Zellinhalt fällt also nicht systematisch mit dem Drop zusammen.

---

## 3. Was diese Messung ausschließt

Belastbar ausgeschlossen für *diese* Aufnahme:

* **Seiten-Append / Fan-out in `IOSUIKitArticleTimelineController.update`.** Ein Snapshot-Apply plus Layout-Invalidierung über 72 neue Zeilen wäre ein Mehr-Frame-Ereignis. Es gibt während Bewegung kein einziges. Die Reparaturen aus `a40e377`/`892eeda` (Reconfigure nur bei `.replace`, `cancelAllPrefetch` nur bei `.replace`, `invalidateLayout` nur bei `.replace`) wirken offenbar.
* **Feed-Icon-Dekodierung auf dem MainActor.** Bereits behoben (`IOSFeedIconImagePreparation`, `Task.detached(priority: .userInitiated)`), und ein Voll-PNG-Dekode wäre ein Mehr-Frame-Ereignis.
* **Kosten, die mit der Listenlänge wachsen** (O(N)-Rebuild aus Finding 3.2, globale Layout-Invalidierung). Kein Tiefentrend.
* **Scrollover-Mutationen.** Während Vorwärtsscrollens findet kein Core-Write und keine Präsentationsveröffentlichung statt; das hält.
* **SwiftUI-Invalidierung pro Frame.** `receiveScrolloverDirection`, `setScrolloverPresentationPhase`, `flushScrollover` und `markMeaningfulInteraction` schreiben ausschließlich in Zustände, die kein `body` liest. `ArticleListView.body` wird während reinen Scrollens nicht neu ausgewertet. Das Design ist an dieser Stelle korrekt.

Was die Messung **nicht** ausschließt: dass die genannten Fan-out-Ereignisse in *anderen* Situationen (Sync während Scrollen, Entfernen gelesener Artikel, Moduswechsel) weiterhin Mehr-Frame-Ereignisse erzeugen. Die offenen Punkte aus dem Vorgängerdokument bleiben gültig, sie sind nur nicht die Ursache des hier gefilmten Stockens.

---

## 4. Befunde

Sortiert nach erwartetem Effekt auf die **Pro-Frame-Kurve**, was nach Abschnitt 2 die richtige Zielgröße ist.

### Befund 1 — Zwei Offscreen-Render-Pässe pro sichtbarer Zelle, in jedem Frame

**Wo:** `ArticleListView.swift:1726–1741` (`feedIconContainer`), `:1810–1823` (`articleImageView`).

```swift
articleImageView.contentMode = .scaleAspectFill
articleImageView.clipsToBounds = true
articleImageView.layer.cornerRadius = 12
articleImageView.backgroundColor = .tertiarySystemFill
articleImageView.addSubview(imagePlaceholder)      // Sublayer
```

```swift
feedIconContainer.clipsToBounds = true
feedIconContainer.layer.cornerRadius = 11
feedIconContainer.addSubview(feedIconImageView)    // zwei Sublayer
feedIconContainer.addSubview(feedIconFallbackLabel)
```

Core Animation kann eine Eckenrundung nur dann kostenlos auflösen, wenn der Layer ausschließlich eine Hintergrundfarbe trägt. Sobald `masksToBounds` mit `contents` **und** Sublayern zusammentrifft, muss der Renderserver ein Offscreen-Ziel anlegen, dorthin komponieren, maskieren und zurückkomponieren — **pro Layer, pro Frame, solange die Zelle sichtbar ist**. Das ist kein einmaliger Aufwand beim Erscheinen.

Bei 2–3 sichtbaren Bildkarten und 4–6 sichtbaren Feed-Icons sind das **6–9 Offscreen-Pässe je Frame**. Auf einem TBDR-Grafikkern kostet jeder einen Render-Target-Wechsel; bei 1179 × 2556 ist das der größte konstante GPU-Term, den die App selbst kontrolliert.

Dass `imagePlaceholder` nach dem Laden nur `isHidden = true` bekommt, hilft nicht zuverlässig: der Sublayer bleibt Teil des Layerbaums.

**Warum das zum Messbild passt:** exakt konstant pro Frame, unabhängig von Geschwindigkeit und Listentiefe — genau die Signatur einer flachen 5,6-%-Drop-Rate.

**Konfidenz:** hoch für „existiert und ist konstant pro Frame“; die absolute Größe ist ohne GPU-Trace nicht bezifferbar.

**Reparatur (empfohlen, konzeptkonform):** Die Pipeline erzeugt bereits *anzeigefertige* Bitmaps. Sie soll sie **kompositionsfertig** erzeugen:

1. In `ArticleImagePipeline.downsample` das Bild im letzten Schritt in einen Kontext **exakter Slotgröße** zeichnen und dabei auf einen `UIBezierPath(roundedRect:cornerRadius:)` clippen. Die Slotgröße ist über `IOSUIKitArticleGeometry.imageSize(hasImage:)` bereits deterministisch und ändert sich nur mit der Geometrie-Identität, es gibt also sehr wenige verschiedene Größen. Der bestehende 64-px-Bucket bleibt für den *Decode*, die Rasterung erfolgt auf die exakte Zielgröße.
2. `articleImageView`: `clipsToBounds = false`, `cornerRadius = 0`, `backgroundColor = nil`, `contentMode = .scaleToFill` (Pixelgröße ist jetzt exakt, keine GPU-Skalierung mehr).
3. Den Platzhalter aus `articleImageView` herausnehmen und als Geschwisteransicht dahinter legen. Ein Layer mit *nur* Hintergrundfarbe und `cornerRadius` braucht keinen Offscreen-Pass.
4. In `IOSFeedIconImagePreparation.prepare` den Kreis in die 22-pt-Bitmap einbacken; `feedIconContainer` verliert `cornerRadius` und `clipsToBounds`.

Damit verschwinden alle Offscreen-Pässe der Timeline und zusätzlich die GPU-Skalierung pro Bild.

**Aufwand:** ca. 40 Zeilen, verteilt auf `ArticleImagePipeline.swift`, `NewsreaderStore.swift` und den Zellaufbau. Keine Produktänderung, keine zweite Geometrieimplementierung — die Radien sind bereits Konstanten.

---

### Befund 2 — Beide Dekodierpfade liefern RGBA statt des Core-Animation-nativen BGRA

**Wo:** `ArticleImagePipeline.swift:431–445` und `NewsreaderStore.swift:109–123`, jeweils:

```swift
bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
```

`premultipliedLast` ohne Byte-Order-Flag ist RGBA/Big-Endian. Das native Layer-Format auf Apple-GPUs ist **BGRA, `premultipliedFirst | byteOrder32Little`**. Wird ein `CGImage` in einem anderen Format an `layer.contents` gehängt, konvertiert Core Animation es — **auf dem Main Thread, während des CATransaction-Commits**, proportional zur Bildfläche.

Eine Artikelkarte ist bei 1088 × 612 px rund **2,66 MB**. Genau die Falle „wir haben im Hintergrund dekodiert, es kostet trotzdem Main-Thread-Zeit“, die der Vorgängerbericht als Finding 4.2(b) beschrieben hat: der `decompressed()`-Schritt wurde eingebaut, aber im falschen Zielformat.

**Warum das zum Messbild passt:** Bild-Completions sind über den Scroll verteilt und laufen zu dritt parallel; jede Konvertierung landet in einem Commit. Das erklärt einen Teil der Streuung, die die Frames über 16,7 ms kippt — es erklärt nicht die konstante Grundlast.

**Konfidenz:** hoch (bestätigter Formatfehler); Größenordnung geschätzt, nicht gemessen.

**Reparatur:** eine Zeile je Stelle:

```swift
bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
```

Sinnvollerweise gemeinsam mit Befund 1 umgesetzt, weil beide denselben Zeichenschritt betreffen.

---

### Befund 3 — Die gesamte Timeline komponiert transparent

**Wo:** `ArticleListView.swift:807` (`view.backgroundColor = .clear`), `:814` (`collectionView.backgroundColor = .clear`), `:801` (`configuration.backgroundColor = .clear`), `:1699–1700` (Zelle und `contentView` `.clear`); alle vier `UILabel` ohne Hintergrund; darunter SwiftUI `.background(.background)` (`:2148`).

Jedes Zellpixel wird also in jedem Frame gegen die dahinterliegende SwiftUI-Fläche alpha-gemischt, und jede Glyphe wird mit Alphakanal gerastert. Bei Vollbildhöhe ist das eine zusätzliche bildschirmfüllende Blend-Schicht pro Frame plus teurere Textrasterung pro erscheinender Zelle.

Der Hintergrund ist tatsächlich uniform `systemBackground` — die Transparenz kauft hier nichts.

**Reparatur:** `collectionView.backgroundColor = .systemBackground`, `contentView.backgroundColor = .systemBackground`, und für die vier Labels `backgroundColor = .systemBackground` mit `isOpaque = true`. Visuell identisch, solange die SwiftUI-Fläche `.background` bleibt.

**Konfidenz:** mittel-hoch für einen messbaren Effekt, hoch dafür, dass es risikolos ist. Dark/Light löst UIKit über die dynamische Farbe selbst auf.

**Vorbehalt:** Falls die Timeline später auf einer nicht-uniformen Fläche liegen soll (Material, Verlauf), fällt dieser Gewinn weg. Das wäre eine Produktentscheidung, keine technische.

---

### Befund 4 — Der Scrollover-Sampler macht in jedem Frame Arbeit über 96 Einträge

**Wo:** `ArticleListView.swift:1162–1165` (`scrollViewDidScroll` → `sampleScrolloverGeometry`), `:1210–1230`, `:382–481` (`IOSUIKitScrolloverGeometryTracker`), `:298–317` (`IOSUIKitResolvedScrolloverFrameStore`).

Pro `scrollViewDidScroll`, also 60-mal pro Sekunde:

1. `refreshResolvedVisibleScrolloverFrames()` iteriert `collectionView.visibleCells` (Array-Allokation) und ruft `record(...)` je Zelle.
2. **Copy-on-Write-Vollkopie:** `sample.rowFrames` erhält denselben Dictionary-Puffer wie `resolvedScrolloverFrames.framesByID`, und `receive` legt ihn in `previousSample` ab. Im nächsten Frame ist der Puffer damit nicht mehr eindeutig referenziert, und die erste `framesByID[id] = frame`-Zuweisung **kopiert alle 96 Einträge**. Jeden Frame.
3. `hasMaterialLayoutChange` läuft über bis zu 96 `previous.rowFrames` mit je einem Dictionary-Lookup.
4. `visibleIDs(in:)` erzeugt per `compactMap` ein Array und daraus ein `Set` — zwei Allokationen.
5. `retainBoundedGeometry` merged bis zu 96 Einträge in `retainedFrames` und trimmt bei Überschreitung per **`sorted()` über 96 Tupel plus vollständigem Dictionary-Neuaufbau**.
6. `Set(retainedFrames.keys).union(visibleIDs)` — zwei weitere Sets à ~96 Elemente.

Zusätzlich pro *neu erscheinender* Zelle: `IOSUIKitResolvedScrolloverFrameStore.record` trimmt bei Kapazität 96 auf exakt 96 herunter, sodass **jede neue Artikel-ID erneut einen Sort plus Dictionary-Neuaufbau auslöst** — dauerhaft, nicht nur einmalig.

Größenordnung: einige zehn bis gut hundert Mikrosekunden und rund sechs Heap-Allokationen pro Frame. Das Vorgängerdokument hat das als „real, aber zu klein“ eingeordnet — bei einem *Einzelereignis* von 100 ms stimmt das. Bei einer flachen 5,6-%-Überschreitungsrate ist konstante Pro-Frame-Arbeit genau die richtige Zielgröße, und Allokator-Bursts sind zusätzlich eine der plausibelsten Quellen der Streuung, die einzelne Frames kippt.

**Konzeptfrage (die eigentliche Empfehlung):** Der gesamte Apparat existiert, um eine einzige Frage zu beantworten — *welche beobachteten Zeilen haben beim Vorwärtsscrollen die obere Viewport-Kante überschritten?* Bei einer geordneten Liste mit bekannten Höhen ist die Antwort ein **zusammenhängender Indexbereich** zwischen `previous.effectiveTop` und `sample.effectiveTop`. Das ist eine allokationsfreie Schleife über wenige Indizes; die 96er-Framecaches, die Set-Algebra, der Sort und die COW-Kopie entfallen ersatzlos.

Das ist kein Micro-Tuning, sondern das Entfernen eines Zwischenmodells, das die Geometrie des Collection-View ein zweites Mal nachbaut. Passend zur Vorgabe, keine technischen Schulden zu veröffentlichen.

**Aufwand:** mittel. Der Tracker hat eine große, gut abgedeckte Testsuite; die Verhaltenskontrakte (nur beobachtete Zeilen, nur vorwärts, Rearm, Bottom-Terminierung) müssen erhalten bleiben. Rechne mit einem Tag inklusive Testanpassung.

**Sofortmaßnahme ohne Umbau**, falls der Umbau später kommen soll: `previousSample` nur die skalaren Felder speichern lassen (nicht `rowFrames`) — das allein entfernt die COW-Vollkopie pro Frame. Drei Zeilen.

---

### Befund 5 — Doppelte und ungenutzte Arbeit pro erscheinender Zelle

Einzeln klein, gemeinsam der Grund, warum ausgerechnet Frames mit erscheinender Zelle am ehesten kippen.

**5a — `updateAccessibility()` läuft zweimal pro erscheinender Zelle.**
`ArticleListView.swift:2087–2092`, aufgerufen aus `updateStatus` (`:1974`), das seinerseits aus `configure` (`:1927`) **und** aus `reconcilePresentationForDisplay` in `willDisplay` (`:1137`) kommt.
Jeder Aufruf: zwei `String(localized:)`-Bundle-Lookups (jeweils Lock plus Tabellensuche), eine Interpolation über Titel + Feedtitel + Datum (~100 Zeichen, Heap), und zwei `accessibilityLabel`/`accessibilityValue`-Setter, die über `objc_setAssociatedObject` in einen globalen, gesperrten Speicher schreiben.
Das ist vollständig verschwendet, solange keine Bedienungshilfe läuft.
**Reparatur:** `accessibilityLabel` und `accessibilityValue` als berechnete Overrides implementieren. UIKit fragt sie nur ab, wenn ein Assistenzclient sie braucht. Der bestehende Zustand (`currentTitle`, `currentIsRead`, …) ist bereits vorhanden. ~15 Zeilen, keine Verhaltensänderung.

**5b — `prepareVisibleLayoutMetrics()` in `willDisplay` ist O(sichtbar) pro erscheinender Zelle.**
`:1128` und `:1441–1444`. Bei ~6 sichtbaren Zellen werden je erscheinender Zelle 6 × `renderedItem` + `preparedLayoutInput` + `IOSUIKitArticleLayoutKey` gebaut, letzterer **hasht vier vollständige Strings** (Titel, Feedtitel, Datum, Preview ≈ 250 Zeichen).
`prefetchItemsAt` und `replacePreparedLayoutWindow` decken dieselben Zeilen bereits ab.
**Reparatur:** ersatzlos streichen oder auf die eine gerade erscheinende Zelle beschränken. Zwei Zeilen.

**5c — `Locale.current.identifier` bei jedem `preparedLayoutInput`, und es wird nie benutzt.**
`:1389`. `Locale.current.identifier` bridged eine `NSString` und allokiert. Das Feld `localeIdentifier` ist Teil von `IOSUIKitArticleLayoutInput`, aber **weder in `IOSUIKitArticleLayoutKey` noch irgendwo in `IOSUIKitArticleLayoutEngine.metrics`** vorhanden. Es wird pro Aufruf berechnet und nie gelesen.
Gleiches gilt abgeschwächt für `view.effectiveUserInterfaceLayoutDirection` (läuft die View-Hierarchie hoch) und `view.traitCollection.preferredContentSizeCategory` — beides ändert sich nur mit der Geometrie-Identität, die ohnehin bereits verfolgt wird (`updateGeometryIfNeeded`, `:857`).
**Reparatur:** `localeIdentifier` entfernen oder in den Key aufnehmen (es korrekt zu berücksichtigen wäre sauberer, aber dann muss es auch wirken); Trait-Werte in einem `IOSUIKitArticleLayoutEnvironment` zwischenspeichern und in `updateGeometryIfNeeded` erneuern. ~20 Zeilen.

**5d — `IOSUIKitArticleGeometry` wird pro `configure` etwa fünfmal konstruiert.**
Im `cellProvider` (`:844–845`) einmal für `Metrics` und einmal für `layoutVariant`, in `configure` (`:1017`) erneut, dann in `metrics.imageSize` und `metrics.layoutVariant` je noch einmal (`:1647–1653`).
Die bereits berechneten `preparedLayoutMetrics` enthalten `variant`, `imageFrame`, `horizontalInset` und `verticalInset` schon. `configure` und `applyLayout` könnten sie direkt konsumieren, statt die Geometrie neu abzuleiten.
**Reparatur:** klein, aber sie berührt den Zell-Konfigurationspfad; sinnvoll gemeinsam mit 5c.

**5e — `ArticleImageRequest.cacheKey` baut pro Aufruf eine `NSString`.**
`ArticleImagePipeline.swift:458`: `"\(url.absoluteString)|\(maxPixelDimension)" as NSString` — String-Interpolation plus Bridge, zwei Allokationen, bei jedem `cachedImage(for:)` auf dem Main Thread. Zusätzlich nimmt `ArticleImageCache.lookup` für die Trefferzählung ein `NSLock`, das mit bis zu drei Dekodier-Threads geteilt wird.
**Reparatur:** Key im `ArticleImageRequest` einmalig speichern; die Metrikzählung hinter `#if DEBUG || FLUX_PERFORMANCE_DIAGNOSTICS` legen, damit der Lock im Release-Pfad ganz entfällt.

**5f — `reconcilePresentationForDisplay` wiederholt in `willDisplay`, was `configure` gerade getan hat.**
`:1123–1131`. Für eine frisch konfigurierte Zelle sind `updateStatus` und `updateFeedIcon` bereits aktuell. Nötig ist der Abgleich nur für Zellen, die UIKit ohne erneutes `configure` wieder einblendet.
**Reparatur:** eine Revisionsmarke pro Zelle (`configuredPresentationRevision`) und Frühausstieg.

---

### Befund 6 — Release baut weiterhin ohne Whole-Module-Optimierung und ohne Diagnose

**Wo:** `apple/ios/FluxNews.xcodeproj/project.pbxproj`. `SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG` steht ausschließlich in der Debug-Konfiguration (Zeile 404). Die Release-Konfiguration setzt weder Compilation Conditions noch `SWIFT_COMPILATION_MODE`; der Xcode-Default ist `singlefile`.

Beides ist unverändert seit `a40e377` offen.

* `SWIFT_COMPILATION_MODE = wholemodule` — der Scroll-Hotpfad verteilt sich über `ArticleListView.swift`, `IOSUIKitArticleLayoutEngine.swift`, `BrowserPresentation.swift` und `ArticleImagePipeline.swift`. Ohne WMO gibt es kein dateiübergreifendes Inlining der vielen winzigen Geometrie-Accessoren und keine Spezialisierung der Dictionary-/Set-Generics auf dem Scrollpfad. Für ein Problem, das aus fehlendem Kopfraum besteht, sind ein paar Prozent über die gesamte Kurve genau die richtige Art von Gewinn — für eine Zeile.
* `SWIFT_ACTIVE_COMPILATION_CONDITIONS = FLUX_PERFORMANCE_DIAGNOSTICS` — schaltet die vorhandenen Zähler wieder ein. In Kombination mit der Videomessung aus Abschnitt 1 ergibt das eine vollständige Vorher/Nachher-Kette ohne Instruments.

---

## 5. Konzeptfragen

Ausdrücklich eingeladen, deshalb explizit beantwortet.

### A. Bleibt `UICollectionViewCompositionalLayout.list` mit geschätzter Selbstdimensionierung die richtige Grundlage?

`ArticleListView.swift:798–803`. Die Liste startet mit geschätzten Höhen und lernt die echte Höhe erst über `preferredLayoutAttributesFitting`, wenn die Zelle erscheint. Jede erscheinende Zelle löst damit einen `shouldInvalidateLayout(forPreferredLayoutAttributes:)`-Rundlauf aus, obwohl `IOSUIKitArticleLayoutEngine` die exakte Höhe längst kennt und cached.

**Die Messung entlastet diesen Punkt teilweise:** Die Drop-Rate wächst nicht mit der Listentiefe, die Neuauflösung ist also lokal und beschränkt, nicht global.

Ein kleines eigenes `UICollectionViewLayout` für eine einspaltige Vertikalliste mit bekannten Höhen würde `preferredLayoutAttributesFitting` komplett entfernen, `contentSize` stabil machen und den Scrollindikator korrekt. Der Preis: es braucht Höhen für **alle** geladenen Zeilen, nicht nur für das vorbereitete Fenster. Machbar, weil die Messung ohnehin off-main läuft — 72 Zeilen pro Seite à ~0,3 ms sind ~22 ms Hintergrundarbeit je Seite.

**Empfehlung: aufschieben.** Es ist die architektonisch sauberere Lösung und keine technische Schuld im Sinne der Vorgabe, aber die Messung weist ihm derzeit keinen relevanten Anteil zu. Erst nach Befund 1–6 neu bewerten. Wichtig: das ist etwas **anderes** als U3.7.5 (manuelles Zell-Layout) und deutlich risikoärmer — es entsteht keine zweite Geometrieimplementierung, weil die Höhe schon aus derselben Engine kommt.

### B. Wie teuer sind die beiden Glas-Oberflächen über der scrollenden Liste?

`ContentView.swift:229–231` (Large Title mit `navigationSubtitle` plus `.bottomBar`-Toolbar) zusammen mit `ArticleListView.swift:2145` (`.ignoresSafeArea(.container, edges: [.top, .bottom])`).

Unter iOS 26 tasten Navigationsleiste und untere Leiste den dahinterliegenden Inhalt kontinuierlich ab. Weil die Timeline bewusst unter beide Leisten scrollt, ist die abgetastete Fläche maximal, und der Inhalt ändert sich in jedem Frame. Das ist nach den Offscreen-Pässen der zweitgrößte konstante GPU-Term — und im Gegensatz zu Befund 1 ist er eine **Designentscheidung**, keine Unachtsamkeit.

**Empfehlung: nicht anfassen, aber quantifizieren.** Ein einziger Vergleichsdurchlauf mit temporär opaken Leisten (oder ohne `ignoresSafeArea`) und derselben Videomessung beziffert den Anteil in einer halben Stunde. Erst wenn Befund 1–3 die Drop-Rate nicht unter ~1 % drücken, wird das eine echte Produktabwägung.

### C. Was ist der nächste Hebel, wenn Befund 1–6 nicht reichen?

Nicht U3.7.5. Der größte verbliebene Main-Thread-Posten pro Zelle ist nicht der Constraint-Solver, sondern die **Textrasterung der vier `UILabel` im CATransaction-Commit** — Titel mehrzeilig plus Preview dreizeilig auf 361 pt Breite, bei 3× Skalierung. Manuelles Frame-Setzen (U3.7.5) entfernt davon nur die kleinere Hälfte.

Der wirksame Hebel wäre vorgesetzter Core-Text-Satz mit eigenem Zeichnen, wofür `IOSUIKitArticleLayoutEngine` bereits sämtliche Subview-Frames liefert. Das ist eine große Zusage und braucht vorher Messwerte.

Ein billiges Zwischenexperiment: `layer.drawsAsynchronously = true` auf `titleLabel` und `previewLabel`. Bei textlastigen Zellen verschiebt das die Rasterung vom Main Thread; bei einfachen Inhalten ist es eine Pessimierung. Eine Zeile, ein Messdurchlauf entscheidet — ausdrücklich als Experiment, nicht als Empfehlung.

Ebenfalls offen und billig: `textStack` ist ein `UIStackView` mit vier arrangierten Subviews, und `previewLabel.isHidden` wird pro `configure` gesetzt (`:1915`). Stack-Views verwalten Constraints für ausgeblendete Views dynamisch und sind spürbar teurer als direkte Constraints. Ein Ersatz durch vier direkte Constraint-Ketten ist ~40 Zeilen und risikoarm, aber ohne Messung nicht zu rechtfertigen.

---

## 6. Empfohlene Reihenfolge

> **Nicht mehr befolgen.** Dieser Plan hängt am Bezugswert aus dem Kasten am
> Dokumentanfang, der zurückgezogen ist. Er ist als Protokoll der damaligen
> Planung erhalten.
>
> Tatsächlich passiert ist: `wholemodule` gilt im Release-Archiv,
> `FLUX_PERFORMANCE_DIAGNOSTICS` wurde **nie** im Release gesetzt, und die
> Diagnose-Oberfläche, die es freigeschaltet hätte, ist am 18. September
> entfernt worden. Die Untersuchung endete mit einer Darstellungsentscheidung
> statt mit einer Leistungskorrektur — siehe
> `IOS_TIMELINE_PERFORMANCE_DIAGNOSTIC_CLEANUP.md`.

~~**Schritt 0 — Messkette schließen (Stunden).**
`SWIFT_COMPILATION_MODE = wholemodule` und `SWIFT_ACTIVE_COMPILATION_CONDITIONS = FLUX_PERFORMANCE_DIAGNOSTICS` in Release (Befund 6). Danach eine Referenzaufnahme mit demselben Wischablauf. Aktueller Bezugswert: **5,6 % verworfene Frames bei Bewegung, 1 Drop je 281 pt.**
WMO ist gleichzeitig schon eine Optimierung, die Referenzaufnahme also nach dem Umstellen erstellen.~~

**Schritt 1 — Kompositionskosten senken (Befund 1, 2, 3).**
Ein zusammenhängender Änderungssatz, weil alle drei denselben Bildpfad betreffen: kompositionsfertige Bitmaps in exakter Slotgröße, mit eingebackenen Ecken, im nativen BGRA-Format; danach die Offscreen-Auslöser aus den Views entfernen und die Komposition opak machen. Nach Abschnitt 2 ist das der Änderungssatz mit dem größten erwarteten Effekt auf die flache Drop-Rate. Messen.

**Schritt 2 — verschwendete Arbeit entfernen (Befund 5).**
5a, 5b, 5c und 5e sind reine Streichungen ohne Verhaltensfläche und zusammen etwa ein halber Tag. 5d und 5f gehören dazu, berühren aber den Konfigurationspfad und brauchen etwas mehr Sorgfalt. Messen.

**Schritt 3 — Scrollover-Sampler (Befund 4).**
Zuerst die Drei-Zeilen-Sofortmaßnahme (keine `rowFrames` in `previousSample`). Der eigentliche Umbau auf eine Indexbereichs-Auswertung lohnt sich, wenn nach Schritt 1 und 2 noch etwas übrig ist — und er lohnt sich unabhängig davon als Vereinfachung.

**Schritt 4 — neu bewerten.**
Erst dann sind Konzeptfrage A (eigenes Collection-View-Layout), B (Glasflächen) und C (Core-Text-Zeichnen) mit Zahlen statt Vermutungen zu entscheiden.

**Was ausdrücklich nicht ansteht:** U3.7.5 in seiner bisherigen Begründung. Die Sizing-Kosten sind bereits entfernt, und die Messung weist den verbleibenden Anteil nicht dem Constraint-Solver zu.

---

## 7. Offene Frage an die Produktentscheidung

Nur eine, und sie blockiert Schritt 1 nicht:

Befund 3 (opake Komposition) setzt voraus, dass die Timeline dauerhaft auf einer uniformen `systemBackground`-Fläche liegt. Falls für die Timeline später ein nicht-uniformer Hintergrund (Material, Verlauf, Bild) vorgesehen ist, fällt dieser Gewinn weg und die Änderung sollte unterbleiben. Wenn diese Absicht nicht besteht, ist Befund 3 unbedenklich.
