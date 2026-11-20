# Flux iOS Timeline — Messprotokoll Frame-Kopfraum (historisch)

Status: **abgeschlossen, Werkzeug entfernt (18. September 2026).**
Dieses Dokument beschrieb ein Messverfahren, dessen Instrument nicht mehr
existiert. Es bleibt als Aufzeichnung dessen, was gemessen wurde und warum die
Messung die Frage nicht beantwortet hat.

Die Anleitung ist bewusst nicht mehr ausführbar: `IOSUIKitTimelineFrameHeadroomRecorder`
und die zugehörige Developer-Diagnostics-Oberfläche wurden entfernt
(siehe `IOS_TIMELINE_PERFORMANCE_DIAGNOSTIC_CLEANUP.md`).

## Die zentrale Einschränkung — zuerst lesen

Die Zielgröße, um die dieses Protokoll herum gebaut war, ist **kein gültiger
Leistungsmaßstab**.

Das Verfahren zählt pixelgleiche aufeinanderfolgende Frames einer
Bildschirmaufnahme als verworfene Display-Frames. Eine Kontrollmessung an
**Apple Kalender ergab mit derselben Methode rund 13 %**, während Flux bei
etwa 5 % lag. Wiederholte Frames in einer ReplayKit-Aufnahme sind also nicht
gleichbedeutend mit verworfenen Display-Frames, und weder die gemessene Rate
noch das ursprüngliche Ziel von „< 1 %" taugen als Freigabekriterium.

Jede Aussage weiter unten ist vor diesem Hintergrund zu lesen.

## Was gemessen wurde

`IOSUIKitTimelineFrameHeadroomRecorder` erfasste je Display-Frame, wie lange der
Main Thread beschäftigt war, und zählte über Wanduhr-Abstände zwischen
`CADisplayLink`-Callbacks, wie oft er einen Vsync ganz verpasste. Ein
`CFRunLoopObserver` hinter dem Commit-Observer von Core Animation schloss das
Belegungsfenster.

Damit ließ sich der Main-Thread-Anteil beziffern — aber **nur dieser**. Für
Render-Server- und GPU-Zeit war das Verfahren bauartbedingt blind, und genau
dort lag der größere Teil.

## Ergebnisse, die Bestand haben

* **Der Main Thread war durchgehend entlastet.** Über alle gemessenen
  Konfigurationen lagen Mittelwerte bei 2,1–2,9 ms von 16,6 ms Budget, der
  Median bei rund 1,6 ms.
* **Die verpasste-Callback-Rate bewegte sich nicht.** Über etwa ein Dutzend
  Konfigurationen — Scroll-Edge-Effekt in drei Stellungen, Undo-Pille in zwei,
  Kapselmaterial in vier, Kompakt gegen Visuell — blieb sie zwischen 0,49 % und
  1,28 %, ohne dass ein Arm die Streuung erklärte.
* **Die Kennzahl sagt die Wahrnehmung nicht vorher.** Der Kompakt-Modus maß
  schlechter als der visuelle und fühlte sich besser an. Das war der erste
  klare Hinweis, dass das Instrument nicht das Symptom misst.
* **Der Scroll-Edge-Effekt kostet echte Main-Thread-Zeit.** Sauber gepaart in
  einer Sitzung gemessen: System 4,00 %, Hard 1,14 %, Aus 1,43 % der Frames über
  10 ms. Auf die verpassten Callbacks wirkte sich auch das nicht aus.

## Methodische Lehren

* **Vergleiche gehören in eine Sitzung.** Zwischen Sitzungen ist die Streuung
  größer als jeder Effekt, den wir gesucht haben. Eine 5,5-σ-Aussage aus einem
  sitzungsübergreifenden Vergleich musste zurückgenommen werden, nachdem ein
  Kontrollarm sie widerlegte.
* **Ein Kontrollarm ist Pflicht.** Genau er hat den Fehler oben aufgedeckt.
* **`CADisplayLink.timestamp` folgt dem Display-Zeitplan, nicht der tatsächlichen
  Callback-Zeit.** Eine daraus abgeleitete Skip-Zählung stand dauerhaft auf 0,
  während Wanduhr-Abstände sehr wohl Ausfälle zeigten.

## Wie es ausgegangen ist

Die Untersuchung endete nicht mit einer Leistungskorrektur, sondern mit einer
Gestaltungsentscheidung: dem Darstellungsmodus **Visuell kompakt**. Eine
formatfüllende Bildkante, die sich vertikal bewegt, ist der stärkste
Ruckel-Reiz; bricht man sie auf, fallen dieselben verlorenen Frames nicht mehr
auf. Die Begründung und die Belege stehen in
`IOS_TIMELINE_PERFORMANCE_DIAGNOSTIC_CLEANUP.md`.

Das Analysewerkzeug für Bildschirmaufnahmen (`docs/tools/scroll-frame-analysis.swift`)
existiert weiterhin und ist rotations- und pausenfest. Seine Ausgabe ist nach der
Einschränkung ganz oben zu bewerten: als Vergleichsgröße zwischen zwei Armen
derselben Sitzung, nicht als absolute Kennzahl.
