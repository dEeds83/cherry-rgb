import DeskGearKit
import Foundation

func usage() -> Never {
    print("""
    deskgear – Steuerung für Cherry G80-3000N & ASUS ROG Chakram

    Tastatur:
      deskgear color <hex> [brightness]          statische Farbe, z.B. ff0000 full
      deskgear effect <mode> [speed] [brightness] [hex|rainbow]
      deskgear key <index> <hex> [...]           einzelne Tasten (Rest aus)
      deskgear off
      deskgear modes

    brightness: off low medium high full     speed: very_fast fast medium slow very_slow

    Maus:
      deskgear mouse info                        aktives Profil auslesen
      deskgear mouse probe                       lesende Befehle 12 00…12 1f roh ausgeben
      deskgear mouse profile <1-3>               Profil wechseln
      deskgear mouse dpi <stufe> <dpi> [--save]  DPI einer Stufe setzen (1-4)
      deskgear mouse led <modus 0-6> <hex> [helligkeit 0-4] [--save]
                                                  alle Zonen (0 statisch, 1 breathing, 2 spectrum,
                                                  3 wave, 4 reaktiv, 5 comet, 6 akku)
      deskgear mouse listen [sekunden]           unaufgeforderte Meldungen mitschreiben
    """)
    exit(2)
}

func fail(_ msg: String) -> Never {
    print(msg)
    exit(1)
}

func parse<T: CaseIterable & RawRepresentable>(_ s: String?, _ names: [String], default def: T) -> T where T.RawValue == UInt8 {
    guard let s else { return def }
    guard let i = names.firstIndex(of: s), let v = T(rawValue: UInt8(i)) else {
        print("Ungültiger Wert: \(s)"); exit(2)
    }
    return v
}

func ensureAccess() {
    if !HIDConnection.hasInputMonitoringAccess {
        HIDConnection.requestInputMonitoringAccess()
    }
}

func connect(_ c: HIDConnection) {
    c.log = { print($0) }
    guard c.waitForDevice(timeout: 2) else {
        fail(HIDConnection.hasInputMonitoringAccess ? HIDError.notConnected.description : HIDError.accessDenied.description)
    }
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}

// MARK: - Mouse

func runMouse(_ args: [String]) -> Never {
    let mouse = AsusMouse()
    connect(mouse.connection)
    do {
        switch args.first {
        case "info":
            let model = AsusMouseModel.chakram
            var s = MouseState()
            model.parseProfile(try mouse.queryBlocking(AsusPacket.request(.getProfile)), into: &s)
            model.parseSettings(try mouse.queryBlocking(AsusPacket.request(.getSettings)), into: &s)
            model.parseButtons(try mouse.queryBlocking(AsusPacket.request(.getButtons)), into: &s)
            model.parseLEDs(try mouse.queryBlocking(AsusPacket.request(.getLEDs)), into: &s)
            print("Firmware \(s.firmware), Profil \(s.profile + 1), aktive DPI-Stufe \(s.activeDPIStage + 1)")
            print("DPI \(s.dpi), \(s.pollingRate.hz) Hz, Entprellung \(s.debounce.ms) ms, Winkelkorrektur \(s.angleSnapping ? "an" : "aus")")
            for (slot, action) in zip(model.buttons, s.buttons) { print("  \(slot.name): \(action.displayName)") }
            for (zone, led) in zip(model.ledZones, s.leds) {
                print("  LED \(zone): \(led.mode.displayName), Helligkeit \(led.brightness), #\(led.color.hex)")
            }
        case "probe":
            // Only "get" commands (low byte 0x12); they do not change anything.
            for hi in UInt8(0)...0x1F {
                let req = [0x12, hi] + [UInt8](repeating: 0, count: 62)
                let answers = try mouse.connection.exchangeBlocking([req], reportID: 0, timeout: .milliseconds(300))
                let line = answers.first.map { hex(Array($0.prefix(24))) } ?? "(keine Antwort)"
                print(String(format: "12 %02x -> ", hi) + line)
            }
        case "dpi":
            // deskgear mouse dpi <stage 1-4> <dpi> [--save]
            guard args.count >= 3, let stage = Int(args[1]), let dpi = Int(args[2]),
                  (1...AsusMouseModel.chakram.dpiStages).contains(stage) else { usage() }
            _ = try mouse.queryBlocking(AsusMouseModel.chakram.setDPI(stage: stage - 1, dpi: dpi))
            if args.contains("--save") { _ = try mouse.queryBlocking(AsusPacket.request(.save)) }
            var s = MouseState()
            AsusMouseModel.chakram.parseSettings(try mouse.queryBlocking(AsusPacket.request(.getSettings)), into: &s)
            print("DPI jetzt \(s.dpi)\(args.contains("--save") ? " (gespeichert)" : "")")
        case "led":
            // deskgear mouse led <mode 0-6> <hex> [brightness 0-4] [--save]
            guard args.count >= 3, let m = UInt8(args[1]).flatMap(MouseLEDMode.init(rawValue:)),
                  let c = RGB(hex: args[2]) else { usage() }
            let b = args.count > 3 ? UInt8(args[3]) ?? 4 : 4
            for zone in AsusMouseModel.chakram.ledZones.indices {
                _ = try mouse.queryBlocking(AsusMouseModel.chakram.setLED(zone: zone, MouseLED(mode: m, brightness: b, color: c)))
            }
            if args.contains("--save") { _ = try mouse.queryBlocking(AsusPacket.request(.save)) }
            print("LEDs: \(m.displayName) #\(c.hex) Helligkeit \(b)")
        case "profile":
            guard args.count >= 2, let p = Int(args[1]), (1...AsusMouseModel.chakram.profiles).contains(p) else { usage() }
            _ = try mouse.queryBlocking(AsusMouseModel.chakram.setProfile(p - 1))
            let r = try mouse.queryBlocking(AsusPacket.request(.getProfile))
            var s = MouseState()
            AsusMouseModel.chakram.parseProfile(r, into: &s)
            print("Profil jetzt \(s.profile + 1) (roh: \(hex(Array(r.prefix(12)))))")
        case "listen":
            let seconds = args.count > 1 ? Double(args[1]) ?? 30 : 30
            print("Lausche \(Int(seconds)) s auf Meldungen der Maus …")
            mouse.connection.onInputReport = { r in
                print(Date().formatted(date: .omitted, time: .standard), hex(Array(r.prefix(24))))
            }
            Thread.sleep(forTimeInterval: seconds)
        default:
            usage()
        }
    } catch {
        fail("Fehler: \(error)")
    }
    exit(0)
}

