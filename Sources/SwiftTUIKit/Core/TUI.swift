import Foundation

public enum OverlayAnchor: String, Sendable {
    case center
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case topCenter
    case bottomCenter
    case leftCenter
    case rightCenter
}

public struct OverlayMargin: Sendable, Equatable {
    public var top: Int?
    public var right: Int?
    public var bottom: Int?
    public var left: Int?

    public init(top: Int? = nil, right: Int? = nil, bottom: Int? = nil, left: Int? = nil) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }
}

public enum SizeValue: Sendable, Equatable {
    case absolute(Int)
    case percent(Double) // 0...100

    public static func percent(_ p: Int) -> SizeValue { .percent(Double(p)) }
}

public struct OverlayOptions: Sendable {
    public var width: SizeValue?
    public var minWidth: Int?
    public var maxHeight: SizeValue?

    public var anchor: OverlayAnchor?
    public var offsetX: Int?
    public var offsetY: Int?

    public var row: SizeValue?
    public var col: SizeValue?

    public var margin: OverlayMargin?
    public var marginAll: Int?

    public var visible: (@Sendable (_ termWidth: Int, _ termHeight: Int) -> Bool)?

    public init() {}
}

public protocol OverlayHandle: AnyObject, Sendable {
    func hide()
    func setHidden(_ hidden: Bool)
    func isHidden() -> Bool
}

public class Container: Component, @unchecked Sendable {
    var children: [Component] = []

    public init() {}

    func addChild(_ component: Component) {
        children.append(component)
    }

    func removeChild(_ component: Component) {
        children.removeAll { ObjectIdentifier($0) == ObjectIdentifier(component) }
    }

    func clear() {
        children.removeAll(keepingCapacity: false)
    }

    public func render(width: Int) -> [String] {
        var lines: [String] = []
        lines.reserveCapacity(children.count * 2)
        for c in children {
            lines.append(contentsOf: c.render(width: width))
        }
        return lines
    }

    public func invalidate() {
        for c in children { c.invalidate() }
    }
}

public final class TUI: Container, @unchecked Sendable {
    public let terminal: Terminal

    public var onDebug: (@Sendable () -> Void)?

    private let decoder = KeyDecoder()
    private var stopped: Bool = false

    private var focusedComponent: Component?
    private var previousLines: [String] = []
    private var previousWidth: Int = 0

    private var renderScheduled: Bool = false

    // Some terminals (including tmux) do not respond to CSI 16 t with CSI 6 ; h ; w t.
    // Never block user input while waiting; instead, opportunistically strip these replies
    // from the input stream when present.
    private var cellSizeByteBuffer: [UInt8] = []

    private let showHardwareCursor: Bool
    private let clearOnShrink: Bool

    private var fullRedrawCount: Int = 0

    private struct OverlayEntry {
        var component: Component
        var options: OverlayOptions?
        var preFocus: Component?
        var hidden: Bool
    }

    private var overlayStack: [OverlayEntry] = []

    // Optional raw write log (for debugging).
    private var writeLogHandle: FileHandle?

    init(terminal: Terminal = ProcessTerminal()) {
        self.terminal = terminal
        self.showHardwareCursor = ProcessInfo.processInfo.environment["PI_HARDWARE_CURSOR"] == "1"
        self.clearOnShrink = ProcessInfo.processInfo.environment["PI_CLEAR_ON_SHRINK"] == "1"
        super.init()

        if let path = ProcessInfo.processInfo.environment["PI_TUI_WRITE_LOG"], !path.isEmpty {
            FileManager.default.createFile(atPath: path, contents: nil)
            writeLogHandle = FileHandle(forWritingAtPath: path)
        }
    }

    public var fullRedraws: Int { fullRedrawCount }

    public func start() {
        stopped = false

        // Default focus policy: if nothing is explicitly focused, focus the first component
        // in the tree so key handling works out of the box with builder-created hierarchies.
        if focusedComponent == nil {
            if let first = firstComponent(in: self) {
                setFocus(first)
            }
        }

        terminal.start(
            onInput: { [weak self] data in self?.handleInputBytes(data) },
            onResize: { [weak self] in self?.requestRender() }
        )

        terminal.hideCursor()
        terminal.write(ANSI.moveCursor(row: 1, col: 1) + ANSI.clearScreen)

        queryCellSize()
        requestRender(force: true)
    }

