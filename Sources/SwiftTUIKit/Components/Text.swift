import Foundation

public final class Text: Component, @unchecked Sendable {
    private var text: String
    private var paddingX: Int
    private var paddingY: Int
    private var bgFn: ((String) -> String)?

    private var cachedWidth: Int?
    private var cachedLines: [String]?

    public init(_ text: String, paddingX: Int = 1, paddingY: Int = 1, background: ((String) -> String)? = nil) {
        self.text = text
        self.paddingX = max(0, paddingX)
        self.paddingY = max(0, paddingY)
        self.bgFn = background
    }

    public func setText(_ text: String) {
        if self.text == text { return }
        self.text = text
        invalidate()
    }

    public func setBackground(_ fn: ((String) -> String)?) {
        bgFn = fn
        invalidate()
    }

    public func invalidate() {
        cachedWidth = nil
        cachedLines = nil
    }

    public func render(width: Int) -> [String] {
        if cachedWidth == width, let cachedLines { return cachedLines }
        let w = max(0, width)

        let innerWidth = max(1, w - paddingX * 2)
        let wrapped = ANSI.wrapTextWithAnsi(text, width: innerWidth)

        var out: [String] = []
        out.reserveCapacity(wrapped.count + paddingY * 2)

        for _ in 0..<paddingY { out.append("") }
        for line in wrapped {
            let padded = String(repeating: " ", count: paddingX) + line + String(repeating: " ", count: paddingX)
            out.append(padToWidth(padded, width: w))
        }
        for _ in 0..<paddingY { out.append("") }

        if let bgFn {
            out = out.map { bgFn(padToWidth($0, width: w)) }
        }

        cachedWidth = width
        cachedLines = out
        return out
    }

    private func padToWidth(_ s: String, width: Int) -> String {
        let w = ANSI.visibleWidth(s)
        if w >= width { return s }
        return s + String(repeating: " ", count: width - w)
    }
}

