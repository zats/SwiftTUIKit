import Foundation

public struct EditorTheme: Sendable {
    public var borderColor: @Sendable (String) -> String
    public var selectList: SelectListTheme

    public init(
        borderColor: @escaping @Sendable (String) -> String = { $0 },
        selectList: SelectListTheme = .init()
    ) {
        self.borderColor = borderColor
        self.selectList = selectList
    }
}

public struct EditorOptions: Sendable, Equatable {
    public var paddingX: Int
    public var autocompleteMaxVisible: Int

    public init(paddingX: Int = 0, autocompleteMaxVisible: Int = 5) {
        self.paddingX = max(0, paddingX)
        self.autocompleteMaxVisible = max(3, min(20, autocompleteMaxVisible))
    }
}

public final class Editor: Component, Focusable, @unchecked Sendable {
    private struct State {
        var lines: [String]
        var cursorLine: Int
        var cursorCol: Int // Character offset within line
    }

    public var focused: Bool = false

    private let tui: TUI
    private let theme: EditorTheme
    private var paddingX: Int
    private var lastWidth: Int = 80

    private var state: State = .init(lines: [""], cursorLine: 0, cursorCol: 0)

    // Autocomplete
    private var autocompleteProvider: AutocompleteProvider?
    private var autocompleteList: SelectList?
    private var autocompletePrefix: String = ""
    private var autocompleteMaxVisible: Int
    private var autocompleteForced: Bool = false
    private var autocompleteItems: [AutocompleteItem] = []

    // History (single-line use-cases)
    private var history: [String] = []
    private var historyIndex: Int = -1 // -1 = not browsing, 0 = most recent

    public var borderColor: (@Sendable (String) -> String)

    public var onSubmit: (@Sendable (String) -> Void)?
    public var onChange: (@Sendable (String) -> Void)?
    public var disableSubmit: Bool = false

    public init(tui: TUI, theme: EditorTheme, options: EditorOptions = .init()) {
        self.tui = tui
        self.theme = theme
        self.paddingX = options.paddingX
        self.autocompleteMaxVisible = options.autocompleteMaxVisible
        self.borderColor = theme.borderColor
    }

    public func setPaddingX(_ padding: Int) {
        let p = max(0, padding)
        if p == paddingX { return }
        paddingX = p
        tui.requestRender()
    }

    public func getPaddingX() -> Int { paddingX }

    public func setAutocompleteMaxVisible(_ n: Int) {
        let v = max(3, min(20, n))
        if v == autocompleteMaxVisible { return }
        autocompleteMaxVisible = v
        if autocompleteList != nil, !autocompleteItems.isEmpty {
            let items = autocompleteItems.map { SelectItem(value: $0.value, label: $0.label, description: $0.description) }
            let list = SelectList(items: items, maxVisible: v, theme: theme.selectList)
            list.onSelect = { [weak self] _ in self?.applyAutocompleteSelection() }
            list.onCancel = { [weak self] in self?.hideAutocomplete() }
            autocompleteList = list
        }
        tui.requestRender()
    }

    public func getAutocompleteMaxVisible() -> Int { autocompleteMaxVisible }

    public func setAutocompleteProvider(_ provider: AutocompleteProvider) {
        autocompleteProvider = provider
    }

    public func addToHistory(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        if history.first == trimmed { return }
        history.insert(trimmed, at: 0)
        if history.count > 200 { history.removeLast(history.count - 200) }
    }

    public func getText() -> String {
        state.lines.joined(separator: "\n")
    }

    public func setText(_ text: String) {
        let parts = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        state.lines = parts.isEmpty ? [""] : parts
        state.cursorLine = max(0, state.lines.count - 1)
        state.cursorCol = state.lines[state.cursorLine].count
        historyIndex = -1
        autocompleteForced = false
        updateAutocomplete()
        tui.requestRender()
    }

    public func clear() {
        state = .init(lines: [""], cursorLine: 0, cursorCol: 0)
        historyIndex = -1
        autocompleteForced = false
        hideAutocomplete()
        onChange?("")
        tui.requestRender()
    }

    public func invalidate() {}

    public func render(width: Int) -> [String] {
        lastWidth = max(1, width)

        let w = max(4, width)
        let innerWidth = max(1, w - 2 - (paddingX * 2))

        // Clamp cursor.
        state.cursorLine = max(0, min(state.cursorLine, state.lines.count - 1))
        state.cursorCol = max(0, min(state.cursorCol, state.lines[state.cursorLine].count))

        var out: [String] = []
        out.reserveCapacity(state.lines.count + 4)

        let top = "┌" + String(repeating: "─", count: max(0, w - 2)) + "┐"
        out.append(borderColor(top))

        for lineIdx in 0..<state.lines.count {
            let content = renderLine(lineIdx: lineIdx, contentWidth: innerWidth)
            let padded = String(repeating: " ", count: paddingX) + content + String(repeating: " ", count: paddingX)
            let full = padToWidth(padded, width: w - 2)
            out.append(borderColor("│") + full + borderColor("│"))
        }

        let bottom = "└" + String(repeating: "─", count: max(0, w - 2)) + "┘"
        out.append(borderColor(bottom))

        if let list = autocompleteList {
            out.append("")
            out.append(contentsOf: list.render(width: w))
        }

        return out
    }

