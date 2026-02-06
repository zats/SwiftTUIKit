import Foundation

public final class Input: Component, Focusable, @unchecked Sendable {
    private var value: String = ""
    private var cursor: String.Index

    public var onSubmit: (@Sendable (String) -> Void)?
    public var onEscape: (@Sendable () -> Void)?

    public var focused: Bool = false

    public init() {
        self.cursor = value.startIndex
    }

    public func getValue() -> String { value }

    public func setValue(_ v: String) {
        value = v
        cursor = min(cursor, value.endIndex)
    }

    public func invalidate() {
        // no cached state
    }

    public func handleInput(_ event: InputEvent) {
        switch event {
        case let .paste(s):
            handlePaste(s)
            return
        case let .key(k):
            handleKey(k)
        default:
            break
        }
    }

    private func handleKey(_ k: KeyEvent) {
        let kb = getEditorKeybindings()

        if k.type == .release, wantsKeyRelease == false {
            return
        }

        if kb.matches(k, action: .selectCancel) {
            onEscape?()
            return
        }

        if kb.matches(k, action: .submit) || k.key == .enter {
            onSubmit?(value)
            return
        }

        if kb.matches(k, action: .deleteCharBackward) || k.key == .backspace {
            deleteBackward()
            return
        }

        if kb.matches(k, action: .deleteCharForward) || k.key == .delete {
            deleteForward()
            return
        }

        if kb.matches(k, action: .deleteWordBackward) {
            deleteWordBackward()
            return
        }

        if kb.matches(k, action: .deleteToLineStart) {
            value.removeSubrange(value.startIndex..<cursor)
            cursor = value.startIndex
            return
        }

        if kb.matches(k, action: .deleteToLineEnd) {
            value.removeSubrange(cursor..<value.endIndex)
            return
        }

        if kb.matches(k, action: .cursorLeft) || k.key == .left {
            moveLeft()
            return
        }

        if kb.matches(k, action: .cursorRight) || k.key == .right {
            moveRight()
            return
        }

        if kb.matches(k, action: .cursorLineStart) || k.key == .home {
            cursor = value.startIndex
            return
        }

        if kb.matches(k, action: .cursorLineEnd) || k.key == .end {
            cursor = value.endIndex
            return
        }

        if kb.matches(k, action: .cursorWordLeft) {
            moveWordBackwards()
            return
        }

        if kb.matches(k, action: .cursorWordRight) {
            moveWordForwards()
            return
        }

        if case let .char(c) = k.key, k.modifiers.isEmpty || k.modifiers == [.alt] {
            // Reject control-ish chars.
            for scalar in String(c).unicodeScalars {
                if scalar.value < 32 || scalar.value == 0x7F || (scalar.value >= 0x80 && scalar.value <= 0x9F) {
                    return
                }
            }
            value.insert(c, at: cursor)
            cursor = value.index(after: cursor)
        }
    }

    private func deleteBackward() {
        guard cursor > value.startIndex else { return }
        let prev = value.index(before: cursor)
        value.removeSubrange(prev..<cursor)
        cursor = prev
    }

    private func deleteForward() {
        guard cursor < value.endIndex else { return }
        let next = value.index(after: cursor)
        value.removeSubrange(cursor..<next)
    }

    private func moveLeft() {
        guard cursor > value.startIndex else { return }
        cursor = value.index(before: cursor)
    }

    private func moveRight() {
        guard cursor < value.endIndex else { return }
        cursor = value.index(after: cursor)
    }

