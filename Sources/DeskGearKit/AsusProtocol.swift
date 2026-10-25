import Foundation

// ASUS ROG mouse protocol (Chakram and relatives).
// Based on libratbag's ASUS driver (MIT, Kyoken) and OpenRGB's Aura mouse
// controller for the LED effect bytes.
//
// Every request and every answer is an unnumbered 64 byte report:
//   byte 0..1  command, u16 little endian (e.g. 0x0412 -> 12 04)
//   byte 2..   parameters
// An answer starting with ff aa means "invalid state, sleeping or disconnected".

public enum AsusCommand: UInt16, Sendable {
    case getProfile = 0x0012
    case getLEDs = 0x0312
    case getSettings = 0x0412
    case getButtons = 0x0512
    case getPower = 0x0712
    case setProfile = 0x0250
    case save = 0x0350
    case setButton = 0x2151
    case setLED = 0x2851
    case setSetting = 0x3151
}

public enum AsusPacket {
    public static let size = 64

    public static func request(_ cmd: AsusCommand, _ params: [UInt8: UInt8] = [:]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: size)
        out[0] = UInt8(cmd.rawValue & 0xFF)
        out[1] = UInt8(cmd.rawValue >> 8)
        for (i, v) in params { out[Int(i)] = v }
        return out
    }

    public static func isError(_ response: [UInt8]) -> Bool {
        response.count >= 2 && response[0] == 0xFF && response[1] == 0xAA
    }
}

// MARK: - Model

public enum PollingRate: Int, CaseIterable, Codable, Identifiable, Sendable {
    case hz125 = 0, hz250, hz500, hz1000
    public var id: Int { rawValue }
    public var hz: Int { [125, 250, 500, 1000][rawValue] }
}

/// Button response / debounce, 4…32 ms in 4 ms steps.
public enum Debounce: Int, CaseIterable, Codable, Identifiable, Sendable {
    case ms4 = 0, ms8, ms12, ms16, ms20, ms24, ms28, ms32
    public var id: Int { rawValue }
    public var ms: Int { (rawValue + 1) * 4 }
}

public enum MouseLEDMode: UInt8, CaseIterable, Codable, Identifiable, Sendable {
    case staticColor = 0, breathing, spectrum, wave, reactive, comet, battery
    public var id: UInt8 { rawValue }
    public var displayName: String {
        ["Statisch", "Breathing", "Spectrum", "Wave", "Reaktiv", "Comet", "Akkustand"][Int(rawValue)]
    }
    public var supportsColor: Bool { [.staticColor, .breathing, .reactive, .comet].contains(self) }
    public var supportsSpeed: Bool { [.breathing, .spectrum, .wave, .comet].contains(self) }
}

public struct MouseLED: Codable, Equatable, Sendable {
    public var mode: MouseLEDMode
    /// 0…4
    public var brightness: UInt8
    public var color: RGB
    /// 1 (fast) … 15 (slow), only used by animated modes
    public var speed: UInt8 = 8

    public init(mode: MouseLEDMode, brightness: UInt8, color: RGB, speed: UInt8 = 8) {
        self.mode = mode; self.brightness = brightness; self.color = color; self.speed = speed
    }
}

/// What a button does. ASUS codes: 0xF0… mouse functions, otherwise a HID keyboard usage.
public enum ButtonAction: Hashable, Codable, Sendable {
    case mouse(UInt8)
    case key(UInt8)
    case disabled
    case unknown(code: UInt8, type: UInt8)

    static let typeKey: UInt8 = 0
    static let typeButton: UInt8 = 1

    public init(code: UInt8, type: UInt8) {
        switch (code, type) {
        case (0xFF, _): self = .disabled
        case (_, Self.typeButton) where AsusCodes.mouseActions.keys.contains(code): self = .mouse(code)
        case (_, Self.typeKey) where AsusCodes.keys[code] != nil: self = .key(code)
        default: self = .unknown(code: code, type: type)
        }
    }

    public var wire: (code: UInt8, type: UInt8) {
        switch self {
        case .mouse(let c): (c, Self.typeButton)
        case .key(let c): (c, Self.typeKey)
        case .disabled: (0xFF, Self.typeButton)
        case let .unknown(c, t): (c, t)
        }
    }

    public var displayName: String {
        switch self {
        case .mouse(let c): AsusCodes.mouseActions[c] ?? String(format: "0x%02x", c)
        case .key(let c): "Taste " + (AsusCodes.keys[c] ?? String(format: "0x%02x", c))
        case .disabled: "Deaktiviert"
        case let .unknown(c, t): String(format: "Unbekannt (0x%02x/%d)", c, t)
        }
    }
}

