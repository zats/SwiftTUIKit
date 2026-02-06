import Foundation

public struct DefaultTextStyle: Sendable {
    public var color: (@Sendable (String) -> String)?
    public var bgColor: (@Sendable (String) -> String)?
    public var bold: Bool
    public var italic: Bool
    public var strikethrough: Bool
    public var underline: Bool

    public init(
        color: (@Sendable (String) -> String)? = nil,
        bgColor: (@Sendable (String) -> String)? = nil,
        bold: Bool = false,
        italic: Bool = false,
        strikethrough: Bool = false,
        underline: Bool = false
    ) {
        self.color = color
        self.bgColor = bgColor
        self.bold = bold
        self.italic = italic
        self.strikethrough = strikethrough
        self.underline = underline
    }
}

public struct MarkdownTheme: Sendable {
    public var heading: @Sendable (String) -> String
    public var link: @Sendable (String) -> String
    public var linkUrl: @Sendable (String) -> String
    public var code: @Sendable (String) -> String
    public var codeBlock: @Sendable (String) -> String
    public var codeBlockBorder: @Sendable (String) -> String
    public var quote: @Sendable (String) -> String
    public var quoteBorder: @Sendable (String) -> String
    public var hr: @Sendable (String) -> String
    public var listBullet: @Sendable (String) -> String
    public var bold: @Sendable (String) -> String
    public var italic: @Sendable (String) -> String
    public var strikethrough: @Sendable (String) -> String
    public var underline: @Sendable (String) -> String
    public var highlightCode: (@Sendable (_ code: String, _ lang: String?) -> [String])?
    public var codeBlockIndent: String

    public init(
        heading: @escaping @Sendable (String) -> String = { $0 },
        link: @escaping @Sendable (String) -> String = { $0 },
        linkUrl: @escaping @Sendable (String) -> String = { $0 },
        code: @escaping @Sendable (String) -> String = { $0 },
        codeBlock: @escaping @Sendable (String) -> String = { $0 },
        codeBlockBorder: @escaping @Sendable (String) -> String = { $0 },
        quote: @escaping @Sendable (String) -> String = { $0 },
        quoteBorder: @escaping @Sendable (String) -> String = { $0 },
        hr: @escaping @Sendable (String) -> String = { $0 },
        listBullet: @escaping @Sendable (String) -> String = { $0 },
        bold: @escaping @Sendable (String) -> String = { $0 },
        italic: @escaping @Sendable (String) -> String = { $0 },
        strikethrough: @escaping @Sendable (String) -> String = { $0 },
        underline: @escaping @Sendable (String) -> String = { $0 },
        highlightCode: (@Sendable (_ code: String, _ lang: String?) -> [String])? = nil,
        codeBlockIndent: String = "  "
    ) {
        self.heading = heading
        self.link = link
        self.linkUrl = linkUrl
        self.code = code
        self.codeBlock = codeBlock
        self.codeBlockBorder = codeBlockBorder
        self.quote = quote
        self.quoteBorder = quoteBorder
        self.hr = hr
        self.listBullet = listBullet
        self.bold = bold
        self.italic = italic
        self.strikethrough = strikethrough
        self.underline = underline
        self.highlightCode = highlightCode
        self.codeBlockIndent = codeBlockIndent
    }
}

public final class Markdown: Component, @unchecked Sendable {
    private var text: String
    private var paddingX: Int
    private var paddingY: Int
    private var theme: MarkdownTheme
    private var defaultTextStyle: DefaultTextStyle?

    private var cachedText: String?
    private var cachedWidth: Int?
    private var cachedLines: [String]?

    public init(
        _ text: String,
        paddingX: Int = 0,
        paddingY: Int = 0,
        theme: MarkdownTheme,
        defaultTextStyle: DefaultTextStyle? = nil
    ) {
        self.text = text
        self.paddingX = max(0, paddingX)
        self.paddingY = max(0, paddingY)
        self.theme = theme
        self.defaultTextStyle = defaultTextStyle
    }

