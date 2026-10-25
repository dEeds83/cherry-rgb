import Foundation
import IOKit.hid

/// ASUS ROG mice: vendor control collection on usage page 0xFF01.
public final class AsusMouse: Sendable {
    public static let vendorID = 0x0B05
    static let usagePage = 0xFF01

    public let connection = HIDConnection(name: "AsusMouse", matching: [
        kIOHIDVendorIDKey: AsusMouse.vendorID,
        kIOHIDDeviceUsagePageKey: AsusMouse.usagePage,
    ])

    public init() {}

    public var isConnected: Bool { connection.isConnected }

    /// One request, one answer. Throws on timeout or when the mouse reports an error.
    public func query(_ request: [UInt8]) async throws -> [UInt8] {
        let answers = try await connection.exchange([request], reportID: 0, timeout: .milliseconds(500))
        return try Self.check(answers)
    }

    public func queryBlocking(_ request: [UInt8]) throws -> [UInt8] {
        try Self.check(connection.exchangeBlocking([request], reportID: 0, timeout: .milliseconds(500)))
    }

    private static func check(_ answers: [[UInt8]]) throws -> [UInt8] {
        guard let r = answers.first else { throw HIDError.timeout }
        if AsusPacket.isError(r) { throw HIDError.deviceBusy }
        return r
    }

    /// Reads everything of the active profile.
    public func readState(_ model: AsusMouseModel) async throws -> MouseState {
        var s = MouseState()
        model.parseProfile(try await query(AsusPacket.request(.getProfile)), into: &s)
        model.parseSettings(try await query(AsusPacket.request(.getSettings)), into: &s)
        model.parseButtons(try await query(AsusPacket.request(.getButtons)), into: &s)
        model.parseLEDs(try await query(AsusPacket.request(.getLEDs)), into: &s)
        s.power = try? await readPower()
        return s
    }

    public func readPower() async throws -> PowerInfo {
        PowerInfo(try await query(AsusPacket.request(.getPower)))
    }

    /// Writes all fields that differ from `old`, then stores them in the active profile.
    public func write(_ new: MouseState, over old: MouseState, model: AsusMouseModel) async throws {
        var requests: [[UInt8]] = []
        for (i, dpi) in new.dpi.enumerated() where i >= old.dpi.count || old.dpi[i] != dpi {
            requests.append(model.setDPI(stage: i, dpi: dpi))
        }
        if new.pollingRate != old.pollingRate { requests.append(model.setPollingRate(new.pollingRate)) }
        if new.debounce != old.debounce { requests.append(model.setDebounce(new.debounce)) }
        if new.angleSnapping != old.angleSnapping { requests.append(model.setAngleSnapping(new.angleSnapping)) }
        for slot in model.buttons where slot.index < new.buttons.count {
            let action = new.buttons[slot.index]
            if slot.index >= old.buttons.count || old.buttons[slot.index] != action {
                requests.append(model.setButton(slot, action))
            }
        }
        for (zone, led) in new.leds.enumerated() where zone >= old.leds.count || old.leds[zone] != led {
            requests.append(model.setLED(zone: zone, led))
        }
        guard !requests.isEmpty else { return }
        for r in requests { _ = try await query(r) }
        _ = try await query(AsusPacket.request(.save))
    }

    public func switchProfile(_ index: Int, model: AsusMouseModel) async throws {
        _ = try await query(model.setProfile(index))
    }
}