// MARK: - Keyboard

let brightnessNames = ["off", "low", "medium", "high", "full"]
let speedNames = ["very_fast", "fast", "medium", "slow", "very_slow"]
let modeNames: [String: LightingMode] = [
    "wave": .wave, "spectrum": .spectrum, "breathing": .breathing, "static": .staticColor,
    "radar": .radar, "vortex": .vortex, "fire": .fire, "stars": .stars, "rolling": .rolling,
    "rain": .rain, "curve": .curve, "wave_mid": .waveMid, "scan": .scan, "radiation": .radiation,
    "ripples": .ripples, "single_key": .singleKey,
]

var args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { usage() }
args.removeFirst()

ensureAccess()
if cmd == "mouse" { runMouse(args) }

let payloads: [Payload]
switch cmd {
case "modes":
    print(modeNames.keys.sorted().joined(separator: "\n")); exit(0)
case "color":
    guard let c = args.first.flatMap(RGB.init(hex:)) else { usage() }
    payloads = Commands.animation(mode: .staticColor, brightness: parse(args.dropFirst().first, brightnessNames, default: .full),
                                  speed: .medium, color: c, rainbow: false)
case "effect":
    guard let m = args.first.flatMap({ modeNames[$0] }) else { usage() }
    let colorArg = args.count > 3 ? args[3] : nil
    payloads = Commands.animation(mode: m,
                                  brightness: parse(args.count > 2 ? args[2] : nil, brightnessNames, default: .full),
                                  speed: parse(args.count > 1 ? args[1] : nil, speedNames, default: .medium),
                                  color: colorArg.flatMap(RGB.init(hex:)) ?? RGB(255, 255, 255),
                                  rainbow: colorArg == nil || colorArg == "rainbow")
case "key":
    guard args.count >= 2, args.count % 2 == 0 else { usage() }
    var colors = KeyColors()
    for pair in stride(from: 0, to: args.count, by: 2) {
        guard let i = Int(args[pair]), (0..<KeyColors.count).contains(i), let c = RGB(hex: args[pair + 1]) else { usage() }
        colors[i] = c
    }
    payloads = Commands.custom(colors, brightness: .full)
case "off":
    payloads = Commands.animation(mode: .staticColor, brightness: .off, speed: .medium, color: .black, rainbow: false)
default:
    usage()
}

let kb = CherryKeyboard()
connect(kb.connection)
do {
    try kb.sendBlocking(payloads)
    print("OK")
} catch {
    fail("Fehler: \(error)")
}
