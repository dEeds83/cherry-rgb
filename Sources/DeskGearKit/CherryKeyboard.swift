import Foundation
import IOKit.hid

/// Desk Gear keyboards (G80-3000N, MX 10.0N, ...): vendor control collection
/// on usage page 0xFF1C.
public final class CherryKeyboard: Sendable {
    public static let vendorID = 0x046A
    static let usagePage = 0xFF1C

    public let connection = HIDConnection(name: "Cherry", matching: [
        kIOHIDVendorIDKey: CherryKeyboard.vendorID,
        kIOHIDDeviceUsagePageKey: CherryKeyboard.usagePage,
    ])

    public init() {}

    public var isConnected: Bool { connection.isConnected }

    /// Sends the packets in order. Not every firmware answers every packet,
    /// so a missing answer just paces the next one.
    public func send(_ payloads: [Payload]) async throws {
        _ = try await connection.exchange(payloads.map(Packet.encode), reportID: Packet.reportID)
    }

    /// Blocking variant for the CLI.
    public func sendBlocking(_ payloads: [Payload]) throws {
        _ = try connection.exchangeBlocking(payloads.map(Packet.encode), reportID: Packet.reportID)
    }
}
