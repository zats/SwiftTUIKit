import Foundation

public enum ANSI {
    // MARK: - Terminal Modes

    /// Synchronized output (atomic updates, reduces flicker). See DECSET 2026.
    public static let syncOutputOn = "\u{001B}[?2026h"
    public static let syncOutputOff = "\u{001B}[?2026l"

    /// Bracketed paste mode.
    public static let bracketedPasteOn = "\u{001B}[?2004h"
    public static let bracketedPasteOff = "\u{001B}[?2004l"

    public static let hideCursor = "\u{001B}[?25l"
    public static let showCursor = "\u{001B}[?25h"

    public static let clearScreen = "\u{001B}[2J"
    public static let clearFromCursor = "\u{001B}[0J"
    public static let clearLine = "\u{001B}[2K"

    public static let sgrReset = "\u{001B}[0m"
    public static let osc8Reset = "\u{001B}]8;;\u{0007}"

    public static func moveCursor(row: Int, col: Int) -> String {
        "\u{001B}[\(max(1, row));\(max(1, col))H"
    }

    public static func moveUp(_ n: Int) -> String { "\u{001B}[\(max(0, n))A" }
    public static func moveDown(_ n: Int) -> String { "\u{001B}[\(max(0, n))B" }
    public static func moveRight(_ n: Int) -> String { "\u{001B}[\(max(0, n))C" }
    public static func moveLeft(_ n: Int) -> String { "\u{001B}[\(max(0, n))D" }

    // MARK: - Cursor Marker (IME)

    /// Zero-width cursor marker (APC-like sequence) used for IME cursor placement.
    /// Matches pi-mono: "\x1b_pi:c\x07"
    public static let cursorMarker = "\u{001B}_pi:c\u{0007}"

    // MARK: - Width Utilities

    public static func visibleWidth(_ s: String) -> Int {
        var width = 0
        for token in tokenize(s) {
            if token.kind == .text {
                width += token.width
            }
        }
        return width
    }

    public static func truncateToWidth(_ s: String, width: Int, ellipsis: String = "...") -> String {
        guard width >= 0 else { return "" }
        if visibleWidth(s) <= width { return s }

        let ellW = visibleWidth(ellipsis)
        let target = max(0, width - ellW)

        var out = ""
        out.reserveCapacity(s.count)

        var col = 0
        var state = AnsiState()
        for token in tokenize(s) {
            switch token.kind {
            case .ansi:
                out += token.text
                state.update(with: token.text)
            case .text:
                if col + token.width > target { break }
                out += token.text
                col += token.width
            }
            if col >= target { break }
        }

        if !ellipsis.isEmpty { out += ellipsis }
        // Ensure we don't leak styles past this line.
        out += sgrReset + osc8Reset
        return out
    }

    public static func wrapTextWithAnsi(_ s: String, width: Int) -> [String] {
        guard width > 0 else { return [""] }
        if s.isEmpty { return [""] }

        var lines: [String] = []
        lines.reserveCapacity(8)

        var state = AnsiState()
        var current = ""
        var col = 0

        func flush() {
            // Close styles at end-of-line so the TUI can safely append resets too.
            lines.append(current + sgrReset + osc8Reset)
            current = state.reapplyPrefix()
            col = 0
        }

        // Start the first line with any state (none).
        current = state.reapplyPrefix()

        for token in tokenize(s) {
            switch token.kind {
            case .ansi:
                current += token.text
                state.update(with: token.text)
            case .text:
                if col + token.width > width {
                    if col == 0 {
                        // Single grapheme wider than width: still emit it.
                        current += token.text
                        flush()
                        continue
                    }
                    flush()
                }
                current += token.text
                col += token.width
            }
        }

        // Add final line.
        lines.append(current + sgrReset + osc8Reset)
        return lines
    }