    public func setText(_ text: String) {
        self.text = text
        invalidate()
    }

    public func invalidate() {
        cachedText = nil
        cachedWidth = nil
        cachedLines = nil
    }

    public func render(width: Int) -> [String] {
        if cachedText == text, cachedWidth == width, let cachedLines { return cachedLines }

        let w = max(1, width)
        let contentWidth = max(1, w - paddingX * 2)

        let normalized = text.replacingOccurrences(of: "\t", with: "   ")
        if normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cachedText = text
            cachedWidth = width
            cachedLines = []
            return []
        }

        var rendered: [String] = []
        rendered.reserveCapacity(32)

        var inCodeBlock = false
        var codeLang: String?
        var codeBuffer: [String] = []

        func flushCodeBlock() {
            guard !codeBuffer.isEmpty else { return }
            let code = codeBuffer.joined(separator: "\n")
            if let highlight = theme.highlightCode {
                let lines = highlight(code, codeLang)
                for l in lines {
                    rendered.append(theme.codeBlockIndent + l)
                }
            } else {
                for l in codeBuffer {
                    rendered.append(theme.codeBlockIndent + theme.codeBlock(l))
                }
            }
            codeBuffer.removeAll(keepingCapacity: true)
        }

        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            if line.hasPrefix("```") {
                if inCodeBlock {
                    flushCodeBlock()
                    inCodeBlock = false
                    codeLang = nil
                } else {
                    inCodeBlock = true
                    let rest = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    codeLang = rest.isEmpty ? nil : String(rest)
                }
                continue
            }

            if inCodeBlock {
                codeBuffer.append(line)
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                rendered.append("")
                continue
            }

            // Headings.
            if let heading = parseHeading(line) {
                rendered.append(theme.heading(applyDefaultStyle(heading.text)))
                continue
            }

            // HR.
            if isHr(line) {
                rendered.append(theme.hr(String(repeating: "─", count: min(30, contentWidth))))
                continue
            }

            // Quote.
            if line.hasPrefix("> ") {
                let body = String(line.dropFirst(2))
                rendered.append(theme.quoteBorder("│ ") + theme.quote(applyDefaultStyle(parseInline(body))))
                continue
            }