    private func renderLine(lineIdx: Int, contentWidth: Int) -> String {
        let line = state.lines[lineIdx]
        if lineIdx != state.cursorLine || !focused {
            return ANSI.truncateToWidth(line, width: contentWidth, ellipsis: "")
        }

        // Cursor line: build a window around the cursor and render a fake cursor.
        let cursorIndex = indexAtCharOffset(line, offset: state.cursorCol)
        let cursorCell = cellOffset(in: line, to: cursorIndex)
        let totalCells = cellWidth(line)

        let slice: (text: String, cursorInSliceCells: Int) = {
            if totalCells <= contentWidth {
                return (line, cursorCell)
            }
            let start = max(0, cursorCell - (contentWidth / 2))
            let maxStart = max(0, totalCells - contentWidth)
            let actualStart = min(start, maxStart)
            let window = sliceWindow(line, startCell: actualStart, maxCells: contentWidth)
            return (window.slice, cursorCell - window.startCell)
        }()

        let split = splitAtCell(slice.text, cell: slice.cursorInSliceCells)
        let marker = focused ? ANSI.cursorMarker : ""
        let cursorChar = split.at.isEmpty ? " " : split.at
        let fakeCursor = marker + "\u{001B}[7m" + cursorChar + "\u{001B}[27m"

        let rendered = split.before + fakeCursor + split.after
        return ANSI.truncateToWidth(rendered, width: contentWidth, ellipsis: "")
    }

    private func padToWidth(_ s: String, width: Int) -> String {
        let w = ANSI.visibleWidth(s)
        if w >= width { return s }
        return s + String(repeating: " ", count: width - w)
    }

    // MARK: - Input

    public func handleInput(_ event: InputEvent) {
        switch event {
        case let .paste(s):
            insertPaste(s)
        case let .key(k):
            handleKey(k)
        default:
            break
        }
    }

    private func handleKey(_ k: KeyEvent) {
        let kb = getEditorKeybindings()

        // Autocomplete interaction takes precedence.
        if let list = autocompleteList {
            if kb.matches(k, action: .selectUp)
                || kb.matches(k, action: .selectDown)
                || kb.matches(k, action: .selectConfirm)
                || kb.matches(k, action: .selectCancel)
            {
                if kb.matches(k, action: .selectConfirm) {
                    applyAutocompleteSelection()
                } else if kb.matches(k, action: .selectCancel) {
                    hideAutocomplete()
                } else {
                    list.handleInput(.key(k))
                }
                tui.requestRender()
                return
            }
        }

        if kb.matches(k, action: .submit) || k.key == .enter {
            if disableSubmit {
                return
            }
            let text = getText()
            onSubmit?(text)
            addToHistory(text)
            clear()
            return
        }

        if kb.matches(k, action: .newLine) {
            insertNewLine()
            onChange?(getText())
            updateAutocomplete()
            return
        }

        if kb.matches(k, action: .tab) {
            autocompleteForced = true
            updateAutocomplete()
            tui.requestRender()
            return
        }

        if kb.matches(k, action: .deleteCharBackward) || k.key == .backspace {
            deleteBackward()
            onChange?(getText())
            updateAutocomplete()
            return
        }

        if kb.matches(k, action: .deleteCharForward) || k.key == .delete {
            deleteForward()
            onChange?(getText())
            updateAutocomplete()
            return
        }

        if kb.matches(k, action: .deleteToLineStart) {
            let line = state.lines[state.cursorLine]
            let idx = indexAtCharOffset(line, offset: state.cursorCol)
            state.lines[state.cursorLine].removeSubrange(line.startIndex..<idx)
            state.cursorCol = 0
            onChange?(getText())
            updateAutocomplete()
            return
        }

        if kb.matches(k, action: .deleteToLineEnd) {
            let line = state.lines[state.cursorLine]
            let idx = indexAtCharOffset(line, offset: state.cursorCol)
            state.lines[state.cursorLine].removeSubrange(idx..<line.endIndex)
            onChange?(getText())
            updateAutocomplete()
            return
        }

        if kb.matches(k, action: .cursorLeft) || k.key == .left {
            moveLeft()
            hideAutocompleteIfNotForced()
            tui.requestRender()
            return
        }

        if kb.matches(k, action: .cursorRight) || k.key == .right {
            moveRight()
            hideAutocompleteIfNotForced()
            tui.requestRender()
            return
        }

        if kb.matches(k, action: .cursorLineStart) || k.key == .home {
            state.cursorCol = 0
            hideAutocompleteIfNotForced()
            tui.requestRender()
            return
        }

        if kb.matches(k, action: .cursorLineEnd) || k.key == .end {
            state.cursorCol = state.lines[state.cursorLine].count
            hideAutocompleteIfNotForced()
            tui.requestRender()
            return
        }

        if kb.matches(k, action: .cursorUp) || k.key == .up {
            if state.lines.count == 1, !history.isEmpty {
                browseHistory(delta: 1)
            } else {
                state.cursorLine = max(0, state.cursorLine - 1)
                state.cursorCol = min(state.cursorCol, state.lines[state.cursorLine].count)
            }
            hideAutocompleteIfNotForced()
            tui.requestRender()
            return
        }

        if kb.matches(k, action: .cursorDown) || k.key == .down {
            if state.lines.count == 1, !history.isEmpty {
                browseHistory(delta: -1)
            } else {
                state.cursorLine = min(state.lines.count - 1, state.cursorLine + 1)
                state.cursorCol = min(state.cursorCol, state.lines[state.cursorLine].count)
            }
            hideAutocompleteIfNotForced()
            tui.requestRender()
            return
        }

        if case let .char(c) = k.key, k.modifiers.isEmpty || k.modifiers == [.alt] {
            if isPrintable(c) {
                insertChar(c)
                onChange?(getText())
                updateAutocomplete()
            }
            return
        }
    }