    public func stop() {
        stopped = true
        terminal.write(ANSI.sgrReset + ANSI.osc8Reset)
        terminal.showCursor()
        terminal.stop()
    }

    public func setFocus(_ component: Component?) {
        if let old = focusedComponent as? Focusable {
            old.focused = false
        }
        focusedComponent = component
        if let new = component as? Focusable {
            new.focused = true
        }
    }

    private func firstComponent(in root: Component) -> Component? {
        if let container = root as? Container {
            for child in container.children {
                if let found = firstComponent(in: child) { return found }
            }
            return container.children.first
        }
        return root
    }

    // MARK: - Overlays

    public func hasOverlay() -> Bool {
        overlayStack.contains { isOverlayVisible($0) }
    }

    public func hideOverlay() {
        guard let overlay = overlayStack.popLast() else { return }
        let topVisible = topmostVisibleOverlay()
        setFocus(topVisible?.component ?? overlay.preFocus)
        requestRender()
    }

    public func showOverlay(_ component: Component, options: OverlayOptions? = nil) -> OverlayHandle {
        let entry = OverlayEntry(component: component, options: options, preFocus: focusedComponent, hidden: false)
        overlayStack.append(entry)
        if isOverlayVisible(entry) {
            setFocus(component)
        }
        terminal.hideCursor()
        requestRender()

        final class Handle: OverlayHandle, @unchecked Sendable {
            private weak var tui: TUI?
            private let id: ObjectIdentifier

            init(tui: TUI, component: Component) {
                self.tui = tui
                self.id = ObjectIdentifier(component)
            }

            func hide() {
                guard let tui else { return }
                tui.overlayStack.removeAll { ObjectIdentifier($0.component) == id }
                // Restore focus to top visible overlay or previous focus.
                let topVisible = tui.topmostVisibleOverlay()
                if let topVisible {
                    tui.setFocus(topVisible.component)
                } else {
                    // best effort: clear focus
                    tui.setFocus(nil)
                }
                tui.requestRender()
            }

            func setHidden(_ hidden: Bool) {
                guard let tui else { return }
                for i in tui.overlayStack.indices {
                    if ObjectIdentifier(tui.overlayStack[i].component) == id {
                        tui.overlayStack[i].hidden = hidden
                    }
                }
                tui.requestRender()
            }

            func isHidden() -> Bool {
                guard let tui else { return true }
                for e in tui.overlayStack where ObjectIdentifier(e.component) == id {
                    return e.hidden
                }
                return true
            }
        }

        return Handle(tui: self, component: component)
    }

    private func isOverlayVisible(_ entry: OverlayEntry) -> Bool {
        if entry.hidden { return false }
        if let visible = entry.options?.visible {
            return visible(terminal.columns, terminal.rows)
        }
        return true
    }

    private func topmostVisibleOverlay() -> OverlayEntry? {
        for e in overlayStack.reversed() where isOverlayVisible(e) {
            return e
        }
        return nil
    }

    // MARK: - Rendering

    public func requestRender(force: Bool = false) {
        if force {
            previousLines = []
            previousWidth = -1
        }
        if renderScheduled { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.renderScheduled = false
            self.doRender()
        }
    }

