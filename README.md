# Desk Gear für macOS

Menüleisten-App + CLI für Tastatur und Maus, ohne Hersteller-Software:

- **Cherry G80-3000N RGB** (TKL, USB `046a:00dd`) und verwandte Cherry-Boards mit dem
  „neuen“ Protokoll (G80-3000N FL, MX 10.0N, MX 3.0S …): RGB-Beleuchtung
- **ASUS ROG Chakram** (USB `0b05:18e5` / `0b05:18e3`): DPI, Abtastrate, Tastenbelegung,
  Beleuchtung, Profile – wie in Armoury Crate

Kein Kernel-Treiber nötig: alles läuft über HID-Reports an die Vendor-Collections
der Geräte (Cherry: Usage Page `0xFF1C`, ASUS: `0xFF01`) aus dem Userspace (IOKit).

## Funktionen

### Tastatur (Cherry)

- Statische Farbe + Helligkeit (5 Stufen)
- Eingebaute Hardware-Effekte (Wave, Spectrum, Breathing, Rolling, Curve, Scan, Radiation, Ripples, …) mit Tempo/Farbe/Regenbogen
- Per-Key-Editor mit ISO-DE-TKL-Layout (Klick = färben, ⇧-Klick = Auswahl)
- Einstellungen werden gespeichert und beim Anstecken / nach Login automatisch neu gesetzt

### Maus (ASUS ROG Chakram)

- 3 Profile, in der Maus gespeichert, umschaltbar aus der Menüleiste
- 4 DPI-Stufen pro Profil (100–16000 in 100er-Schritten)
- Abtastrate 125/250/500/1000 Hz, Tastenreaktion 4–32 ms, Winkelkorrektur
- Tastenbelegung der 8 Tasten: Maus-Funktionen, DPI-Wechsel, Tastatur-Tasten, deaktivieren
- Beleuchtung je Zone (Logo, Scrollrad, Unterseite): Statisch, Breathing, Spectrum, Wave,
  Reaktiv, Comet, Akkustand – mit Farbe, Helligkeit, Tempo
- Akkustand (experimentell, siehe unten)

Änderungen werden erst mit **„In Maus speichern“** geschrieben und landen im aktiven Profil.
Funktioniert auch über den 2,4-GHz-Dongle; schläft die Maus, kurz bewegen.

### Allgemein

- Autostart beim Login (`SMAppService`)

## Download

