import Foundation

public final class KeyDecoder {
    private var buffer: [UInt8] = []

    // Bracketed paste buffering.
    private var pasteBuffer: [UInt8] = []
    private var inPaste: Bool = false

    public init() {}

    public func feed(_ bytes: Data) -> [InputEvent] {
        buffer.append(contentsOf: bytes)
        var out: [InputEvent] = []

        while true {
            if inPaste {
                if let endIdx = findSequence(in: buffer, needle: Array(ASCII.bracketedPasteEnd)) {
                    // Consume through end marker.
                    let pasteChunk = buffer.prefix(endIdx)
                    pasteBuffer.append(contentsOf: pasteChunk)
                    buffer.removeFirst(endIdx + ASCII.bracketedPasteEnd.count)
                    inPaste = false

                    let s = String(decoding: pasteBuffer, as: UTF8.self)
                    pasteBuffer.removeAll(keepingCapacity: true)
                    out.append(.paste(s))
                    continue
                }

                // No end marker yet: consume all.
                pasteBuffer.append(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: false)
                break
            }

            // Detect paste start anywhere in the buffer.
            if let startIdx = findSequence(in: buffer, needle: Array(ASCII.bracketedPasteStart)) {
                // Decode anything before the start as normal input.
                if startIdx > 0 {
                    out.append(contentsOf: decodeBytes(Array(buffer.prefix(startIdx))))
                }
                buffer.removeFirst(startIdx + ASCII.bracketedPasteStart.count)
                inPaste = true
                pasteBuffer.removeAll(keepingCapacity: true)
                continue
            }

            if buffer.isEmpty { break }

            // Decode one key event.
            guard let (evt, consumed) = decodeOne(from: buffer) else { break }
            out.append(.key(evt))
            buffer.removeFirst(consumed)
        }

        return out
    }

    private func decodeBytes(_ bytes: [UInt8]) -> [InputEvent] {
        var tmp = bytes
        var out: [InputEvent] = []
        while !tmp.isEmpty {
            if let (evt, consumed) = decodeOne(from: tmp) {
                out.append(.key(evt))
                tmp.removeFirst(consumed)
            } else {
                out.append(.raw(Data(tmp)))
                break
            }
        }
        return out
    }

    private func decodeOne(from b: [UInt8]) -> (KeyEvent, Int)? {
        guard !b.isEmpty else { return nil }
        let b0 = b[0]

        // Tab
        if b0 == ASCII.tab {
            return (KeyEvent(key: .tab), 1)
        }

        // Enter (CR or LF). Some terminals send LF for Enter.
        if b0 == ASCII.cr || b0 == ASCII.lf {
            return (KeyEvent(key: .enter), 1)
        }

        // Escape sequences.
        if b0 == ASCII.esc {
            if b.count == 1 { return nil }
            let b1 = b[1]

            // CSI: ESC [ ...
            if b1 == ASCII.leftBracket {
                // Kitty CSI-u: ESC [ <codepoint> ... u
                if let (evt, consumed) = decodeKittyCSIu(from: b) {
                    return (evt, consumed)
                }
                return decodeCSI(from: b)
            }

            // SS3: ESC O ...
            if b1 == ASCII.o {
                return decodeSS3(from: b)
            }

            // Alt-modified UTF-8 printable (ESC + utf8)
            if let (c, len) = decodeUTF8(from: Array(b.dropFirst(1))) {
                return (KeyEvent(key: .char(c), modifiers: [.alt]), 1 + len)
            }

            return (KeyEvent(key: .escape), 1)
        }

        // Backspace (DEL)
        if b0 == ASCII.del {
            return (KeyEvent(key: .backspace), 1)
        }

        // Space
        if b0 == ASCII.space {
            return (KeyEvent(key: .space), 1)
        }

        // C0 control chars (Ctrl+A..Ctrl+Z) map to 1..26.
        if b0 >= 1 && b0 <= 26 {
            let scalar = UnicodeScalar(Int(b0) + Int(UnicodeScalar("a").value) - 1)!
            return (KeyEvent(key: .char(Character(scalar)), modifiers: [.ctrl]), 1)
        }

        // UTF-8 printable.
        if let (c, len) = decodeUTF8(from: b) {
            return (KeyEvent(key: .char(c)), len)
        }

        return nil
    }

