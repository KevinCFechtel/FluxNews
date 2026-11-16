# Flux: Prüfung der Scroll-Ruckler auf dem iPhone 15

Stand: 11. September 2026. Geprüfter `main`: **2dbec0d3fc0368b15d04ff679fd79dc5e6bcdfc7**, zum Abschluss erneut über GitHub bestätigt. Gerät und Betriebssystem laut Nutzer: physisches iPhone 15, iOS 26.6.1.

## Ergebnis

Die Aufnahme enthält nachvollziehbare Bewegungsunterbrechungen. Der aktuelle Code hat bereits einen `UICollectionView`-Container und native UIKit-Zellen. Der Architekturwechsel ist damit erfolgt; die Umsetzung erfüllt die beabsichtigte Entkopplung von Scrollen, Layout und Statusänderungen aber noch nicht vollständig.

Die wichtigsten Änderungen sind ein dauerhaft aufgebautes, wiederverwendbares Zell-Layout mit gecachter Größenbestimmung sowie eine Übergabe gezielter Änderungen an den UIKit-Controller. Zusätzlich gehört die Geometrieerfassung aus dem wiederholten Abfragen eines großen Layoutbereichs herausgelöst. Diese Änderungen sind anhand des Codes begründbar. Ein erneuter Vergleich verschiedener Listenframeworks ist dafür keine Voraussetzung.

Die Reihenfolge unten ist eine technische Priorisierung anhand der vorhandenen Ausführungspfade, keine Messung ihrer jeweiligen CPU-Anteile. Die Aufnahme enthält keine Stacktraces. Der genaue Build-Commit und Debug-/Release-Modus des aufgenommenen Binaries lassen sich daraus nicht feststellen.

## 1. Was die Aufnahme belegt

Untersucht wurde `ScreenRecording_09-11-2026 14-52-26_1.MP4`: ungefähr 29,24 Sekunden, 1180 × 2556 Pixel, HEVC, nominell 60 Videobilder pro Sekunde. Die Videofrequenz ist keine Messung der tatsächlich von der App gelieferten Bildrate.

Nach der visuellen Übersicht wurden die decodierten Bilder mit ihren Präsentationszeitstempeln verglichen. Für die Bewegungsanalyse wurde ein innerer Listenausschnitt ohne Navigationsleiste und untere Bedienelemente verwendet. Eine auffällige Sequenz wurde anschließend in Originalauflösung kontrolliert.

| Zeit in der Aufnahme | Beobachtung |
|---|---|
| 3,645 s | Die Liste hat eine neue Position erreicht. |
| 3,662 s | Der untersuchte Listeninhalt bleibt praktisch unverändert. |
| 3,678 s | Der Listeninhalt bleibt weiterhin praktisch unverändert. |
| 3,695 s | Die Bewegung setzt mit einem deutlich größeren Positionsschritt fort. |
| 5,143–5,193 s | Die Bewegungsanalyse findet erneut zwei praktisch unveränderte Zwischenbilder mit anschließendem größeren Schritt. |

Im ersten Beispiel liegen ungefähr **50 ms zwischen zwei tatsächlichen Positionsänderungen**. Das sind drei Anzeigeintervalle im nominellen 60-Hz-Raster, einschließlich des ersten dargestellten Bildes. Der mittlere absolute Helligkeitsunterschied des überprüften Ausschnitts in Originalauflösung beträgt an den beiden Zwischenbildern nur etwa 0,012 und 0,008 auf der Skala 0–255. Bei den Bewegungen unmittelbar davor liegt er ungefähr bei 36,6. Das belegt das Halten des Inhalts in dieser Datei.

Die separat beigefügte Datei `hold_detail_3_65.png` zeigt fünf aufeinanderfolgende Bilder derselben Sequenz. Die ersten drei haben praktisch dieselbe Listenposition. Die rote Linie ist eine nachträglich eingezeichnete Positionshilfe.

