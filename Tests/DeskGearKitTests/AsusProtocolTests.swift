import Testing
@testable import DeskGearKit

private func bytes(_ s: String) -> [UInt8] {
    let b = s.split(separator: " ").map { UInt8($0, radix: 16)! }
    return b + [UInt8](repeating: 0, count: 64 - b.count)
}

// Responses captured from a ROG Chakram (0b05:18e5, 2.4 GHz dongle, firmware 13.11.33).
@Suite struct AsusProtocolTests {
    let model = AsusMouseModel.chakram

    @Test func requestLayout() {
        #expect(Array(AsusPacket.request(.getSettings).prefix(2)) == [0x12, 0x04])
        #expect(Array(AsusPacket.request(.setLED).prefix(2)) == [0x51, 0x28])
        #expect(AsusPacket.request(.save).count == 64)
    }

    @Test func errorAnswer() {
        #expect(AsusPacket.isError(bytes("ff aa")))
        #expect(!AsusPacket.isError(bytes("12 04")))
    }

    @Test func parseCapturedSettings() {
        var s = MouseState()
        s.dpi = []
        model.parseSettings(bytes("12 04 00 00 03 00 07 00 0f 00 1f 00 03 00 02 00 00 00"), into: &s)
        #expect(s.dpi == [400, 800, 1600, 3200])
        #expect(s.pollingRate == .hz1000)
        #expect(s.debounce == .ms12)
        #expect(s.angleSnapping == false)
    }

    @Test func parseCapturedProfile() {
        var s = MouseState()
        model.parseProfile(bytes("12 00 00 00 32 00 01 00 03 07 00 04 1f 33 11 13"), into: &s)
        #expect(s.profile == 0)
        #expect(s.activeDPIStage == 3)
        #expect(s.firmware == "13.11.33")
        model.parseProfile(bytes("12 00 00 00 32 00 01 00 03 07 01 03 1f 33 11 13"), into: &s)
        #expect(s.profile == 1)
        #expect(s.activeDPIStage == 2)
    }

    @Test func parseCapturedButtons() {
        var s = MouseState()
        model.parseButtons(bytes("12 05 00 00 f0 01 f1 01 f2 01 e4 01 e5 01 e6 01 e8 01 e9 01"), into: &s)
        #expect(s.buttons == [.mouse(0xF0), .mouse(0xF1), .mouse(0xF2), .mouse(0xE4),
                              .mouse(0xE5), .mouse(0xE6), .mouse(0xE8), .mouse(0xE9)])
    }

    @Test func parseCapturedLEDs() {
        var s = MouseState()
        model.parseLEDs(bytes("12 03 00 00 06 01 00 00 00 06 01 00 00 00 06 01 00 00 00"), into: &s)
        #expect(s.leds.count == 3)
        #expect(s.leds.allSatisfy { $0.mode == .battery && $0.brightness == 1 })
    }

    @Test func dpiRoundTrip() {
        // Chakram sends half the DPI: 3200 -> (1600 - 50) / 50 = 31 = 0x1f
        #expect(Array(model.setDPI(stage: 3, dpi: 3200).prefix(6)) == [0x51, 0x31, 0x03, 0x00, 0x1F, 0x00])
        #expect(Array(model.setDPI(stage: 0, dpi: 16000).prefix(6)) == [0x51, 0x31, 0x00, 0x00, 0x9F, 0x00])
        #expect(model.setDPI(stage: 0, dpi: 50)[4] == 0x00) // clamped to 100
    }

    @Test func settingFields() {
        #expect(Array(model.setPollingRate(.hz500).prefix(5)) == [0x51, 0x31, 0x04, 0x00, 0x02])
        #expect(Array(model.setDebounce(.ms16).prefix(5)) == [0x51, 0x31, 0x05, 0x00, 0x03])
        #expect(Array(model.setAngleSnapping(true).prefix(5)) == [0x51, 0x31, 0x06, 0x00, 0x01])
    }

    @Test func buttonAndLED() {
        let back = model.buttons[3]
        #expect(Array(model.setButton(back, .key(0x04)).prefix(8)) == [0x51, 0x21, 0, 0, 0xE4, 0x01, 0x04, 0x00])
        #expect(Array(model.setButton(back, .disabled).prefix(8)) == [0x51, 0x21, 0, 0, 0xE4, 0x01, 0xFF, 0x01])
        let led = MouseLED(mode: .breathing, brightness: 4, color: RGB(1, 2, 3), speed: 5)
        #expect(Array(model.setLED(zone: 2, led).prefix(12)) == [0x51, 0x28, 0x02, 0x00, 0x01, 0x04, 1, 2, 3, 0, 0, 5])
    }

    @Test func power() {
        // Captured before and after ~1 h on the charging cable.
        let before = PowerInfo(bytes("12 07 00 00 02 02 01"))
        let after = PowerInfo(bytes("12 07 00 00 03 02 01"))
        #expect(before.chargePercent == 50)
        #expect(after.chargePercent == 75)
        #expect(after.sleepRaw == 2 && after.alertRaw == 1)
    }
}