    private func decodeCSI(from b: [UInt8]) -> (KeyEvent, Int)? {
        if b.count < 3 { return nil }
        // b starts with ESC [
        let b2 = b[2]
        switch b2 {
        case ASCII.A: return (KeyEvent(key: .up), 3)
        case ASCII.B: return (KeyEvent(key: .down), 3)
        case ASCII.C: return (KeyEvent(key: .right), 3)
        case ASCII.D: return (KeyEvent(key: .left), 3)
        case ASCII.H: return (KeyEvent(key: .home), 3)
        case ASCII.F: return (KeyEvent(key: .end), 3)
        case ASCII.Z: return (KeyEvent(key: .tab, modifiers: [.shift]), 3)
        default:
            break
        }

        // Numeric CSI: ESC [ <digits> ~
        var i = 2
        var num = 0
        var sawDigit = false
        while i < b.count {
            let x = b[i]
            if x >= ASCII.zero && x <= ASCII.nine {
                sawDigit = true
                num = num * 10 + Int(x - ASCII.zero)
                i += 1
                continue
            }
            if x == ASCII.tilde {
                if !sawDigit { return nil }
                switch num {
                case 1: return (KeyEvent(key: .home), i + 1)
                case 4: return (KeyEvent(key: .end), i + 1)
                case 3: return (KeyEvent(key: .delete), i + 1)
                case 5: return (KeyEvent(key: .pageUp), i + 1)
                case 6: return (KeyEvent(key: .pageDown), i + 1)
                case 11: return (KeyEvent(key: .f(1)), i + 1)
                case 12: return (KeyEvent(key: .f(2)), i + 1)
                case 13: return (KeyEvent(key: .f(3)), i + 1)
                case 14: return (KeyEvent(key: .f(4)), i + 1)
                case 15: return (KeyEvent(key: .f(5)), i + 1)
                case 17: return (KeyEvent(key: .f(6)), i + 1)
                case 18: return (KeyEvent(key: .f(7)), i + 1)
                case 19: return (KeyEvent(key: .f(8)), i + 1)
                case 20: return (KeyEvent(key: .f(9)), i + 1)
                case 21: return (KeyEvent(key: .f(10)), i + 1)
                case 23: return (KeyEvent(key: .f(11)), i + 1)
                case 24: return (KeyEvent(key: .f(12)), i + 1)
                default: return nil
                }
            }
            return nil
        }
        return nil
    }

    private func decodeSS3(from b: [UInt8]) -> (KeyEvent, Int)? {
        if b.count < 3 { return nil }
        let b2 = b[2]
        switch b2 {
        case ASCII.P: return (KeyEvent(key: .f(1)), 3)
        case ASCII.Q: return (KeyEvent(key: .f(2)), 3)
        case ASCII.R: return (KeyEvent(key: .f(3)), 3)
        case ASCII.S: return (KeyEvent(key: .f(4)), 3)
        case ASCII.H: return (KeyEvent(key: .home), 3)
        case ASCII.F: return (KeyEvent(key: .end), 3)
        default: return nil
        }
    }