    private func doRender() {
        if stopped { return }

        let width = max(1, terminal.columns)
        let height = max(1, terminal.rows)

        // Base lines.
        var lines = render(width: width)

        // Apply overlays (topmost last).
        for entry in overlayStack where isOverlayVisible(entry) {
            lines = applyOverlay(base: lines, overlay: entry.component, options: entry.options, termWidth: width, termHeight: height)
        }

        // Ensure non-empty for cursor math.
        if lines.isEmpty { lines = [""] }

        // Find cursor marker position (IME) and strip it.
        var cursorPos: (row: Int, col: Int)?
        for i in lines.indices {
            if let range = lines[i].range(of: ANSI.cursorMarker) {
                let prefix = String(lines[i][..<range.lowerBound])
                let col = ANSI.visibleWidth(prefix) + 1
                lines[i].removeSubrange(range)
                cursorPos = (row: i + 1, col: col)
                break
            }
        }

        // Enforce width: truncate lines that overflow.
        var rendered: [String] = []
        rendered.reserveCapacity(lines.count)
        for l in lines {
            if ANSI.visibleWidth(l) > width {
                rendered.append(ANSI.truncateToWidth(l, width: width, ellipsis: ""))
            } else {
                rendered.append(l)
            }
        }
        // Match pi-mono behavior: reset styling and hyperlinks at the end of each line,
        // so component output can't leak into the next line.
        rendered = rendered.map { $0 + ANSI.sgrReset + ANSI.osc8Reset }

        // Diff render.
        let widthChanged = (previousWidth != width)
        let firstDiff = firstDifferentLineIndex(a: previousLines, b: rendered) ?? (widthChanged ? 0 : nil)
        let needsFull = widthChanged || firstDiff == 0 || (clearOnShrink && rendered.count < previousLines.count)

        var out = ""
        out.reserveCapacity(4096)
        out += ANSI.syncOutputOn

        if needsFull {
            fullRedrawCount += 1
            out += ANSI.moveCursor(row: 1, col: 1)
            out += ANSI.clearScreen
            for l in rendered {
                out += "\r" + l + "\r\n"
            }
            out += ANSI.clearFromCursor
        } else if let firstDiff {
            out += ANSI.moveCursor(row: firstDiff + 1, col: 1)
            out += ANSI.clearFromCursor
            for idx in firstDiff..<rendered.count {
                out += "\r" + rendered[idx] + "\r\n"
            }
            out += ANSI.clearFromCursor
        } else {
            // No changes; still update cursor visibility/position.
        }

        out += ANSI.syncOutputOff

        write(out)

        // Hardware cursor.
        if showHardwareCursor, let cursorPos {
            write(ANSI.moveCursor(row: cursorPos.row, col: cursorPos.col) + ANSI.showCursor)
        } else {
            write(ANSI.hideCursor)
        }

        previousLines = rendered
        previousWidth = width
    }

    private func write(_ s: String) {
        terminal.write(s)
        if let h = writeLogHandle, let d = s.data(using: .utf8) {
            h.write(d)
        }
    }

    private func firstDifferentLineIndex(a: [String], b: [String]) -> Int? {
        let n = min(a.count, b.count)
        for i in 0..<n {
            if a[i] != b[i] { return i }
        }
        if a.count != b.count { return n }
        return nil
    }

    // MARK: - Overlay Composition

    private func applyOverlay(base: [String], overlay: Component, options: OverlayOptions?, termWidth: Int, termHeight: Int) -> [String] {
        let overlayWidth = resolveSize(options?.width, reference: termWidth) ?? min(80, termWidth)
        let content = overlay.render(width: overlayWidth)
        let overlayHeight = content.count

        let layout = resolveOverlayLayout(options: options, overlayHeight: overlayHeight, termWidth: termWidth, termHeight: termHeight)
        let row0 = layout.row
        let col0 = layout.col
        let maxH = layout.maxHeight

        let clipped: [String] = {
            if let maxH {
                return Array(content.prefix(maxH))
            }
            return content
        }()

        var out = base
        if out.count < termHeight {
            out.append(contentsOf: Array(repeating: "", count: termHeight - out.count))
        }

        for (i, line) in clipped.enumerated() {
            let targetRow = row0 + i
            if targetRow < 0 || targetRow >= out.count { continue }

            var baseLine = out[targetRow]
            // Ensure base line is wide enough (pad with spaces).
            let baseW = ANSI.visibleWidth(baseLine)
            if baseW < termWidth {
                baseLine += String(repeating: " ", count: termWidth - baseW)
            }

            let left = ANSI.sliceByColumn(baseLine, startCol: 0, length: col0)
            let mid = ANSI.sliceByColumn(line, startCol: 0, length: min(overlayWidth, termWidth - col0))
            let rightStart = col0 + ANSI.visibleWidth(mid)
            let rightLen = max(0, termWidth - rightStart)
            let right = rightLen > 0 ? ANSI.sliceByColumn(baseLine, startCol: rightStart, length: rightLen) : ""

            out[targetRow] = left + mid + right
        }

        return out
    }

