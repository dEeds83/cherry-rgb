import CherryRGBKit
import SwiftUI

struct KeyEditorView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: Set<Int> = []
    @State private var brush = RGB(0, 200, 255)
    @State private var hovered: KeyCap?

    private let unit: CGFloat = 44
    private let gap: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            keyboard
            controls
        }
        .padding(18)
        .onAppear {
            // Opening the editor implies per-key mode.
            state.settings.kind = .perKey
        }
    }

    private var keyboard: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Layout.g80TKL) { key in
                keyView(key)
                    .offset(x: key.x * unit, y: key.y * unit)
            }
        }
        .frame(width: Layout.width * unit, height: Layout.height * unit, alignment: .topLeading)
        .padding(10)
        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
    }

    private func keyView(_ key: KeyCap) -> some View {
        let color = state.settings.keyColors[key.index]
        let selected = selection.contains(key.index)
        let lum = (0.299 * Double(color.r) + 0.587 * Double(color.g) + 0.114 * Double(color.b)) / 255
        return Text(key.label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(lum > 0.55 ? Color.black : Color.white)
            .frame(width: key.w * unit - gap, height: key.h * unit - gap)
            .background(color.color, in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(selected ? Color.accentColor : Color.white.opacity(0.15), lineWidth: selected ? 3 : 1)
            )
            .contentShape(Rectangle())
            .onHover { hovered = $0 ? key : (hovered == key ? nil : hovered) }
            .onTapGesture { tap(key) }
            .help("LED-Index \(key.index)")
    }

    private var controls: some View {
        HStack(alignment: .center, spacing: 14) {
            ColorPicker("Pinsel", selection: Binding(get: { brush.color }, set: { brush = RGB($0) }),
                        supportsOpacity: false)
            presetRow { brush = $0 }

            Divider().frame(height: 22)

            Button("Auswahl färben") { paint(selection) }
                .disabled(selection.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            Button("Alle färben") { paint(Set(0..<KeyColors.count)) }
            Button("Auswahl leeren") { selection.removeAll() }
                .disabled(selection.isEmpty)

            Spacer()

            Text(hovered.map { "\($0.label.isEmpty ? "Leertaste" : $0.label) · Index \($0.index)" }
                 ?? "Klick = färben · ⇧-Klick = auswählen")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 200, alignment: .trailing)
        }
    }

    private func tap(_ key: KeyCap) {
        if NSEvent.modifierFlags.contains(.shift) {
            if selection.contains(key.index) { selection.remove(key.index) } else { selection.insert(key.index) }
        } else {
            paint([key.index])
        }
    }

    private func paint(_ indices: Set<Int>) {
        var colors = state.settings.keyColors
        for i in indices { colors[i] = brush }
        state.settings.keyColors = colors
        state.settings.kind = .perKey
    }
}
