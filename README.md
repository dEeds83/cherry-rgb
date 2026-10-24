# Cherry RGB für macOS

Menüleisten-App + CLI zur RGB-Steuerung der **Cherry G80-3000N RGB** (TKL, USB `046a:00dd`)
und verwandter Cherry-Boards mit dem „neuen“ Protokoll (G80-3000N FL, MX 10.0N, MX 3.0S …).

Kein Kernel-Treiber nötig: die Beleuchtung läuft über HID-Output-Reports an die
Vendor-Collection (Usage Page `0xFF1C`) aus dem Userspace (IOKit).

## Funktionen

- Statische Farbe + Helligkeit (5 Stufen)
- Eingebaute Hardware-Effekte (Wave, Spectrum, Breathing, Rolling, Curve, Scan, Radiation, Ripples, …) mit Tempo/Farbe/Regenbogen
- Per-Key-Editor mit ISO-DE-TKL-Layout (Klick = färben, ⇧-Klick = Auswahl)
- Einstellungen werden gespeichert und beim Anstecken / nach Login automatisch neu gesetzt
- Autostart beim Login (`SMAppService`)

## Download

Fertige App unter [Releases](https://github.com/dEeds83/cherry-rgb/releases): `Cherry-RGB-<version>.zip`
entpacken, nach `~/Applications` ziehen. Die App ist nicht notarisiert, daher einmalig:

```bash
xattr -dr com.apple.quarantine ~/Applications/"Cherry RGB.app"
```

## Bauen & installieren

Benötigt nur die Xcode Command Line Tools (Swift 5.9+), macOS 13+.

```bash
scripts/bundle.sh --install
```

Erzeugt `build/Cherry RGB.app`, kopiert sie nach `~/Applications` und startet sie.
Zusätzlich liegt das CLI unter `build/cherryrgb`.

### Berechtigung „Eingabeüberwachung“

Die Steuer-Collection hängt am Tastatur-Interface, deshalb verlangt macOS beim Öffnen
die Berechtigung **Datenschutz & Sicherheit → Eingabeüberwachung**. Beim ersten Start
erscheint der Dialog; „Cherry RGB“ dort aktivieren. Die App erkennt die Freigabe
automatisch (kein Neustart nötig).

Die App ist nur ad-hoc signiert. macOS bindet die Freigabe an den Code-Hash →
**nach jedem Rebuild** den Eintrag in der Liste entfernen und neu aktivieren.

## CLI

```bash
build/cherryrgb color ff0000 full
build/cherryrgb effect wave slow full rainbow
build/cherryrgb effect breathing medium high 00aaff
build/cherryrgb key 84 ff0000 0 00ff00      # F12 rot, Esc grün
build/cherryrgb off
build/cherryrgb modes
```

Das CLI braucht die Eingabeüberwachung für das aufrufende Terminal.

## Tests

```bash
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift test -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F
```

(Mit vollem Xcode reicht `swift test`.)

## Protokoll

64-Byte-Output-Report, Report-ID `0x04`:

| Byte | Inhalt |
|------|--------|
| 0 | `0x04` |
| 1–2 | Checksumme (u16 LE) = Payload-Typ + Summe aller Payload-Bytes |
| 3 | Payload-Typ (`01` Start, `02` Ende, `06` Animation, `0B` Per-Key-LEDs) |
| 4… | Payload, mit Nullen auf 64 Byte aufgefüllt |

Per-Key: 126 LED-Slots × RGB, in 56-Byte-Chunks; Index = Spalte × 6 + Zeile
(Zeile 0 = F-Reihe). Details in `Sources/CherryRGBKit/Protocol.swift`.

Protokoll reverse-engineered von [cherryrgb-rs](https://github.com/skraus-dev/cherryrgb-rs)
(MIT, Sebastian Kraus).

## Bekannte Lücken

- LED-Index der **Pause**-Taste (102) ist geschätzt – Hover im Editor zeigt den Index.
- Nur ISO-DE-TKL-Layout im Editor; andere Boards funktionieren für Farbe/Effekte trotzdem.
