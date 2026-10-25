import Foundation

// Packet format of the "new" Desk Gear protocol (G80-3000N, MX 3.0S, MX 10.0N, ...).
// Reverse engineered by the cherryrgb-rs project (MIT, Sebastian Kraus):
// https://github.com/skraus-dev/cherryrgb-rs
//
//   byte 0      report id, always 0x04
//   byte 1..2   checksum, u16 little endian = payload_type + sum(payload bytes)
//   byte 3      payload type
//   byte 4..    payload, zero padded to 64 bytes

public enum LightingMode: UInt8, CaseIterable, Codable, Identifiable, Sendable {
    case wave = 0x00
    case spectrum = 0x01
    case breathing = 0x02
    case staticColor = 0x03
    case radar = 0x04
    case vortex = 0x05
    case fire = 0x06
    case stars = 0x07
    case custom = 0x08
    case rolling = 0x0A
    case rain = 0x0B
    case curve = 0x0C
    case waveMid = 0x0E
    case scan = 0x0F
    case radiation = 0x12
    case ripples = 0x13
    case singleKey = 0x15

    public var id: UInt8 { rawValue }

    public var displayName: String {
        switch self {
        case .wave: "Wave"
        case .spectrum: "Spectrum"
        case .breathing: "Breathing"
        case .staticColor: "Statisch"
        case .radar: "Radar"
        case .vortex: "Vortex"
        case .fire: "Fire"
        case .stars: "Stars"
        case .custom: "Per-Key"
        case .rolling: "Rolling"
        case .rain: "Rain"
        case .curve: "Curve"
        case .waveMid: "Wave (Mitte)"
        case .scan: "Scan"
        case .radiation: "Radiation"
        case .ripples: "Ripples"
        case .singleKey: "Single Key"
        }
    }

    public var supportsColor: Bool {
        switch self {
        case .wave, .breathing, .staticColor, .curve, .scan, .radiation, .ripples, .singleKey: true
        default: false
        }
    }

    public var supportsSpeed: Bool {
        switch self {
        case .staticColor, .scan, .custom: false
        default: true
        }
    }

    /// Effects selectable in the UI (custom is driven by the per-key editor).
    public static var effects: [LightingMode] { allCases.filter { $0 != .custom && $0 != .staticColor } }
}

public enum Speed: UInt8, CaseIterable, Codable, Identifiable, Sendable {
    case veryFast = 0, fast, medium, slow, verySlow
    public var id: UInt8 { rawValue }
    public var displayName: String {
        ["Sehr schnell", "Schnell", "Mittel", "Langsam", "Sehr langsam"][Int(rawValue)]
    }
}

public enum Brightness: UInt8, CaseIterable, Codable, Identifiable, Sendable {
    case off = 0, low, medium, high, full
    public var id: UInt8 { rawValue }
    public var displayName: String {
        ["Aus", "Niedrig", "Mittel", "Hoch", "Voll"][Int(rawValue)]
    }
}

public struct RGB: Codable, Equatable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r; self.g = g; self.b = b
    }

    public static let black = RGB(0, 0, 0)

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF))
    }

    public var hex: String { String(format: "%02x%02x%02x", r, g, b) }
}

public enum Payload: Equatable, Sendable {
    case transactionStart
    case transactionEnd
    case unknown3(UInt8)
    case unknown5(UInt8)
    case setAnimation(unknown: [UInt8], mode: LightingMode, brightness: Brightness, speed: Speed, rainbow: Bool, color: RGB)
    case setCustomLED(offset: UInt16, data: [UInt8])

    public var type: UInt8 {
        switch self {
        case .transactionStart: 0x01
        case .transactionEnd: 0x02
        case .unknown3: 0x03
        case .unknown5: 0x05
        case .setAnimation: 0x06
        case .setCustomLED: 0x0B
        }
    }

    public var bytes: [UInt8] {
        switch self {
        case .transactionStart, .transactionEnd:
            return []
        case .unknown3(let v), .unknown5(let v):
            return [v]
        case let .setAnimation(unknown, mode, brightness, speed, rainbow, color):
            return unknown + [mode.rawValue, brightness.rawValue, speed.rawValue, 0x00, rainbow ? 1 : 0, color.r, color.g, color.b]
        case let .setCustomLED(offset, data):
            return [UInt8(data.count), UInt8(offset & 0xFF), UInt8(offset >> 8), 0x00] + data
        }
    }
}

public enum Packet {
    public static let reportID: UInt8 = 0x04
    public static let size = 64

    public static func checksum(type: UInt8, payload: [UInt8]) -> UInt16 {
        payload.reduce(UInt16(type)) { $0 &+ UInt16($1) }
    }

    /// Full 64 byte output report including the leading report id.
    public static func encode(_ payload: Payload) -> [UInt8] {
        let body = payload.bytes
        let sum = checksum(type: payload.type, payload: body)
        var out: [UInt8] = [reportID, UInt8(sum & 0xFF), UInt8(sum >> 8), payload.type] + body
        precondition(out.count <= size, "payload too large")
        out += [UInt8](repeating: 0, count: size - out.count)
        return out
    }
}

/// Per-key LED buffer, 126 slots of RGB.
public struct KeyColors: Codable, Equatable, Sendable {
    public static let count = 126
    /// 64 byte packet - 4 byte packet header - 4 byte payload header
    static let chunkSize = 56

    public var leds: [RGB]

    public init(fill: RGB = .black) {
        leds = Array(repeating: fill, count: Self.count)
    }

    public subscript(index: Int) -> RGB {
        get { leds[index] }
        set { leds[index] = newValue }
    }

    public func payloads() -> [Payload] {
        let raw = leds.flatMap { [$0.r, $0.g, $0.b] }
        return stride(from: 0, to: raw.count, by: Self.chunkSize).map { off in
            .setCustomLED(offset: UInt16(off), data: Array(raw[off..<min(off + Self.chunkSize, raw.count)]))
        }
    }
}

public enum Commands {
    /// Packet sequence to switch on a built-in effect.
    public static func animation(mode: LightingMode, brightness: Brightness, speed: Speed, color: RGB, rainbow: Bool) -> [Payload] {
        [
            .transactionStart,
            .setAnimation(unknown: [0x09, 0x00, 0x00, 0x55, 0x00], mode: mode, brightness: brightness, speed: speed, rainbow: rainbow, color: color),
            .setAnimation(unknown: [0x01, 0x18, 0x00, 0x55, 0x01], mode: .wave, brightness: .off, speed: .veryFast, rainbow: false, color: .black),
            .transactionEnd,
        ]
    }

    /// Switch into custom mode and upload all key colors.
    public static func custom(_ colors: KeyColors, brightness: Brightness) -> [Payload] {
        animation(mode: .custom, brightness: brightness, speed: .slow, color: .black, rainbow: false) + colors.payloads()
    }
}