Fertige App unter [Releases](https://github.com/dEeds83/desk-gear/releases): `Desk-Gear-<version>.zip`
entpacken, nach `~/Applications` ziehen. Die App ist nicht notarisiert, daher einmalig:

```bash
xattr -dr com.apple.quarantine ~/Applications/"Desk Gear.app"
```

Nur Apple Silicon (arm64), macOS 13+.

## Bauen & installieren

Benötigt nur die Xcode Command Line Tools (Swift 5.9+).

```bash
scripts/bundle.sh --install
```

Erzeugt `build/Desk Gear.app`, kopiert sie nach `~/Applications` und startet sie.
Zusätzlich liegt das CLI unter `build/deskgear`.

### Berechtigung „Eingabeüberwachung“ (nur Tastatur)

Die Cherry-Steuer-Collection hängt am Tastatur-Interface, deshalb verlangt macOS beim
Öffnen die Berechtigung **Datenschutz & Sicherheit → Eingabeüberwachung**. Beim ersten
Start erscheint der Dialog; „Desk Gear“ dort aktivieren. Die App erkennt die Freigabe
automatisch. Die ASUS-Maus braucht keine Berechtigung.

Die App ist nur ad-hoc signiert. macOS bindet die Freigabe an den Code-Hash →
**nach jedem Rebuild** den Eintrag in der Liste entfernen und neu aktivieren.

## CLI

```bash
# Tastatur
build/deskgear color ff0000 full
build/deskgear effect wave slow full rainbow
build/deskgear effect breathing medium high 00aaff
build/deskgear key 84 ff0000 0 00ff00      # F12 rot, Esc grün
build/deskgear off

# Maus
build/deskgear mouse info                  # aktives Profil auslesen
build/deskgear mouse profile 2             # Profil wechseln
build/deskgear mouse dpi 4 3200 --save     # DPI-Stufe 4 setzen und speichern
build/deskgear mouse led 0 ff0000 4        # alle Zonen statisch rot (ohne --save nur temporär)
build/deskgear mouse probe                 # lesende Befehle roh ausgeben (Diagnose)
build/deskgear mouse listen 30             # unaufgeforderte Meldungen mitschreiben
```

Für die Tastatur-Befehle braucht das aufrufende Terminal die Eingabeüberwachung.

## Tests

```bash
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift test -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F
```

(Mit vollem Xcode reicht `swift test`.) Die ASUS-Tests nutzen echte Antworten einer Chakram.

## Protokolle

### Cherry

64-Byte-Output-Report, Report-ID `0x04`:

| Byte | Inhalt |
|------|--------|
| 0 | `0x04` |
| 1–2 | Checksumme (u16 LE) = Payload-Typ + Summe aller Payload-Bytes |
| 3 | Payload-Typ (`01` Start, `02` Ende, `06` Animation, `0B` Per-Key-LEDs) |
| 4… | Payload, mit Nullen auf 64 Byte aufgefüllt |

Per-Key: 126 LED-Slots × RGB, in 56-Byte-Chunks; Index = Spalte × 6 + Zeile
(Zeile 0 = F-Reihe). Details in `Sources/DeskGearKit/Protocol.swift`.

### ASUS

Unnummerierte 64-Byte-Reports, Byte 0–1 = Befehl (u16 LE), Antwort im selben Format;
`ff aa` = Maus schläft / nicht bereit.

| Befehl | Bytes | Bedeutung |
|--------|-------|-----------|
| Profil lesen | `12 00` | Profil (Byte 10), aktive DPI-Stufe (11), Firmware (13–15) |
| LEDs lesen | `12 03` | je Zone 5 Byte ab Byte 4: Modus, Helligkeit, R, G, B |
| Einstellungen | `12 04` | 4 × DPI (u16, `(dpi/2 − 50)/50`), Rate, Entprellung, Winkelkorrektur |
| Tasten lesen | `12 05` | je Taste 2 Byte ab Byte 4: Aktion, Typ |
| Energie (experimentell) | `12 07` | Byte 4 Ladung (0–4, stieg beim Laden), 5 Sleep?, 6 Warnschwelle? |
| Profil setzen | `50 02 <n>` | |
| Speichern | `50 03` | |
| Taste setzen | `51 21` | Byte 4 Quelle, 6 Ziel, 7 Typ (0 Taste, 1 Maus) |
| LED setzen | `51 28 <zone>` | Byte 4 Modus, 5 Helligkeit, 6–8 RGB, 11 Tempo |
| Einstellung | `51 31 <feld>` | Feld 0–3 DPI-Stufen, 4 Rate, 5 Entprellung, 6 Winkelkorrektur |

Details in `Sources/DeskGearKit/AsusProtocol.swift`.

### Quellen

- [cherryrgb-rs](https://github.com/skraus-dev/cherryrgb-rs) (MIT, Sebastian Kraus) – Cherry-Protokoll
- [libratbag](https://github.com/libratbag/libratbag) ASUS-Treiber (MIT, Kyoken) – ASUS-Befehle
- [OpenRGB](https://gitlab.com/CalcProgrammer1/OpenRGB) – ASUS-LED-Effektbytes (nur als Referenz)

## Bekannte Lücken

- **Akkustand der Chakram:** kein öffentlich dokumentierter Befehl. In `12 07` stieg
  Byte 4 nach ca. 1 h am Ladekabel von 2 auf 3 – das wird als Ladung in Stufen à 25 %
  gedeutet. Nur eine Beobachtung, daher weiter „experimentell“ (grob, kein Prozentwert).
- **Chakram-Joystick, Lift-off-Distanz, Energiesparzeit, Makros:** nicht unterstützt
  (Protokoll unbekannt, bräuchte USB-Mitschnitt von Armoury Crate).
- Tastenbelegung ist implementiert, aber nur Lesen wurde an echter Hardware geprüft.
- LED-Index der **Pause**-Taste (102) ist geschätzt – Hover im Editor zeigt den Index.
- Nur ISO-DE-TKL-Layout im Tastatur-Editor.
