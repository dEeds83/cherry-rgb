import AppKit
import DeskGearKit
import ServiceManagement
import SwiftUI

enum LightingKind: String, Codable, CaseIterable, Identifiable {
    case color, effect, perKey
    var id: String { rawValue }
    var title: String {
        switch self {
        case .color: "Farbe"
        case .effect: "Effekt"
        case .perKey: "Per-Key"
        }
    }
}

/// Everything that is persisted and re-applied when the keyboard shows up.
struct LightingSettings: Codable, Equatable {
    var kind: LightingKind = .color
    var color = RGB(255, 80, 0)
    var brightness: Brightness = .full
    var effect: LightingMode = .wave
    var speed: Speed = .medium
    var rainbow = true
    var keyColors = KeyColors(fill: RGB(255, 80, 0))

    var payloads: [Payload] {
        switch kind {
        case .color:
            Commands.animation(mode: .staticColor, brightness: brightness, speed: .medium, color: color, rainbow: false)
        case .effect:
            Commands.animation(mode: effect, brightness: brightness, speed: speed, color: color,
                               rainbow: rainbow || !effect.supportsColor)
        case .perKey:
            Commands.custom(keyColors, brightness: brightness)
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    private static let defaultsKey = "lighting"

    @Published var settings: LightingSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            scheduleApply()
        }
    }
    @Published private(set) var connectedName: String?
    @Published private(set) var lastError: String?
    @Published private(set) var hasAccess = HIDConnection.hasInputMonitoringAccess
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    let keyboard = CherryKeyboard()
    private var applyTask: Task<Void, Never>?
    private var accessPoll: Timer?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let s = try? JSONDecoder().decode(LightingSettings.self, from: data) {
            settings = s
        } else {
            settings = LightingSettings()
        }

        keyboard.connection.log = { NSLog("DeskGear: %@", $0) }
        keyboard.connection.onConnectionChange = { [weak self] info in
            guard let self else { return }
            connectedName = info?.product
            if info != nil {
                lastError = nil
                // The keyboard falls back to its own default after replug / wake.
                scheduleApply(delay: .milliseconds(300))
            }
        }
        keyboard.connection.onError = { [weak self] err in
            guard let self else { return }
            lastError = err.description
            if case .accessDenied = err { waitForAccess() }
        }

        if !hasAccess {
            HIDConnection.requestInputMonitoringAccess()
            waitForAccess()
        }
    }

    // MARK: - Applying

    func scheduleApply(delay: Duration = .milliseconds(120)) {
        applyTask?.cancel()
        applyTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await apply()
        }
    }

    func apply() async {
        guard keyboard.isConnected else { return }
        do {
            try await keyboard.send(settings.payloads)
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
    }

    func turnOff() {
        Task {
            try? await keyboard.send(Commands.animation(mode: .staticColor, brightness: .off, speed: .medium,
                                                        color: .black, rainbow: false))
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    // MARK: - Permission

    /// Poll until the user ticks the app in Privacy & Security → Input Monitoring.
    private func waitForAccess() {
        guard accessPoll == nil else { return }
        accessPoll = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, HIDConnection.hasInputMonitoringAccess else { return }
                self.hasAccess = true
                self.accessPoll?.invalidate()
                self.accessPoll = nil
                self.keyboard.connection.retryPending()
            }
        }
    }

    func openInputMonitoringSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    // MARK: - Autostart

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastError = "Autostart: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

extension RGB {
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(UInt8(max(0, min(1, ns.redComponent)) * 255),
                  UInt8(max(0, min(1, ns.greenComponent)) * 255),
                  UInt8(max(0, min(1, ns.blueComponent)) * 255))
    }

    var color: Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}