Längere Pausen zwischen Wischgesten wurden nicht pauschal als Ruckler bewertet. Ohne Touch- und Laufzeitdaten lässt sich nicht endgültig zwischen App-, System- und Aufnahmeeffekten unterscheiden. Insbesondere werden hier keine durchschnittliche App-FPS, keine Hitch-Rate und keine millisekundengenauen Laufzeiten einzelner Funktionen behauptet. Die Beobachtung stützt den gemeldeten Eindruck und rechtfertigt die folgende Codeprüfung.

## 2. Was auf main bereits sinnvoll umgesetzt ist

- Die produktive Timeline verwendet native `UICollectionView`-Zellen. Der frühere SwiftUI-Geometriecontroller ist nicht mehr der aktive Scrollover-Sensor.
- Die Diffable Data Source verwendet Artikel-IDs. Bei unveränderten IDs und unveränderter Reihenfolge wird im Controller kein struktureller Snapshot angewendet.
- Read-Änderungen erreichen vorhandene sichtbare Zellen über `updateStatus`; die Farbe und der Ungelesen-Punkt benötigen grundsätzlich keinen Inhaltsneuaufbau.
- Der neue Tracker begrenzt gespeicherte Geometrie auf 96 Einträge. Der frühere Verlaufsscan über alle bisher gesehenen Artikel ist nicht der aktuelle aktive Sensorpfad.
- Artikelbilder werden bereits mit ImageIO heruntergerechnet und unmittelbar decodiert; es gibt einen Bildcache, Request-Deduplizierung und UIKit-Prefetching.
- Scrollover-Schreibvorgänge rufen den Core in einem abgekoppelten Task auf. Sichtbare Read-Rückmeldungen werden beim Vorwärtsscrollen gesammelt und bei Richtungswechsel beziehungsweise Idle veröffentlicht.

Diese Fortschritte bleiben Grundlage der Reparatur. Insbesondere ist „noch einen Bildcache hinzufügen“ keine ausreichende Beschreibung der noch notwendigen Arbeit.

## 3. Priorität 1: Zellaufbau und Größenbestimmung stabilisieren