    private func isWhitespace(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private func isPunctuation(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) }
    }

    private func moveWordBackwards() {
        if cursor == value.startIndex { return }

        // Skip whitespace.
        while cursor > value.startIndex {
            let prev = value.index(before: cursor)
            if !isWhitespace(value[prev]) { break }
            cursor = prev
        }

        if cursor == value.startIndex { return }

        let prev = value.index(before: cursor)
        if isPunctuation(value[prev]) {
            while cursor > value.startIndex {
                let p = value.index(before: cursor)
                if !isPunctuation(value[p]) { break }
                cursor = p
            }
            return
        }

        while cursor > value.startIndex {
            let p = value.index(before: cursor)
            let ch = value[p]
            if isWhitespace(ch) || isPunctuation(ch) { break }
            cursor = p
        }
    }

    private func moveWordForwards() {
        if cursor == value.endIndex { return }

        // Skip whitespace.
        while cursor < value.endIndex, isWhitespace(value[cursor]) {
            cursor = value.index(after: cursor)
        }
        if cursor == value.endIndex { return }

        if isPunctuation(value[cursor]) {
            while cursor < value.endIndex, isPunctuation(value[cursor]) {
                cursor = value.index(after: cursor)
            }
            return
        }

        while cursor < value.endIndex {
            let ch = value[cursor]
            if isWhitespace(ch) || isPunctuation(ch) { break }
            cursor = value.index(after: cursor)
        }
    }

    private func deleteWordBackward() {
        let old = cursor
        moveWordBackwards()
        let start = cursor
        cursor = old
        value.removeSubrange(start..<cursor)
        cursor = start
    }

    private func handlePaste(_ pastedText: String) {
        // Single-line input: remove newlines.
        let clean = pastedText
            .replacingOccurrences(of: "\r\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        value.insert(contentsOf: clean, at: cursor)
        cursor = value.index(cursor, offsetBy: clean.count, limitedBy: value.endIndex) ?? value.endIndex
    }

    public func render(width: Int) -> [String] {
        let prompt = "> "
        let available = max(1, width - prompt.count)

        // Build a visible window around the cursor.
        let cursorCell = cellOffset(in: value, to: cursor)
        let totalCells = cellWidth(value)

        let visible: (slice: String, cursorInSliceCells: Int) = {
            if totalCells <= available {
                return (value, cursorCell)
            }

            // Keep cursor near center.
            let scrollWidth = (cursor == value.endIndex) ? max(1, available - 1) : available
            let half = scrollWidth / 2

            if cursorCell < half {
                let (s, _) = sliceByCells(value, startCell: 0, maxCells: scrollWidth)
                return (s, cursorCell)
            }
            if cursorCell > totalCells - half {
                let start = max(0, totalCells - scrollWidth)
                let (s, actualStart) = sliceByCells(value, startCell: start, maxCells: scrollWidth)
                return (s, cursorCell - actualStart)
            }
            let start = max(0, cursorCell - half)
            let (s, actualStart) = sliceByCells(value, startCell: start, maxCells: scrollWidth)
            return (s, cursorCell - actualStart)
        }()

        let slice = visible.slice
        let cursorCellsInSlice = visible.cursorInSliceCells

        let (before, at, after) = splitAtCell(slice, cell: cursorCellsInSlice)
        let marker = focused ? ANSI.cursorMarker : ""
        let cursorChar = "\u{001B}[7m" + (at.isEmpty ? " " : at) + "\u{001B}[27m"
        let textWithCursor = before + marker + cursorChar + after

        let visualLen = ANSI.visibleWidth(textWithCursor)
        let pad = visualLen < available ? String(repeating: " ", count: available - visualLen) : ""

        return [prompt + textWithCursor + pad]
    }

    private func cellWidth(_ s: String) -> Int {
        s.reduce(0) { $0 + UnicodeWidth.width(of: $1) }
    }

    private func cellOffset(in s: String, to idx: String.Index) -> Int {
        var w = 0
        var i = s.startIndex
        while i < idx {
            w += UnicodeWidth.width(of: s[i])
            i = s.index(after: i)
        }
        return w
    }

    // Returns substring of up to maxCells starting at startCell, and the actual startCell used
    // (if startCell was in the middle of a wide grapheme, we adjust).
    private func sliceByCells(_ s: String, startCell: Int, maxCells: Int) -> (slice: String, actualStart: Int) {
        let startCell = max(0, startCell)
        var cell = 0
        var i = s.startIndex

        // Move `i` to the first character whose *start* cell is >= startCell.
        while i < s.endIndex {
            let w = UnicodeWidth.width(of: s[i])
            if cell + w <= startCell {
                cell += w
                i = s.index(after: i)
                continue
            }
            break
        }
        let actualStart = cell

        var out = ""
        out.reserveCapacity(min(64, s.count))
        var used = 0
        var j = i
        while j < s.endIndex, used < maxCells {
            let w = UnicodeWidth.width(of: s[j])
            if used + w > maxCells { break }
            out.append(s[j])
            used += w
            j = s.index(after: j)
        }
        return (out, max(0, actualStart))
    }

    private func splitAtCell(_ s: String, cell target: Int) -> (before: String, at: String, after: String) {
        var cell = 0
        var i = s.startIndex
        while i < s.endIndex {
            let w = UnicodeWidth.width(of: s[i])
            if cell + w > target { break }
            cell += w
            i = s.index(after: i)
        }

        let before = String(s[..<i])
        if i == s.endIndex {
            return (before, "", "")
        }
        let at = String(s[i])
        let after = String(s[s.index(after: i)...])
        return (before, at, after)
    }
}