    private func resolveSize(_ value: SizeValue?, reference: Int) -> Int? {
        guard let value else { return nil }
        switch value {
        case let .absolute(n):
            return n
        case let .percent(p):
            return Int(Double(reference) * (p / 100.0))
        }
    }

    private func resolveOverlayLayout(
        options: OverlayOptions?,
        overlayHeight: Int,
        termWidth: Int,
        termHeight: Int
    ) -> (width: Int, row: Int, col: Int, maxHeight: Int?) {
        let opt = options ?? OverlayOptions()

        let margin: OverlayMargin = {
            if let all = opt.marginAll {
                return OverlayMargin(top: all, right: all, bottom: all, left: all)
            }
            return opt.margin ?? OverlayMargin()
        }()

        let mTop = max(0, margin.top ?? 0)
        let mRight = max(0, margin.right ?? 0)
        let mBottom = max(0, margin.bottom ?? 0)
        let mLeft = max(0, margin.left ?? 0)

        let availW = max(1, termWidth - mLeft - mRight)
        let availH = max(1, termHeight - mTop - mBottom)

        var width = resolveSize(opt.width, reference: termWidth) ?? min(80, availW)
        if let minW = opt.minWidth { width = max(width, minW) }
        width = max(1, min(width, availW))

        var maxH = resolveSize(opt.maxHeight, reference: termHeight)
        if let mh = maxH { maxH = max(1, min(mh, availH)) }

        let effectiveH = maxH.map { min(overlayHeight, $0) } ?? overlayHeight

        func anchorRow(_ a: OverlayAnchor) -> Int {
            switch a {
            case .topLeft, .topCenter, .topRight:
                return mTop
            case .bottomLeft, .bottomCenter, .bottomRight:
                return mTop + max(0, availH - effectiveH)
            case .leftCenter, .rightCenter, .center:
                return mTop + max(0, (availH - effectiveH) / 2)
            }
        }

        func anchorCol(_ a: OverlayAnchor) -> Int {
            switch a {
            case .topLeft, .leftCenter, .bottomLeft:
                return mLeft
            case .topRight, .rightCenter, .bottomRight:
                return mLeft + max(0, availW - width)
            case .topCenter, .bottomCenter, .center:
                return mLeft + max(0, (availW - width) / 2)
            }
        }

        let anchor = opt.anchor ?? .center
        var row = anchorRow(anchor)
        var col = anchorCol(anchor)

        if let r = opt.row {
            if case let .absolute(n) = r {
                row = n
            } else if case let .percent(p) = r {
                let maxRow = max(0, availH - effectiveH)
                row = mTop + Int(Double(maxRow) * (p / 100.0))
            }
        }

        if let c = opt.col {
            if case let .absolute(n) = c {
                col = n
            } else if case let .percent(p) = c {
                let maxCol = max(0, availW - width)
                col = mLeft + Int(Double(maxCol) * (p / 100.0))
            }
        }

        row += opt.offsetY ?? 0
        col += opt.offsetX ?? 0

        row = max(mTop, min(row, termHeight - mBottom - effectiveH))
        col = max(mLeft, min(col, termWidth - mRight - width))

        return (width, row, col, maxH)
    }

    // MARK: - Input

    private func findSequence(in haystack: [UInt8], needle: [UInt8]) -> Int? {
        if needle.isEmpty { return nil }
        if haystack.count < needle.count { return nil }
        if needle.count == 1 {
            return haystack.firstIndex(of: needle[0])
        }
        for i in 0...(haystack.count - needle.count) {
            if haystack[i] != needle[0] { continue }
            var ok = true
            for j in 1..<needle.count {
                if haystack[i + j] != needle[j] { ok = false; break }
            }
            if ok { return i }
        }
        return nil
    }