    private func browseHistory(delta: Int) {
        // delta: +1 older (up), -1 newer (down)
        if delta > 0 {
            let next = min(history.count - 1, historyIndex + 1)
            if next == historyIndex { return }
            historyIndex = next
            setText(history[historyIndex])
            return
        }

        // Newer.
        if historyIndex <= 0 {
            historyIndex = -1
            setText("")
            return
        }
        historyIndex -= 1
        setText(history[historyIndex])
    }

    private func insertChar(_ c: Character) {
        let line = state.lines[state.cursorLine]
        let idx = indexAtCharOffset(line, offset: state.cursorCol)
        state.lines[state.cursorLine].insert(c, at: idx)
        state.cursorCol += 1
        autocompleteForced = false
    }

    private func insertPaste(_ pasted: String) {
        let normalized = pasted.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let parts = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if parts.isEmpty { return }

        let line = state.lines[state.cursorLine]
        let idx = indexAtCharOffset(line, offset: state.cursorCol)
        let before = String(line[..<idx])
        let after = String(line[idx...])

        if parts.count == 1 {
            state.lines[state.cursorLine] = before + parts[0] + after
            state.cursorCol += parts[0].count
        } else {
            var newLines: [String] = []
            newLines.reserveCapacity(state.lines.count + parts.count)
            newLines.append(contentsOf: state.lines.prefix(state.cursorLine))
            newLines.append(before + parts[0])
            if parts.count > 2 {
                newLines.append(contentsOf: parts[1..<(parts.count - 1)])
            }
            newLines.append(parts.last! + after)
            newLines.append(contentsOf: state.lines.suffix(from: state.cursorLine + 1))
            state.lines = newLines
            state.cursorLine += parts.count - 1
            state.cursorCol = parts.last!.count
        }

        autocompleteForced = false
        onChange?(getText())
        updateAutocomplete()
        tui.requestRender()
    }

    private func insertNewLine() {
        let line = state.lines[state.cursorLine]
        let idx = indexAtCharOffset(line, offset: state.cursorCol)
        let before = String(line[..<idx])
        let after = String(line[idx...])
        state.lines[state.cursorLine] = before
        state.lines.insert(after, at: state.cursorLine + 1)
        state.cursorLine += 1
        state.cursorCol = 0
        autocompleteForced = false
        hideAutocomplete()
    }

    private func deleteBackward() {
        if state.cursorCol == 0 {
            if state.cursorLine == 0 { return }
            // Join with previous line.
            let prev = state.lines[state.cursorLine - 1]
            let cur = state.lines[state.cursorLine]
            state.cursorCol = prev.count
            state.lines[state.cursorLine - 1] = prev + cur
            state.lines.remove(at: state.cursorLine)
            state.cursorLine -= 1
            autocompleteForced = false
            return
        }
        let line = state.lines[state.cursorLine]
        let idx = indexAtCharOffset(line, offset: state.cursorCol)
        let prev = line.index(before: idx)
        state.lines[state.cursorLine].removeSubrange(prev..<idx)
        state.cursorCol -= 1
        autocompleteForced = false
    }

