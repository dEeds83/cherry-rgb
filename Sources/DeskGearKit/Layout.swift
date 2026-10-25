import Foundation

/// One physical key: LED index plus position/size in key units (1u = one letter key).
public struct KeyCap: Identifiable, Hashable, Sendable {
    public let label: String
    public let index: Int
    public let x: Double
    public let y: Double
    public let w: Double
    public let h: Double

    public var id: Int { index }

    init(_ label: String, _ index: Int, _ x: Double, _ y: Double, w: Double = 1, h: Double = 1) {
        self.label = label; self.index = index; self.x = x; self.y = y; self.w = w; self.h = h
    }
}

/// G80-3000N TKL, ISO German layout.
///
/// LED indices run column by column, 6 rows each: index = column * 6 + row,
/// row 0 being the F-key row (see examples/static_rainbow.json in cherryrgb-rs).
/// Pause (102) is not covered by the upstream map and may need adjusting.
public enum Layout {
    public static let g80TKL: [KeyCap] = {
        var k: [KeyCap] = []
        // Row 0 – function row
        let r0 = 0.0
        k.append(KeyCap("Esc", 0, 0, r0))
        for (i, (idx, x)) in [(18, 2.0), (24, 3), (30, 4), (36, 5), (42, 6.5), (48, 7.5), (54, 8.5), (60, 9.5),
                               (66, 11), (72, 12), (78, 13), (84, 14)].enumerated() {
            k.append(KeyCap("F\(i + 1)", idx, x, r0))
        }
        k += [KeyCap("Druck", 90, 15.25, r0), KeyCap("Rollen", 96, 16.25, r0), KeyCap("Pause", 102, 17.25, r0)]

        // Row 1 – numbers
        let r1 = 1.25
        let numbers: [(String, Int)] = [("^", 1), ("1", 7), ("2", 13), ("3", 19), ("4", 25), ("5", 31), ("6", 37),
                                        ("7", 43), ("8", 49), ("9", 55), ("0", 61), ("ß", 67), ("´", 73)]
        for (i, (l, idx)) in numbers.enumerated() { k.append(KeyCap(l, idx, Double(i), r1)) }
        k += [KeyCap("⌫", 79, 13, r1, w: 2),
              KeyCap("Einfg", 85, 15.25, r1), KeyCap("Pos1", 91, 16.25, r1), KeyCap("Bild↑", 97, 17.25, r1)]

        // Row 2 – QWERTZ
        let r2 = 2.25
        k.append(KeyCap("⇥", 2, 0, r2, w: 1.5))
        let top: [(String, Int)] = [("Q", 8), ("W", 14), ("E", 20), ("R", 26), ("T", 32), ("Z", 38), ("U", 44),
                                    ("I", 50), ("O", 56), ("P", 62), ("Ü", 68), ("+", 74)]
        for (i, (l, idx)) in top.enumerated() { k.append(KeyCap(l, idx, 1.5 + Double(i), r2)) }
        k += [KeyCap("⏎", 81, 13.75, r2, w: 1.25, h: 2),
              KeyCap("Entf", 86, 15.25, r2), KeyCap("Ende", 92, 16.25, r2), KeyCap("Bild↓", 98, 17.25, r2)]

        // Row 3 – home row
        let r3 = 3.25
        k.append(KeyCap("⇪", 3, 0, r3, w: 1.75))
        let home: [(String, Int)] = [("A", 9), ("S", 15), ("D", 21), ("F", 27), ("G", 33), ("H", 39), ("J", 45),
                                     ("K", 51), ("L", 57), ("Ö", 63), ("Ä", 69), ("#", 75)]
        for (i, (l, idx)) in home.enumerated() { k.append(KeyCap(l, idx, 1.75 + Double(i), r3)) }

        // Row 4 – shift row
        let r4 = 4.25
        k += [KeyCap("⇧", 4, 0, r4, w: 1.25), KeyCap("<", 10, 1.25, r4)]
        let bottom: [(String, Int)] = [("Y", 16), ("X", 22), ("C", 28), ("V", 34), ("B", 40), ("N", 46), ("M", 52),
                                       (",", 58), (".", 64), ("-", 70)]
        for (i, (l, idx)) in bottom.enumerated() { k.append(KeyCap(l, idx, 2.25 + Double(i), r4)) }
        k += [KeyCap("⇧", 82, 12.25, r4, w: 2.75), KeyCap("↑", 94, 16.25, r4)]

        // Row 5 – modifiers
        let r5 = 5.25
        k += [KeyCap("Strg", 5, 0, r5, w: 1.25), KeyCap("Win", 11, 1.25, r5, w: 1.25), KeyCap("Alt", 17, 2.5, r5, w: 1.25),
              KeyCap("", 41, 3.75, r5, w: 6.25), KeyCap("AltGr", 65, 10, r5, w: 1.25), KeyCap("Fn", 71, 11.25, r5, w: 1.25),
              KeyCap("Menü", 77, 12.5, r5, w: 1.25), KeyCap("Strg", 83, 13.75, r5, w: 1.25),
              KeyCap("←", 89, 15.25, r5), KeyCap("↓", 95, 16.25, r5), KeyCap("→", 101, 17.25, r5)]
        return k
    }()

    public static let width = 18.25
    public static let height = 6.25
}