    /// Slice a line by visible columns, preserving ANSI sequences.
    /// `startCol` is 0-based. `length` is the number of visible columns.
    public static func sliceByColumn(_ s: String, startCol: Int, length: Int) -> String {
        if length <= 0 { return "" }
        let startCol = max(0, startCol)

        var state = AnsiState()
        var col = 0

        // First pass: advance to startCol and capture active style state there.
        for token in tokenize(s) {
            switch token.kind {
            case .ansi:
                state.update(with: token.text)
            case .text:
                if col + token.width <= startCol {
                    col += token.width
                    continue
                }
                // We reached or crossed start.
                break
            }
            if col >= startCol { break }
        }

        var out = state.reapplyPrefix()
        out.reserveCapacity(s.count)

        col = 0
        var outCol = 0
        var emitting = false

        for token in tokenize(s) {
            switch token.kind {
            case .ansi:
                if emitting {
                    out += token.text
                }
                state.update(with: token.text)
            case .text:
                let nextCol = col + token.width
                if nextCol <= startCol {
                    col = nextCol
                    continue
                }
                if !emitting {
                    emitting = true
                    // Apply style at slice start.
                    out = state.reapplyPrefix()
                }
                if outCol + token.width > length { break }
                out += token.text
                outCol += token.width
                col = nextCol
                if outCol >= length { break }
            }
        }

        return out + sgrReset + osc8Reset
    }

    // MARK: - Tokenizer

    private struct Token: Sendable {
        enum Kind: Sendable { case ansi, text }
        var kind: Kind
        var text: String
        var width: Int
    }

    private static func tokenize(_ s: String) -> [Token] {
        if s.isEmpty { return [] }

        var out: [Token] = []
        out.reserveCapacity(min(128, s.count))

        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "\u{001B}" {
                if let (esc, next) = parseEscape(s, from: i) {
                    out.append(Token(kind: .ansi, text: esc, width: 0))
                    i = next
                    continue
                }
            }

            // Treat extended grapheme cluster as one cell width (often 1 or 2).
            let w = UnicodeWidth.width(of: ch)
            out.append(Token(kind: .text, text: String(ch), width: w))
            i = s.index(after: i)
        }

        return out
    }

    private static func parseEscape(_ s: String, from start: String.Index) -> (String, String.Index)? {
        // Recognize CSI/OSC/APC/DCS. If unknown, treat ESC as plain.
        let esc = "\u{001B}"
        guard s[start] == Character(esc) else { return nil }
        let next = s.index(after: start)
        guard next < s.endIndex else { return (esc, next) }

        let kind = s[next]
        switch kind {
        case "[":
            // CSI: ESC [ ... final in 0x40-0x7E
            var j = s.index(after: next)
            while j < s.endIndex {
                let u = s[j].unicodeScalars.first?.value ?? 0
                if u >= 0x40 && u <= 0x7E {
                    let end = s.index(after: j)
                    return (String(s[start..<end]), end)
                }
                j = s.index(after: j)
            }
            return nil
        case "]", "_", "P":
            // OSC (]), APC (_), DCS (P): terminated by BEL or ST (ESC \)
            var j = s.index(after: next)
            while j < s.endIndex {
                let c = s[j]
                if c == "\u{0007}" { // BEL
                    let end = s.index(after: j)
                    return (String(s[start..<end]), end)
                }
                if c == "\u{001B}" {
                    let j2 = s.index(after: j)
                    if j2 < s.endIndex, s[j2] == "\\" {
                        let end = s.index(after: j2)
                        return (String(s[start..<end]), end)
                    }
                }
                j = s.index(after: j)
            }
            return nil
        default:
            // Unknown ESC sequence: treat ESC as literal.
            return nil
        }
    }

    private struct AnsiState {
        // Minimal state: last SGR, last OSC 8 link opener.
        private var sgr: String = ""
        private var osc8: String = ""

        mutating func update(with ansi: String) {
            if ansi.hasPrefix("\u{001B}[") && ansi.hasSuffix("m") {
                if ansi == ANSI.sgrReset {
                    sgr = ""
                    return
                }
                // This is a lossy approximation but good enough for line wrapping.
                sgr = ansi
                return
            }

            if ansi.hasPrefix("\u{001B}]8;") {
                if ansi == ANSI.osc8Reset {
                    osc8 = ""
                } else {
                    osc8 = ansi
                }
            }
        }

        func reapplyPrefix() -> String {
            osc8 + sgr
        }
    }
}