public enum AsusCodes {
    public static let mouseActions: [UInt8: String] = [
        0xF0: "Linksklick", 0xF1: "Rechtsklick", 0xF2: "Mittelklick",
        0xE4: "Zurück", 0xE5: "Vorwärts",
        0xE6: "DPI wechseln", 0xE7: "DPI-Ziel (Sniper)",
        0xE8: "Scroll hoch", 0xE9: "Scroll runter",
    ]

    /// Keyboard actions use HID usage IDs (page 0x07).
    public static let keys: [UInt8: String] = {
        var k: [UInt8: String] = [:]
        for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() { k[UInt8(0x04 + i)] = String(c) }
        for (i, c) in "1234567890".enumerated() { k[UInt8(0x1E + i)] = String(c) }
        for i in 0..<12 { k[UInt8(0x3A + i)] = "F\(i + 1)" }
        k[0x28] = "Enter"; k[0x29] = "Esc"; k[0x2A] = "Backspace"; k[0x2B] = "Tab"; k[0x2C] = "Leertaste"
        k[0x4A] = "Pos1"; k[0x4B] = "Bild↑"; k[0x4C] = "Entf"; k[0x4D] = "Ende"; k[0x4E] = "Bild↓"
        k[0x4F] = "→"; k[0x50] = "←"; k[0x51] = "↓"; k[0x52] = "↑"
        return k
    }()
}

/// Physical button slots in the order the mouse reports its bindings.
public struct MouseButtonSlot: Identifiable, Hashable, Sendable {
    public let index: Int
    /// ASUS code that identifies the physical button when rebinding
    public let source: UInt8
    public let name: String
    public var id: Int { index }
}

public struct MouseState: Equatable, Sendable {
    public var profile: Int = 0
    public var activeDPIStage: Int = 0
    public var firmware: String = ""
    public var dpi: [Int] = [400, 800, 1600, 3200]
    public var pollingRate: PollingRate = .hz1000
    public var debounce: Debounce = .ms12
    public var angleSnapping = false
    public var buttons: [ButtonAction] = []
    public var leds: [MouseLED] = []
    /// Answer bytes 4…6 of `12 07` (charge, sleep, alert level – experimental).
    public var power: PowerInfo?

    public init() {}
}

/// Experimental answer of `12 07`. Byte 4 rose from 2 to 3 while charging
/// (Chakram, firmware 13.11.33), so it is taken as the charge level; bytes 5
/// and 6 stayed constant and are assumed to be sleep timeout and alert level.
public struct PowerInfo: Equatable, Sendable {
    public let chargeRaw: UInt8
    public let sleepRaw: UInt8
    public let alertRaw: UInt8

    public init(_ r: [UInt8]) {
        chargeRaw = r.count > 4 ? r[4] : 0
        sleepRaw = r.count > 5 ? r[5] : 0
        alertRaw = r.count > 6 ? r[6] : 0
    }

    /// Assuming charge is reported in 25 % steps (0…4).
    public var chargePercent: Int? { chargeRaw <= 4 ? Int(chargeRaw) * 25 : nil }
}

// MARK: - Device description

public struct AsusMouseModel: Sendable {
    public let name: String
    public let productIDs: [Int]
    public let profiles: Int
    public let dpiStages: Int
    public let dpiRange: ClosedRange<Int>
    public let dpiStep: Int
    /// DPI on the wire is half the real value
    public let doubleDPI: Bool
    /// Profile id sits at result offset 7 instead of 8
    public let strixProfile: Bool
    public let buttons: [MouseButtonSlot]
    public let ledZones: [String]

    public static let chakram = AsusMouseModel(
        name: "ROG Chakram",
        productIDs: [0x18E5, 0x18E3],
        profiles: 3,
        dpiStages: 4,
        dpiRange: 100...16000,
        dpiStep: 100,
        doubleDPI: true,
        // libratbag sets STRIX_PROFILE, but firmware 13.11.33 behind the dongle
        // reports the profile at offset 10 (verified by switching profiles).
        strixProfile: false,
        buttons: [
            MouseButtonSlot(index: 0, source: 0xF0, name: "Linke Taste"),
            MouseButtonSlot(index: 1, source: 0xF1, name: "Rechte Taste"),
            MouseButtonSlot(index: 2, source: 0xF2, name: "Mittlere Taste"),
            MouseButtonSlot(index: 3, source: 0xE4, name: "Seitentaste hinten"),
            MouseButtonSlot(index: 4, source: 0xE5, name: "Seitentaste vorne"),
            MouseButtonSlot(index: 5, source: 0xE6, name: "DPI-Taste"),
            MouseButtonSlot(index: 6, source: 0xE8, name: "Scroll hoch"),
            MouseButtonSlot(index: 7, source: 0xE9, name: "Scroll runter"),
        ],
        ledZones: ["Logo", "Scrollrad", "Unterseite"]
    )

