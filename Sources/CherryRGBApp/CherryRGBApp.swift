import CherryRGBKit
import SwiftUI

@main
struct CherryRGBApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(state)
        } label: {
            Image(systemName: state.connectedName == nil ? "keyboard.badge.ellipsis" : "keyboard")
        }
        .menuBarExtraStyle(.window)

        Window("Per-Key-Editor", id: "editor") {
            KeyEditorView().environmentObject(state)
        }
        .windowResizability(.contentSize)
    }
}

struct MenuView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !state.hasAccess {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Für die Tastatur braucht die App die Berechtigung „Eingabeüberwachung“.")
                        .font(.callout)
                    Button("Systemeinstellungen öffnen") { state.openInputMonitoringSettings() }
                }
                .padding(8)
                .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            }

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

            Divider()

            Toggle("Beim Login starten", isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.setLaunchAtLogin($0) }
            ))

            HStack {
                Button("Erneut anwenden") { Task { await state.apply() } }
                Button("Aus") { state.turnOff() }
                Spacer()
                Button("Beenden") { NSApp.terminate(nil) }
            }

            if let err = state.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var header: some View {
        HStack {
            Circle()
                .fill(state.connectedName == nil ? Color.secondary : Color.green)
                .frame(width: 8, height: 8)
            Text(state.connectedName ?? "Keine Tastatur verbunden")
                .font(.headline)
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
