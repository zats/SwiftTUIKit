import Foundation

enum UnicodeWidth {
    static func width(of ch: Character) -> Int {
        // Terminal cell width approximation:
        // - Combining marks: 0
        // - East Asian wide/fullwidth: 2
        // - Everything else: 1
        //
        // This is not a perfect wcwidth implementation, but it is good enough for
        // most UI alignment, and avoids pulling in heavy dependencies.
        var w = 0
        for scalar in ch.unicodeScalars {
            if scalar.properties.isJoinControl { continue }
            if scalar.properties.canonicalCombiningClass != .notReordered { continue }
            if scalar.value == 0 { continue }

            if isWide(scalar) {
                w += 2
            } else {
                w += 1
            }
        }
        return max(0, w)
    }

    private static func isWide(_ s: Unicode.Scalar) -> Bool {
        // Heuristic: treat a few common ranges as wide.
        let v = s.value
        switch v {
        case 0x1100...0x115F, // Hangul Jamo init. consonants
             0x2329...0x232A,
             0x2E80...0xA4CF, // CJK ... Yi
             0xAC00...0xD7A3, // Hangul Syllables
             0xF900...0xFAFF, // CJK Compatibility Ideographs
             0xFE10...0xFE19,
             0xFE30...0xFE6F,
             0xFF00...0xFF60,
             0xFFE0...0xFFE6:
            return true
        default:
            return false
        }
    }
}
