import DeskGearKit
import SwiftUI

struct MouseSettingsView: View {
    @EnvironmentObject var mouse: MouseController

    var body: some View {
        VStack(spacing: 0) {
            if let model = mouse.model, mouse.current != nil {
                TabView {
                    PerformanceTab(model: model).tabItem { Text("Leistung") }
                    ButtonsTab(model: model).tabItem { Text("Tasten") }
                    LightingTab(model: model).tabItem { Text("Beleuchtung") }
                    InfoTab(model: model).tabItem { Text("Info") }
                }
                .padding(16)

                Divider()
                footer
            } else {
                VStack(spacing: 10) {
                    if mouse.connectedName == nil {
                        Text("Keine ASUS-Maus verbunden")
                    } else if mouse.asleep {
                        Text("Maus schläft – kurz bewegen, die Einstellungen laden dann automatisch.")
                    } else {
                        ProgressView("Lese Einstellungen …")
                    }
                }
                .padding(40)
            }
        }
        .frame(width: 520)
    }

    private var footer: some View {
        HStack {
            if let err = mouse.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            } else if mouse.busy {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Button("Neu laden") { Task { await mouse.reload() } }
            Button("Verwerfen") { mouse.discardChanges() }
                .disabled(!mouse.hasChanges)
            Button("In Maus speichern") { Task { await mouse.commit() } }
                .keyboardShortcut(.defaultAction)
                .disabled(!mouse.hasChanges || mouse.busy)
        }
        .padding(12)
    }
}

// MARK: - Tabs

private struct PerformanceTab: View {
    @EnvironmentObject var mouse: MouseController
    let model: AsusMouseModel

    var body: some View {
        Form {
            Section("DPI-Stufen (Profil \(mouse.draft.profile + 1))") {
                ForEach(mouse.draft.dpi.indices, id: \.self) { i in
                    HStack {
                        Text("Stufe \(i + 1)")
                            .fontWeight(i == mouse.draft.activeDPIStage ? .bold : .regular)
                            .frame(width: 60, alignment: .leading)
                        Slider(value: dpiBinding(i),
                               in: Double(model.dpiRange.lowerBound)...Double(model.dpiRange.upperBound),
                               step: Double(model.dpiStep))
                        Stepper(value: Binding(get: { mouse.draft.dpi[i] }, set: { mouse.draft.dpi[i] = $0 }),
                                in: model.dpiRange, step: model.dpiStep) {
                            Text("\(mouse.draft.dpi[i])").monospacedDigit().frame(width: 50, alignment: .trailing)
                        }
                    }
                }
            }
            Section("Allgemein") {
                Picker("Abtastrate", selection: $mouse.draft.pollingRate) {
                    ForEach(PollingRate.allCases) { Text("\($0.hz) Hz").tag($0) }
                }
                Picker("Tastenreaktion", selection: $mouse.draft.debounce) {
                    ForEach(Debounce.allCases) { Text("\($0.ms) ms").tag($0) }
                }
                Toggle("Winkelkorrektur (Angle Snapping)", isOn: $mouse.draft.angleSnapping)
            }
        }
        .formStyle(.grouped)
    }

    private func dpiBinding(_ i: Int) -> Binding<Double> {
        Binding(get: { Double(mouse.draft.dpi[i]) }, set: { mouse.draft.dpi[i] = Int($0) })
    }
}

private struct ButtonsTab: View {
    @EnvironmentObject var mouse: MouseController
    let model: AsusMouseModel

    private var choices: [ButtonAction] {
        AsusCodes.mouseActions.keys.sorted().map { .mouse($0) }
            + [.disabled]
            + AsusCodes.keys.keys.sorted().map { .key($0) }
    }

    var body: some View {
        Form {
            Section("Belegung (Profil \(mouse.draft.profile + 1))") {
                ForEach(model.buttons) { slot in
                    if slot.index < mouse.draft.buttons.count {
                        Picker(slot.name, selection: $mouse.draft.buttons[slot.index]) {
                            let current = mouse.draft.buttons[slot.index]
                            if !choices.contains(current) { Text(current.displayName).tag(current) }
                            ForEach(choices, id: \.self) { Text($0.displayName).tag($0) }
                        }
                    }
                }
            }
            Text("Tipp: Linksklick nie deaktivieren, ohne eine andere Taste mit Linksklick zu belegen.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct LightingTab: View {
    @EnvironmentObject var mouse: MouseController
    let model: AsusMouseModel
    @State private var linked = true

    var body: some View {
        Form {
            Toggle("Alle Zonen gleich", isOn: $linked)
            if linked {
                if !mouse.draft.leds.isEmpty { zone(name: "Alle Zonen", index: 0) }
            } else {
                ForEach(model.ledZones.indices, id: \.self) { i in
                    if i < mouse.draft.leds.count { zone(name: model.ledZones[i], index: i) }
                }
            }
            Text("„Akkustand“ zeigt den Ladezustand über die Farbe an (beim Laden blau atmend).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func zone(name: String, index: Int) -> some View {
        let led = mouse.draft.leds[index]
        Section(name) {
            Picker("Effekt", selection: binding(index, \.mode)) {
                ForEach(MouseLEDMode.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Helligkeit", selection: binding(index, \.brightness)) {
                ForEach(0..<5) { Text($0 == 0 ? "Aus" : "\($0 * 25) %").tag(UInt8($0)) }
            }
            if led.mode.supportsColor {
                ColorPicker("Farbe", selection: Binding(
                    get: { led.color.color },
                    set: { c in set(index) { $0.color = RGB(c) } }
                ), supportsOpacity: false)
            }
            if led.mode.supportsSpeed {
                Slider(value: Binding(
                    get: { Double(16 - Int(led.speed)) },
                    set: { v in set(index) { $0.speed = UInt8(16 - Int(v)) } }
                ), in: 1...15, step: 1) { Text("Tempo") }
            }
        }
    }

    private func binding<T>(_ index: Int, _ kp: WritableKeyPath<MouseLED, T>) -> Binding<T> {
        Binding(get: { mouse.draft.leds[index][keyPath: kp] },
                set: { v in set(index) { $0[keyPath: kp] = v } })
    }

    /// Applies the change to one zone, or all zones when linked.
    private func set(_ index: Int, _ change: (inout MouseLED) -> Void) {
        let targets = linked ? Array(mouse.draft.leds.indices) : [index]
        for i in targets { change(&mouse.draft.leds[i]) }
    }
}

private struct InfoTab: View {
    @EnvironmentObject var mouse: MouseController
    let model: AsusMouseModel

    var body: some View {
        Form {
            LabeledContent("Modell", value: model.name)
            LabeledContent("Firmware", value: mouse.current?.firmware ?? "–")
            LabeledContent("Aktives Profil", value: "\((mouse.current?.profile ?? 0) + 1)")
            if let p = mouse.current?.power {
                Section("Energie (experimentell)") {
                    LabeledContent("Akku", value: p.chargePercent.map { "ca. \($0) %" } ?? "unbekannt")
                    LabeledContent("Rohwerte 12 07", value: String(format: "%02x %02x %02x", p.sleepRaw, p.chargeRaw, p.alertRaw))
                }
            }
        }
        .formStyle(.grouped)
    }
}
