import DeskGearKit
import SwiftUI

@main
struct DeskGearApp: App {
    @StateObject private var state = AppState()
    @StateObject private var mouse = MouseController()

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(state).environmentObject(mouse)
        } label: {
            Image(systemName: state.connectedName == nil && mouse.connectedName == nil ? "keyboard.badge.ellipsis" : "keyboard")
        }
        .menuBarExtraStyle(.window)

        Window("Per-Key-Editor", id: "editor") {
            KeyEditorView().environmentObject(state)
        }
        .windowResizability(.contentSize)

        Window("Maus", id: "mouse") {
            MouseSettingsView().environmentObject(mouse)
        }
        .windowResizability(.contentSize)
    }
}

struct MenuView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var mouse: MouseController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !state.hasAccess {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Für die Tastatur braucht die App die Berechtigung „Eingabeüberwachung“.")
                        .font(.callout)
                    Button("Systemeinstellungen öffnen") { state.openInputMonitoringSettings() }
                }
                .padding(8)
                .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            }

            KeyboardSection()

            Divider()

            MouseSection()

            Divider()

            Toggle("Beim Login starten", isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.setLaunchAtLogin($0) }
            ))
            HStack {
                Spacer()
                Button("Beenden") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

struct DeviceHeader: View {
    let title: String
    let name: String?

    var body: some View {
        HStack {
            Circle()
                .fill(name == nil ? Color.secondary : Color.green)
                .frame(width: 8, height: 8)
            Text(name ?? "\(title): nicht verbunden")
                .font(.headline)
        }
    }
}

struct KeyboardSection: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DeviceHeader(title: "Tastatur", name: state.connectedName)

            Picker("", selection: $state.settings.kind) {
                ForEach(LightingKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch state.settings.kind {
            case .color: colorSection
            case .effect: effectSection
            case .perKey: perKeySection
            }

            LabeledContent("Helligkeit") {
                Picker("", selection: $state.settings.brightness) {
                    ForEach(Brightness.allCases) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            HStack {
                Button("Erneut anwenden") { Task { await state.apply() } }
                Button("Aus") { state.turnOff() }
            }

            if let err = state.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(get: { state.settings.color.color }, set: { state.settings.color = RGB($0) })
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ColorPicker("Farbe", selection: colorBinding, supportsOpacity: false)
            presetRow { state.settings.color = $0 }
        }
    }

    private var effectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Effekt") {
                Picker("", selection: $state.settings.effect) {
                    ForEach(LightingMode.effects) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .frame(width: 140)
            }
            if state.settings.effect.supportsSpeed {
                LabeledContent("Tempo") {
                    Picker("", selection: $state.settings.speed) {
                        ForEach(Speed.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
            }
            if state.settings.effect.supportsColor {
                Toggle("Regenbogen", isOn: $state.settings.rainbow)
                if !state.settings.rainbow {
                    ColorPicker("Farbe", selection: colorBinding, supportsOpacity: false)
                }
            }
        }
    }

    private var perKeySection: some View {
        Button("Editor öffnen …") {
            openWindow(id: "editor")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct MouseSection: View {
    @EnvironmentObject var mouse: MouseController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DeviceHeader(title: "Maus", name: mouse.connectedName)

            if mouse.connectedName != nil {
                if let s = mouse.current, let model = mouse.model {
                    Picker("Profil", selection: Binding(
                        get: { s.profile },
                        set: { p in Task { await mouse.switchProfile(p) } }
                    )) {
                        ForEach(0..<model.profiles, id: \.self) { Text("\($0 + 1)").tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Text("DPI-Stufe \(s.activeDPIStage + 1): \(s.dpi[safe: s.activeDPIStage] ?? 0) DPI · \(s.pollingRate.hz) Hz")
                        .font(.callout)
                    if let pct = s.power?.chargePercent {
                        Label("Akku ca. \(pct) % (experimentell)", systemImage: batteryIcon(pct))
                            .font(.callout)
                    }
                } else if mouse.asleep {
                    Text("Maus schläft – kurz bewegen").font(.callout).foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }

                Button("Einstellungen …") {
                    openWindow(id: "mouse")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }

            if let err = mouse.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func batteryIcon(_ pct: Int) -> String {
        switch pct {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

let colorPresets: [RGB] = [
    RGB(255, 0, 0), RGB(255, 80, 0), RGB(255, 200, 0), RGB(0, 255, 0),
    RGB(0, 200, 255), RGB(0, 0, 255), RGB(160, 0, 255), RGB(255, 255, 255),
]

func presetRow(_ pick: @escaping (RGB) -> Void) -> some View {
    HStack(spacing: 6) {
        ForEach(colorPresets, id: \.self) { c in
            Button { pick(c) } label: {
                Circle().fill(c.color).frame(width: 20, height: 20)
                    .overlay(Circle().stroke(.secondary.opacity(0.5)))
            }
            .buttonStyle(.plain)
        }
    }
}