            // Unordered list.
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let body = String(line.dropFirst(2))
                rendered.append(theme.listBullet("• ") + applyDefaultStyle(parseInline(body)))
                continue
            }

            // Ordered list: `N. `
            if let ordered = parseOrderedList(line) {
                rendered.append(theme.listBullet("\(ordered.number). ") + applyDefaultStyle(parseInline(ordered.text)))
                continue
            }

            rendered.append(applyDefaultStyle(parseInline(line)))
        }

        if inCodeBlock {
            flushCodeBlock()
        }

        // Wrap.
        var wrapped: [String] = []
        for line in rendered {
            if isImageLine(line) {
                wrapped.append(line)
            } else {
                wrapped.append(contentsOf: ANSI.wrapTextWithAnsi(line, width: contentWidth))
            }
        }

        // Apply padding and background.
        let leftMargin = String(repeating: " ", count: paddingX)
        let rightMargin = leftMargin

        var padded: [String] = []
        padded.reserveCapacity(wrapped.count + paddingY * 2)

        let bgFn = defaultTextStyle?.bgColor
        func padToWidth(_ s: String) -> String {
            let vw = ANSI.visibleWidth(s)
            if vw >= w { return s }
            return s + String(repeating: " ", count: w - vw)
        }

        let empty = String(repeating: " ", count: w)
        for _ in 0..<paddingY {
            padded.append(bgFn.map { $0(empty) } ?? empty)
        }

        for line in wrapped {
            if isImageLine(line) {
                padded.append(line)
                continue
            }
            let withMargins = leftMargin + line + rightMargin
            let full = padToWidth(withMargins)
            padded.append(bgFn.map { $0(full) } ?? full)
        }

        for _ in 0..<paddingY {
            padded.append(bgFn.map { $0(empty) } ?? empty)
        }

        cachedText = text
        cachedWidth = width
        cachedLines = padded
        return padded
    }

    private func applyDefaultStyle(_ s: String) -> String {
        guard let st = defaultTextStyle else { return s }
        var out = s
        if let color = st.color { out = color(out) }
        if st.bold { out = theme.bold(out) }
        if st.italic { out = theme.italic(out) }
        if st.strikethrough { out = theme.strikethrough(out) }
        if st.underline { out = theme.underline(out) }
        return out
    }

    private func parseInline(_ s: String) -> String {
        // Minimal inline parser:
        // - `code`
        // - **bold**
        // - *italic*
        // - ~~strike~~
        // - [text](url)
        var out = ""
        out.reserveCapacity(s.count + 16)

        var i = s.startIndex

        func take(_ n: Int) -> String.Index {
            s.index(i, offsetBy: n, limitedBy: s.endIndex) ?? s.endIndex
        }

        while i < s.endIndex {
            // Link
            if s[i] == "[", let closeText = s[i...].firstIndex(of: "]") {
                let afterText = s.index(after: closeText)
                if afterText < s.endIndex, s[afterText] == "(", let closeUrl = s[afterText...].firstIndex(of: ")") {
                    let textPart = String(s[s.index(after: i)..<closeText])
                    let urlPart = String(s[s.index(after: afterText)..<closeUrl])
                    let linkText = theme.link(theme.underline(textPart))
                    if textPart == urlPart || (urlPart.hasPrefix("mailto:") && String(urlPart.dropFirst(7)) == textPart) {
                        out += linkText
                    } else {
                        out += linkText + theme.linkUrl(" (\(urlPart))")
                    }
                    i = s.index(after: closeUrl)
                    continue
                }
            }

            // Code span
            if s[i] == "`", let end = s[s.index(after: i)...].firstIndex(of: "`") {
                let code = String(s[s.index(after: i)..<end])
                out += theme.code(code)
                i = s.index(after: end)
                continue
            }

            // Bold
            if s[i...].hasPrefix("**") {
                let start = take(2)
                if let end = s[start...].range(of: "**")?.lowerBound {
                    let body = String(s[start..<end])
                    out += theme.bold(parseInline(body))
                    i = s.index(end, offsetBy: 2)
                    continue
                }
            }

            // Strikethrough
            if s[i...].hasPrefix("~~") {
                let start = take(2)
                if let end = s[start...].range(of: "~~")?.lowerBound {
                    let body = String(s[start..<end])
                    out += theme.strikethrough(parseInline(body))
                    i = s.index(end, offsetBy: 2)
                    continue
                }
            }

            // Italic
            if s[i] == "*" {
                let start = s.index(after: i)
                if let end = s[start...].firstIndex(of: "*") {
                    let body = String(s[start..<end])
                    out += theme.italic(parseInline(body))
                    i = s.index(after: end)
                    continue
                }
            }

            out.append(s[i])
            i = s.index(after: i)
        }

        return out
    }

    private func parseHeading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        var i = line.startIndex
        while i < line.endIndex, line[i] == "#" {
            level += 1
            i = line.index(after: i)
        }
        if level == 0 || level > 6 { return nil }
        if i < line.endIndex, line[i] == " " {
            let text = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
            return (level: level, text: String(text))
        }
        return nil
    }

    private func isHr(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t == "---" || t == "***" || t == "___"
    }

    private func parseOrderedList(_ line: String) -> (number: Int, text: String)? {
        // e.g. "1. hello"
        let chars = Array(line)
        var i = 0
        var n = 0
        var saw = false
        while i < chars.count, let d = chars[i].wholeNumberValue {
            saw = true
            n = n * 10 + d
            i += 1
        }
        guard saw, i + 1 < chars.count, chars[i] == ".", chars[i + 1] == " " else { return nil }
        return (number: n, text: String(chars[(i + 2)...]))
    }
}