    public static let all = [chakram]

    public static func forProductID(_ pid: Int) -> AsusMouseModel? {
        all.first { $0.productIDs.contains(pid) }
    }
}

// MARK: - Encoding / decoding

public extension AsusMouseModel {
    func setDPI(stage: Int, dpi: Int) -> [UInt8] {
        let clamped = min(max(dpi, dpiRange.lowerBound), dpiRange.upperBound)
        let raw = ((doubleDPI ? clamped / 2 : clamped) - 50) / 50
        return AsusPacket.request(.setSetting, [2: UInt8(stage), 4: UInt8(raw & 0xFF), 5: UInt8(raw >> 8)])
    }

    // Settings after the DPI stages are addressed as field dpiStages + n.
    func setPollingRate(_ r: PollingRate) -> [UInt8] {
        AsusPacket.request(.setSetting, [2: UInt8(dpiStages), 4: UInt8(r.rawValue)])
    }

    func setDebounce(_ d: Debounce) -> [UInt8] {
        AsusPacket.request(.setSetting, [2: UInt8(dpiStages + 1), 4: UInt8(d.rawValue)])
    }

    func setAngleSnapping(_ on: Bool) -> [UInt8] {
        AsusPacket.request(.setSetting, [2: UInt8(dpiStages + 2), 4: on ? 1 : 0])
    }

    func setButton(_ slot: MouseButtonSlot, _ action: ButtonAction) -> [UInt8] {
        let w = action.wire
        return AsusPacket.request(.setButton, [4: slot.source, 5: ButtonAction.typeButton, 6: w.code, 7: w.type])
    }

    /// LED layout from OpenRGB: zone, 0, mode, brightness, r, g, b, direction, random, speed.
    func setLED(zone: Int, _ led: MouseLED) -> [UInt8] {
        AsusPacket.request(.setLED, [2: UInt8(zone), 4: led.mode.rawValue, 5: min(led.brightness, 4),
                                     6: led.color.r, 7: led.color.g, 8: led.color.b,
                                     9: 0, 10: 0, 11: min(max(led.speed, 1), 15)])
    }

    func setProfile(_ index: Int) -> [UInt8] {
        AsusPacket.request(.setProfile, [2: UInt8(index)])
    }

    // Responses carry their payload from byte 2 on ("results" in libratbag).

    func parseProfile(_ r: [UInt8], into s: inout MouseState) {
        guard r.count >= 16 else { return }
        s.profile = min(Int(r[strixProfile ? 9 : 10]), profiles - 1)
        s.activeDPIStage = r[11] > 0 ? Int(r[11]) - 1 : 0
        s.firmware = String(format: "%X.%02X.%02X", r[15], r[14], r[13])
    }

    func parseSettings(_ r: [UInt8], into s: inout MouseState) {
        guard r.count >= 18 else { return }
        s.dpi = (0..<dpiStages).map { i in
            let raw = Int(r[4 + i * 2]) | Int(r[5 + i * 2]) << 8
            return (raw * 50 + 50) * (doubleDPI ? 2 : 1)
        }
        let rateIndex = 4 + dpiStages * 2
        s.pollingRate = PollingRate(rawValue: Int(r[rateIndex])) ?? .hz1000
        s.debounce = Debounce(rawValue: Int(r[rateIndex + 2])) ?? .ms12
        s.angleSnapping = r[rateIndex + 4] != 0
    }

    func parseButtons(_ r: [UInt8], into s: inout MouseState) {
        s.buttons = buttons.map { slot in
            let off = 4 + slot.index * 2
            guard off + 1 < r.count else { return .unknown(code: 0, type: 0) }
            return ButtonAction(code: r[off], type: r[off + 1])
        }
    }

    func parseLEDs(_ r: [UInt8], into s: inout MouseState) {
        s.leds = ledZones.indices.map { i in
            let off = 4 + i * 5
            guard off + 4 < r.count else { return MouseLED(mode: .staticColor, brightness: 4, color: .black) }
            return MouseLED(mode: MouseLEDMode(rawValue: r[off]) ?? .staticColor, brightness: min(r[off + 1], 4),
                            color: RGB(r[off + 2], r[off + 3], r[off + 4]))
        }
    }
}