    private func queryCellSize() {
        // CSI 16 t -> response CSI 6 ; height ; width t
        terminal.write("\u{001B}[16t")
    }

    private func handleInputBytes(_ data: Data) {
        let filtered = stripCellSizeReplies(from: data)

        let events = decoder.feed(filtered)
        for ev in events {
            // Debug key: shift+ctrl+d
            if case let .key(k) = ev,
               k.modifiers.contains(.ctrl),
               k.modifiers.contains(.shift),
               case let .char(c) = k.key,
               String(c).lowercased() == "d" {
                onDebug?()
                continue
            }

            // If focused component is an overlay, ensure it is still visible.
            if let f = focusedComponent {
                if overlayStack.contains(where: { ObjectIdentifier($0.component) == ObjectIdentifier(f) }),
                   topmostVisibleOverlay()?.component !== f {
                    if let top = topmostVisibleOverlay() {
                        setFocus(top.component)
                    }
                }
            }

            focusedComponent?.handleInput(ev)
            requestRender()
        }
    }

    private func stripCellSizeReplies(from data: Data) -> Data {
        // Reply pattern: ESC [ 6 ; <height> ; <width> t
        // Bytes prefix: 0x1b 0x5b 0x36 0x3b
        let prefix: [UInt8] = [0x1b, 0x5b, 0x36, 0x3b]

        var buf = cellSizeByteBuffer
        buf.append(contentsOf: data)

        var out: [UInt8] = []
        out.reserveCapacity(buf.count)

        func longestSuffixMatchingPrefixStart(_ bytes: [UInt8]) -> Int {
            if bytes.isEmpty { return 0 }
            let maxK = min(prefix.count - 1, bytes.count)
            if maxK <= 0 { return 0 }
            for k in stride(from: maxK, through: 1, by: -1) {
                let suf = bytes.suffix(k)
                if Array(suf) == Array(prefix.prefix(k)) {
                    return k
                }
            }
            return 0
        }

        while true {
            guard let start = findSequence(in: buf, needle: prefix) else {
                let keep = longestSuffixMatchingPrefixStart(buf)
                if keep > 0 {
                    out.append(contentsOf: buf.prefix(buf.count - keep))
                    buf = Array(buf.suffix(keep))
                } else {
                    out.append(contentsOf: buf)
                    buf.removeAll(keepingCapacity: false)
                }
                break
            }

            if start > 0 {
                out.append(contentsOf: buf.prefix(start))
                buf.removeFirst(start)
            }

            // buf now begins with prefix. Find terminating 't' (0x74).
            guard let endRel = buf.firstIndex(of: 0x74) else {
                // Incomplete reply; keep it buffered.
                break
            }

            let seq = Array(buf.prefix(endRel + 1))
            buf.removeFirst(endRel + 1)

            if let dims = parseCellSizeResponseBytes(seq) {
                setCellDimensions(dims)
            }
        }

        cellSizeByteBuffer = buf
        return Data(out)
    }

    private func parseCellSizeResponseBytes(_ seq: [UInt8]) -> CellDimensions? {
        // Expected: ESC [ 6 ; <heightPx> ; <widthPx> t
        guard seq.count >= 8 else { return nil }
        guard seq[0] == 0x1b, seq[1] == 0x5b, seq[2] == 0x36, seq[3] == 0x3b, seq.last == 0x74 else { return nil }

        let body = seq[4..<(seq.count - 1)]
        let s = String(decoding: body, as: UTF8.self)
        let parts = s.split(separator: ";")
        guard parts.count == 2 else { return nil }
        guard let h = Int(parts[0]), let w = Int(parts[1]) else { return nil }

        let cols = max(1, terminal.columns)
        let rows = max(1, terminal.rows)

        let cellW = max(1, w / cols)
        let cellH = max(1, h / rows)
        return CellDimensions(widthPx: cellW, heightPx: cellH)
    }
}