    private func deleteForward() {
        let line = state.lines[state.cursorLine]
        if state.cursorCol >= line.count {
            if state.cursorLine >= state.lines.count - 1 { return }
            // Join with next line.
            let next = state.lines[state.cursorLine + 1]
            state.lines[state.cursorLine] = line + next
            state.lines.remove(at: state.cursorLine + 1)
            autocompleteForced = false
            return
        }
        let idx = indexAtCharOffset(line, offset: state.cursorCol)
        let next = line.index(after: idx)
        state.lines[state.cursorLine].removeSubrange(idx..<next)
        autocompleteForced = false
    }

    private func moveLeft() {
        if state.cursorCol > 0 {
            state.cursorCol -= 1
            return
        }
        if state.cursorLine > 0 {
            state.cursorLine -= 1
            state.cursorCol = state.lines[state.cursorLine].count
        }
    }

    private func moveRight() {
        let line = state.lines[state.cursorLine]
        if state.cursorCol < line.count {
            state.cursorCol += 1
            return
        }
        if state.cursorLine < state.lines.count - 1 {
            state.cursorLine += 1
            state.cursorCol = 0
        }
    }

    private func isPrintable(_ c: Character) -> Bool {
        for s in String(c).unicodeScalars {
            if s.value < 32 || s.value == 0x7F || (s.value >= 0x80 && s.value <= 0x9F) {
                return false
            }
        }
        return true
    }

    // MARK: - Autocomplete

    private func updateAutocomplete() {
        guard let provider = autocompleteProvider else {
            hideAutocomplete()
            return
        }

        let sug = provider.getSuggestions(lines: state.lines, cursorLine: state.cursorLine, cursorCol: state.cursorCol)
        if let sug, (!sug.items.isEmpty) {
            autocompletePrefix = sug.prefix
            autocompleteItems = sug.items
            if let list = autocompleteList {
                list.setItems(sug.items.map { SelectItem(value: $0.value, label: $0.label, description: $0.description) })
            } else {
                let items = sug.items.map { SelectItem(value: $0.value, label: $0.label, description: $0.description) }
                let list = SelectList(items: items, maxVisible: autocompleteMaxVisible, theme: theme.selectList)
                list.onSelect = { [weak self] _ in self?.applyAutocompleteSelection() }
                list.onCancel = { [weak self] in self?.hideAutocomplete() }
                autocompleteList = list
            }
            tui.requestRender()
            return
        }

        if autocompleteForced {
            // Keep showing empty state off (matches TS: no list if no items).
            hideAutocomplete()
        } else {
            hideAutocomplete()
        }
    }

    private func applyAutocompleteSelection() {
        guard let provider = autocompleteProvider else { return }
        guard let list = autocompleteList else { return }
        guard let selected = list.getSelectedItem() else { return }

        let item = AutocompleteItem(value: selected.value, label: selected.label, description: selected.description)
        let applied = provider.applyCompletion(
            lines: state.lines,
            cursorLine: state.cursorLine,
            cursorCol: state.cursorCol,
            item: item,
            prefix: autocompletePrefix
        )

        state.lines = applied.lines.isEmpty ? [""] : applied.lines
        state.cursorLine = applied.cursorLine
        state.cursorCol = applied.cursorCol

        autocompleteForced = false
        hideAutocomplete()
        onChange?(getText())
        tui.requestRender()
    }

    private func hideAutocompleteIfNotForced() {
        if autocompleteForced { return }
        hideAutocomplete()
    }

    private func hideAutocomplete() {
        autocompleteList = nil
        autocompletePrefix = ""
        autocompleteForced = false
        autocompleteItems = []
    }

    // MARK: - Cell Width Helpers (copied from Input)

    private func cellWidth(_ s: String) -> Int {
        var w = 0
        for ch in s { w += UnicodeWidth.width(of: ch) }
        return w
    }

    private func cellOffset(in s: String, to index: String.Index) -> Int {
        var cell = 0
        var i = s.startIndex
        while i < index, i < s.endIndex {
            cell += UnicodeWidth.width(of: s[i])
            i = s.index(after: i)
        }
        return cell
    }

    private func sliceWindow(_ s: String, startCell: Int, maxCells: Int) -> (slice: String, startCell: Int) {
        if s.isEmpty { return ("", 0) }
        let startCell = max(0, startCell)

        var cell = 0
        var i = s.startIndex
        while i < s.endIndex {
            let w = UnicodeWidth.width(of: s[i])
            if cell + w > startCell {
                break
            }
            cell += w
            i = s.index(after: i)
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

    private func indexAtCharOffset(_ s: String, offset: Int) -> String.Index {
        s.index(s.startIndex, offsetBy: max(0, offset), limitedBy: s.endIndex) ?? s.endIndex
    }
}