    // Kitty CSI-u: ESC [ <codepoint>(:<shifted>)?(...)?;<mods>u
    // We implement the common form: ESC [ <codepoint> ; <mods> u
    // Modifiers are 1-indexed and represent Shift=1, Alt=2, Ctrl=4 as bitmask.
    private func decodeKittyCSIu(from b: [UInt8]) -> (KeyEvent, Int)? {
        // Need at least: ESC [ digits ; digits u
        if b.count < 6 { return nil }
        if b[0] != ASCII.esc || b[1] != ASCII.leftBracket { return nil }

        var i = 2
        func parseInt() -> Int? {
            var n = 0
            var saw = false
            while i < b.count {
                let x = b[i]
                if x >= ASCII.zero && x <= ASCII.nine {
                    saw = true
                    n = n * 10 + Int(x - ASCII.zero)
                    i += 1
                    continue
                }
                break
            }
            return saw ? n : nil
        }

        guard let codepoint = parseInt() else { return nil }

        // Skip optional :shifted / :base parts.
        while i < b.count, b[i] == ASCII.colon {
            i += 1
            _ = parseInt()
        }

        guard i < b.count, b[i] == ASCII.semicolon else { return nil }
        i += 1
        guard let modsValue = parseInt() else { return nil }
        guard i < b.count, b[i] == ASCII.u else { return nil }
        i += 1

        let mods = max(0, modsValue - 1) // kitty is 1-indexed
        var m: KeyEvent.Modifiers = []
        if (mods & 1) != 0 { m.insert(.shift) }
        if (mods & 2) != 0 { m.insert(.alt) }
        if (mods & 4) != 0 { m.insert(.ctrl) }

        if let scalar = UnicodeScalar(codepoint) {
            return (KeyEvent(key: .char(Character(scalar)), modifiers: m), i)
        }
        return (KeyEvent(key: .unknown("kitty")), i)
    }

    private func decodeUTF8(from bytes: [UInt8]) -> (Character, Int)? {
        guard let first = bytes.first else { return nil }
        let len: Int
        if first < 0x80 { len = 1 }
        else if (first & 0xE0) == 0xC0 { len = 2 }
        else if (first & 0xF0) == 0xE0 { len = 3 }
        else if (first & 0xF8) == 0xF0 { len = 4 }
        else { return nil }

        if bytes.count < len { return nil }
        let slice = bytes.prefix(len)
        let s = String(decoding: slice, as: UTF8.self)
        guard s.count == 1, let c = s.first else { return nil }
        return (c, len)
    }

    private func findSequence(in haystack: [UInt8], needle: [UInt8]) -> Int? {
        if needle.isEmpty { return 0 }
        if haystack.count < needle.count { return nil }
        if needle.count == 1 {
            return haystack.firstIndex(of: needle[0])
        }
        for i in 0...(haystack.count - needle.count) {
            var ok = true
            for j in 0..<needle.count {
                if haystack[i + j] != needle[j] { ok = false; break }
            }
            if ok { return i }
        }
        return nil
    }
}

private enum ASCII {
    static let esc: UInt8 = 0x1B
    static let tab: UInt8 = 0x09
    static let cr: UInt8 = 0x0D
    static let lf: UInt8 = 0x0A
    static let del: UInt8 = 0x7F
    static let space: UInt8 = 0x20

    static let leftBracket: UInt8 = 0x5B // [
    static let o: UInt8 = 0x4F // O

    static let A: UInt8 = 0x41
    static let B: UInt8 = 0x42
    static let C: UInt8 = 0x43
    static let D: UInt8 = 0x44
    static let F: UInt8 = 0x46
    static let H: UInt8 = 0x48
    static let P: UInt8 = 0x50
    static let Q: UInt8 = 0x51
    static let R: UInt8 = 0x52
    static let S: UInt8 = 0x53
    static let Z: UInt8 = 0x5A

    static let zero: UInt8 = 0x30
    static let nine: UInt8 = 0x39

    static let tilde: UInt8 = 0x7E
    static let semicolon: UInt8 = 0x3B
    static let colon: UInt8 = 0x3A
    static let u: UInt8 = 0x75

    static let bracketedPasteStart: [UInt8] = Array("\u{001B}[200~".utf8)
    static let bracketedPasteEnd: [UInt8] = Array("\u{001B}[201~".utf8)
}

