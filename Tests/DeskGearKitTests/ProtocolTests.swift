import Testing
@testable import DeskGearKit

private func hex(_ s: String) -> [UInt8] {
    s.split(separator: " ").map { UInt8($0, radix: 16)! }
}

// Expected bytes are USB captures from the cherryrgb-rs test suite.
@Suite struct ProtocolTests {
    @Test func transactionPackets() {
        #expect(Array(Packet.encode(.transactionStart).prefix(4)) == hex("04 01 00 01"))
        #expect(Array(Packet.encode(.transactionEnd).prefix(4)) == hex("04 02 00 02"))
    }

    @Test func staticRedCapture() {
        let p = Payload.setAnimation(unknown: [0x09, 0x00, 0x00, 0x55, 0x00], mode: .staticColor,
                                     brightness: .high, speed: .veryFast, rainbow: false, color: RGB(0xE0, 0x03, 0x00))
        #expect(Array(Packet.encode(p).prefix(17)) == hex("04 4D 01 06 09 00 00 55 00 03 03 00 00 00 E0 03 00"))
    }

    @Test func secondAnimationPacket() {
        let p = Payload.setAnimation(unknown: [0x01, 0x18, 0x00, 0x55, 0x01], mode: .wave,
                                     brightness: .off, speed: .veryFast, rainbow: false, color: RGB(0, 0, 0x42))
        #expect(Array(Packet.encode(p).prefix(17)) == hex("04 B7 00 06 01 18 00 55 01 00 00 00 00 00 00 00 42"))
    }

    @Test func packetIsPadded() {
        #expect(Packet.encode(.transactionStart).count == 64)
    }

    @Test func customLEDChunks() throws {
        var colors = KeyColors()
        colors[0] = RGB(0x11, 0x11, 0x11)
        colors[125] = RGB(1, 2, 3)
        let payloads = colors.payloads()
        // 126 * 3 = 378 bytes -> 6 full chunks of 56 + 42
        #expect(payloads.count == 7)
        guard case let .setCustomLED(off0, data0) = payloads[0], case let .setCustomLED(off6, data6) = payloads[6] else {
            Issue.record("wrong payload type"); return
        }
        #expect(off0 == 0)
        #expect(Array(data0.prefix(3)) == [0x11, 0x11, 0x11])
        #expect(off6 == 336)
        #expect(data6.count == 42)
        #expect(Array(data6.suffix(3)) == [1, 2, 3])
        // type, len, offset lo, offset hi, pad
        #expect(Array(Packet.encode(payloads[6])[3...7]) == [0x0B, 42, 0x50, 0x01, 0x00])
    }

    @Test func hexColor() {
        #expect(RGB(hex: "#ff8000") == RGB(255, 128, 0))
        #expect(RGB(hex: "xyz") == nil)
        #expect(RGB(255, 128, 0).hex == "ff8000")
    }
}
