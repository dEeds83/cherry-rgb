import CherryRGBKit
import Foundation

func usage() -> Never {
    print("""
    cherryrgb – RGB-Steuerung für Cherry G80-3000N & Co.

      cherryrgb color <hex> [brightness]          statische Farbe, z.B. ff0000 full
      cherryrgb effect <mode> [speed] [brightness] [hex|rainbow]
      cherryrgb key <index> <hex> [...]           einzelne Tasten (Rest aus)
      cherryrgb off
      cherryrgb modes

    brightness: off low medium high full     speed: very_fast fast medium slow very_slow
    """)
    exit(2)
}

func parse<T: CaseIterable & RawRepresentable>(_ s: String?, _ names: [String], default def: T) -> T where T.RawValue == UInt8 {
    guard let s else { return def }
    guard let i = names.firstIndex(of: s), let v = T(rawValue: UInt8(i)) else {
        print("Ungültiger Wert: \(s)"); exit(2)
    }
    return v
}

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

if !CherryKeyboard.hasInputMonitoringAccess {
    CherryKeyboard.requestInputMonitoringAccess()
}

let kb = CherryKeyboard()
kb.log = { print($0) }
guard kb.waitForDevice(timeout: 2) else {
    print(CherryKeyboard.hasInputMonitoringAccess ? CherryError.notConnected.description : CherryError.accessDenied.description)
    exit(1)
}
do {
    try kb.sendBlocking(payloads)
    print("OK")
} catch {
    print("Fehler: \(error)")
    exit(1)
}