Fundstelle: [ArticleListView.swift, geprüfter Commit](https://github.com/KevinCFechtel/Flux/blob/2dbec0d3fc0368b15d04ff679fd79dc5e6bcdfc7/apple/ios/FluxNews/ArticleListView.swift), Symbole `IOSUIKitArticleCell.configure` und `preferredLayoutAttributesFitting`.

`configure` entfernt bei jeder Konfiguration die angeordneten Unteransichten aus `rootStack`, entfernt sie auch aus der View-Hierarchie und fügt Bild- und Textansichten anschließend erneut ein. Vorhandene Bildgrößen-Constraints werden deaktiviert und durch neue ersetzt. Das geschieht auch beim Konfigurieren einer wiederverwendeten Zelle für denselben Darstellungsmodus.

`preferredLayoutAttributesFitting` führt bei jedem Aufruf eine neue `systemLayoutSizeFitting`-Berechnung aus. Es gibt hier keinen an Inhalt, Breite und Typografie gebundenen Messwertcache. Die Zelle enthält mehrere verschachtelte Stack Views und mehrzeiligen Text. Damit führt der Vorbereitungspfad neuer Zellen sowohl Hierarchie-/Constraint-Änderungen als auch Text- und Auto-Layout-Arbeit auf dem UI-Thread aus.

Der Aufwand ist aus dem Code ersichtlich. Wie oft UIKit dieselbe Zelle im konkreten Lauf erneut vermisst und wie viele Millisekunden die Aufrufe dauern, ist nicht gemessen. Apple beschreibt die Vorbereitung und Größenbestimmung neuer Zellen ausdrücklich als mögliche Ursache von Scroll-Unterbrechungen; Prefetching verschafft dafür zusätzliche Zeit, ersetzt aber keine günstige Konfiguration. [Apple: Make blazing fast lists and collection views](https://developer.apple.com/videos/play/wwdc2021/10252/)

**Konkrete Änderung:**

1. Den View- und Constraint-Aufbau aus der wiederholten Inhaltskonfiguration entfernen. Dauerhafte Layoutvarianten für kompakt, visuell im Hochformat und visuell im Querformat verwenden; unterschiedliche Reuse-Varianten sind eine mögliche Umsetzung.
2. Bei gleicher Layoutvariante ausschließlich geänderte Texte, Bilder, Statuswerte und gegebenenfalls Constraint-Konstanten setzen. Kein Entfernen und erneutes Einfügen unveränderter Unteransichten.
3. Gemessene Höhen anhand eines vollständigen Layoutschlüssels wiederverwenden: Artikel-ID/Inhaltsrevision, tatsächlich verfügbare Textbreite, Darstellungsmodus, Preview-Zeilen, Dynamic Type, relevante Schrift-/Sprach-/Schreibrichtungsparameter und bildabhängige Layoutvariante. Read/Starred und geladene Bildpixel dürfen diesen Schlüssel nicht ändern.
4. Cachetreffer in der Größenbestimmung ohne erneuten Auto-Layout-Solver beantworten. Erstberechnungen begrenzt vorbereiten; keine synchrone Vorberechnung der gesamten Historie beim Scrollbeginn. UIKit-Views ausschließlich auf dem Main Actor behandeln.
5. Bei Breiten- oder Typografieänderungen Layoutrevision und Cache konsistent wechseln und den sichtbaren Artikelanker erhalten. Höhe und endgültiges Zell-Layout müssen dieselben Regeln verwenden.

Das Ziel ist ein kontrollierter nativer Zellrenderer. Ein vollständig eigener Layoutalgorithmus ist eine mögliche Vertiefung, falls für die endgültige Text-/Bildanordnung nötig; eine solche Neuerfindung ist durch die Aufnahme allein nicht als zwingend bewiesen.

## 4. Priorität 2: Einzelne Änderungen dürfen nicht die gesamte Liste aufbereiten

Fundstellen in derselben Datei: `ArticleListView.timelineItems`, `IOSUIKitArticleTimelineView.updateUIViewController` und `IOSUIKitArticleTimelineViewController.update`. Ergänzend: [NewsreaderStore.swift](https://github.com/KevinCFechtel/Flux/blob/2dbec0d3fc0368b15d04ff679fd79dc5e6bcdfc7/apple/ios/FluxNews/NewsreaderStore.swift), `ArticleRowPresentationState` und `requestFeedIcon`.

`timelineItems` läuft über **alle geladenen Artikel**. Dabei liest der SwiftUI-Body für jeden Artikel `content`, `isRead`, `isStarred` und `feedIcon.image` aus beobachtbaren Objekten. Die oberste Timeline-View wird dadurch von den einzelnen Zuständen abhängig. Eine Änderung kann eine erneute Auswertung des vollständigen Mappings auslösen; mehrere Änderungen können zwar in einer SwiftUI-Transaktion zusammenfallen, beseitigen den linearen Aufwand aber nicht.

Anschließend erzeugt `update` erneut das vollständige ID-Array, vergleicht die Struktur, durchsucht alle Elemente nach explizitem Unread und baut `itemsByID` vollständig neu auf. Erst danach entscheidet der Code, welche sichtbaren Zellen tatsächlich ein kleines Update benötigen.

**Die Snapshot-Unterdrückung funktioniert, aber die davor ausgeführte vollständige Datenaufbereitung bleibt bestehen.** Bei N geladenen Artikeln bleibt ein einzelnes Icon-/Statusereignis ein möglicher O(N)-UI-Pfad. Wie viele Artikel im aufgenommenen Lauf geladen waren, lässt sich aus dem sichtbaren Ungelesen-Zähler nicht ableiten.

Apple erläutert, dass auch indirekte Zugriffe auf beobachtete Eigenschaften Abhängigkeiten erzeugen und unnötige View-Updates verursachen können. Die konkrete Zuordnung zur Flux-Timeline folgt aus den oben genannten Property-Zugriffen. [Apple: Optimize SwiftUI performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/306/)

**Konkrete Änderung:**

- Strukturelle Änderungen mit einer eigenen Revision und stabilen IDs an den Controller übergeben. Vollständiges Aufbereiten nur beim tatsächlichen Austausch von Inhalt, Reihenfolge oder Mitgliedschaft.
- Read-/Starred-Änderungen direkt als Änderungen der betroffenen IDs an den bestehenden Präsentationszustand des Controllers liefern. Geänderte Feed-Icons über Feed-ID/Variante an die zugehörigen gebundenen Zellen liefern.
- Die SwiftUI-Bridge beobachtet Struktur und Darstellungsparameter, nicht die Status- und Icon-Eigenschaften jedes Artikels. Eine bloße spätere `guard`-Abfrage im Controller genügt nicht, solange `timelineItems` vorher weiterhin alle Elemente aufbereitet.
- Kein zweiter fachlicher Wahrheitsbestand: Die native Darstellung erhält die benötigten Projektionen und Änderungen des bestehenden Store-Zustands. Der Rust-Core bleibt für Persistenz zuständig.
- Auch vorbereitete, noch nicht sichtbare Zellen berücksichtigen. `willDisplay` führt aktuell nur eine Ende-der-Liste-Prüfung aus. Dort darf ein vorbereiteter älterer Status nicht unbemerkt sichtbar werden. Ein günstiger Abgleich nach ID/Revision muss ohne komplettes Layout-Reconfigure möglich sein.
- Die Suchergebnisse verwenden inzwischen dieselbe UIKit-Komponente. Änderungen am gemeinsamen Controller und seiner Übergabe müssen auch diesen Aufrufer berücksichtigen.

## 5. Priorität 3: Scrollover mit bereits aufgelöster Geometrie ausführen

Fundstellen: `sampleScrolloverGeometry`, `IOSUIKitScrolloverGeometryTracker.receive` und `hasMaterialLayoutChange` in `ArticleListView.swift`.

Bei jedem aktiven Scroll-Callback fragt der Sensor `layoutAttributesForElements` für einen Bereich von drei Viewport-Höhen ab und baut daraus ein neues Dictionary. Das ist räumlich begrenzt und kein Vollscan aller Artikel. Es koppelt den Scroll-Callback aber weiterhin an Layoutabfragen, inklusive nahe gelegener, möglicherweise noch geschätzter Zellgeometrie.

Eine Frame-Änderung irgendeiner in beiden Samples enthaltenen Zeile führt im Tracker zu einer Neubasierung. Die Verbindung aus laufendem Self-Sizing und einem größeren Abfragebereich kann damit zusätzlich gültige Erkennungsschritte aussetzen. Ob dies im Video passiert, ist ohne entsprechende Laufzeitereignisse offen.

**Konkrete Änderung:** Aufgelöste Frames tatsächlich sichtbarer Zellen übernehmen und nur die für Austrittsüberschreitungen nötigen vorherigen Frames behalten. Die Erfassung mit dem abgeschlossenen Layout koordinieren, ohne aus `scrollViewDidScroll` ein erzwungenes `layoutIfNeeded` auszulösen. Im Scroll-Callback nur Offset/Richtung und bereits verfügbare begrenzte Geometrie auswerten. Geschätzte oder nur vorbereitete, nie sichtbare Zeilen qualifizieren nicht als gesehen.

Dabei müssen die bereits vereinbarten Regeln erhalten bleiben: echte Vorwärtsüberschreitung, keine Markierung übersprungener ungesehener Artikel, korrekte Richtungswechsel und Terminalbehandlung, Neubasierung bei echten Layoutwechseln sowie fortgesetzte Erkennung in derselben Geste. Keine zeitbasierte Exposure-Heuristik als Ersatz einführen.

## 6. Weitere konkrete Reparaturen

### Statusänderungen müssen wirklich geometrieneutral sein

`updateStatus` setzt `starImageView.isHidden`. Der Stern ist ein angeordnetes Element der horizontalen `titleRow`. Ausblenden ändert damit den für den mehrzeiligen Titel verfügbaren Platz und kann dessen Höhe verändern. Das ist ein konkreter Verstoß gegen geometrieneutrale Statusupdates, aber kein Nachweis für die Ruckler des reinen Vorwärtsscrollens im Video.

Die Sternfläche dauerhaft reservieren oder den Stern ohne Einfluss auf die Textgeometrie platzieren. Sichtbarkeit über einen geometrieneutralen Präsentationswert ändern. Derselbe Titel muss vor und nach Read, Starred und Undo dieselbe Höhe behalten.

### Bildpipeline: Begrenzung, Priorität und Consumer-Lebensdauer

Fundstelle: [ArticleImagePipeline.swift](https://github.com/KevinCFechtel/Flux/blob/2dbec0d3fc0368b15d04ff679fd79dc5e6bcdfc7/apple/ios/FluxNews/ArticleImagePipeline.swift), `image(for:)`; außerdem `configureArticleImage` und die Prefetch-Callbacks im Controller.

Das Downsampling ist bereits außerhalb des Main Actors und der synchrone Cachezugriff ist `nonisolated`. Diese positiven Eigenschaften dürfen nicht als fehlend beschrieben werden. Der im Pipeline-Actor angelegte Task führt die synchrone Decodierung allerdings im geerbten Actor-Kontext aus und belegt damit währenddessen dessen Ausführung. Ein explizites appweites Limit und eine Bevorzugung sichtbarer Anforderungen gegenüber spekulativem Prefetch fehlen. Das Canceln eines äußeren Consumers beendet zudem nicht automatisch den geteilten zugrunde liegenden Auftrag.

Den Actor auf Request-/Cache-Verwaltung beschränken und Decodierung über einen begrenzten Executor ausführen. Sichtbare Anforderungen priorisieren, gleichartige Anforderungen weiterhin zusammenfassen und Arbeit ohne verbleibenden Consumer kontrolliert verwerfen. Keine unbeschränkte Task-Parallelität als vermeintliche Beschleunigung einführen.

Zusätzlicher konkreter Fehler: Der Fehlerzweig von `configureArticleImage` prüft nur den Request-Schlüssel, nicht Cancellation oder eine eindeutige Consumer-Generation. Ein abgebrochener alter Consumer für Request A kann daher die Anzeige eines neu gebundenen Consumers desselben Requests A auf den Platzhalter zurücksetzen. Erfolg und Fehler müssen an dieselbe eindeutige Bindung gebunden sein. Unveränderte Requests nicht unnötig abbrechen und neu starten.

### U4 ist weiterhin eine offene eigenständige Aufgabe

`NewsreaderStore` enthält weiterhin die bisherige Queue. Die Präsentationsgeneration wird beim Drain aufgenommen, nicht beim ursprünglichen Enqueue. Kleine Gruppen warten auf Idle/Lifecycle, solange die 64er-Grenze nicht erreicht wird. Der vereinbarte Worker mit Herkunft pro Auftrag, begrenzter Wartezeit und geordneter Konkurrenz zu manuellem Unread/Undo ist damit nicht fertiggestellt.

U4 entsprechend dem vorhandenen Vertrag abschließen. Das ist für Zuverlässigkeit und dauerhafte Entkopplung erforderlich. Es wäre jedoch unbegründet, ausschließlich diese Queue für sämtliche sichtbaren Ruckler verantwortlich zu machen oder allein ihren Austausch als vollständige Lösung anzukündigen.

## 7. Gezielt prüfen, bevor die Reparatur als fertig gilt

Die vorhandenen Tests decken Teile der Geometrie und Store-Semantik ab. Sie belegen nicht, dass die produktive Timeline bei Statusänderungen keine vollständige Aufbereitung durchläuft. Beispielsweise beobachtet `testRowReadStateDoesNotInvalidateTheStructuralArticleSnapshot` nur `store.articles`; der produktive Body liest zusätzlich alle Zeilenstatuswerte. Der Snapshot-Policy-Test prüft die Gleichheit von ID-Arrays, nicht den vollständigen Controller-/Bridge-Pfad.

Erforderliche Prüfungen des reparierten produktiven Pfads:

| Fall | Erwartung |
|---|---|
| Ein Read-/Starred-Ereignis bei großer geladener Liste | Arbeit für geänderte IDs und gebundene Zellen; kein vollständiges Item-Mapping, Dictionary-Neuaufbau oder struktureller Snapshot. |
| Ein Feed-Icon wird verfügbar | Aktualisierung der passenden gebundenen Zellen; kein Durchlauf aller Artikel. |
| Erneutes Vermessen derselben Inhalts-/Layoutrevision | Cachetreffer ohne erneute Solver-Berechnung. |
| Status oder Bildpixel ändern sich | Gleiche Zellhöhe und gleicher Scrollanker; kein neuer Hierarchie-/Constraint-Aufbau. |
| Vorbereitete Zelle erhält zwischenzeitlich neuen Status | Richtiger Zustand beim Anzeigen, ohne schwere Arbeit in `willDisplay`. |
| Schneller Vorwärtsscroll mit direktem Rückwärtswechsel | Korrekte Read-Semantik ohne Listenumbau und ohne angewachsenen Geometrieverlauf. |
| Rotation/Dynamic Type | Korrekte neue Höhen, konsistente Sensor-Neubasierung, stabiler sichtbarer Artikelanker. |
| Abgebrochener Bildconsumer A, neuer Consumer desselben A | Alte Completion kann weder neues Bild noch Platzhalterzustand überschreiben. |
| Blockierter Writer, danach Unread/Undo/Scopewechsel | Ältere automatische Reads überschreiben keine neuere Absicht; Herkunft und Feedback bleiben korrekt. |

Zähler/Spies sollen tatsächliche Übergabe-, Konfigurations-, Mess- und Writer-Pfade beobachten. Ein isolierter Test einer nachgebauten Array-Funktion reicht dafür nicht.

Nach der Reparatur folgt ein kurzer Release-Abnahmelauf auf demselben iPhone: bildreicher Feed, kalter und warmer Bildcache, schneller sowie langsamer Scroll, unmittelbarer Richtungswechsel, Scrollover eingeschaltet. Hitches/Time Profiler und die relevanten Konfigurations-/Update-Aufrufe gemeinsam ansehen. Für einen 60-Hz-Lauf steht dem gesamten Frame ungefähr 16,7 ms zur Verfügung; dies ist kein Budget, das eine einzelne Zelle ausschöpfen darf.

Diese Geräteabnahme überprüft die fertig umgesetzte Lösung. Sie ist keine vorgeschaltete Aufwandstudie und eröffnet die bereits getroffene UIKit-Entscheidung nicht erneut.

## 8. Dokumentationsstand und Umfang dieser Prüfung

`docs/IOS_UIKIT_TIMELINE_IMPLEMENTATION.md` beschreibt U3 noch als ausstehend und behauptet für die U2-Baseline einen fehlenden produktiven Scrollover-Sensor. Auf dem geprüften main ist der neue Tracker dagegen bereits angeschlossen; auch Search verwendet inzwischen die gemeinsame UIKit-Timeline. Status und Quellenkarte müssen mit dem tatsächlichen Stand abgeglichen werden, damit nachfolgende Implementierungen weder fertige Teile erneut bauen noch offene Anforderungen übersehen.

Abgeschlossen wurden die Videoanalyse, der Vergleich aufeinanderfolgender Bilder, die Kontrolle eines Ausschnitts in Originalauflösung und die statische Prüfung des aktuellen Timeline-, Bridge-, Geometrie-, Bild-, Store- und relevanten Testcodes. Diese Umgebung hat kein Apple SDK und keinen Zugriff auf das Gerät. Ein nativer Build, XCTest-Lauf oder Instruments-Profil dieser App wurde hier nicht ausgeführt.

Empfohlener nächster Implementierungsschritt ist die gemeinsame Reparatur von Zell-Layout, Größenwiederverwendung und gezielten UIKit-Updates, gefolgt von der daran angepassten Geometrieerfassung. Der bestehende Rust-/UniFFI-Vertrag und die bereits beschlossene native UIKit-Timeline bleiben die Grundlage.
