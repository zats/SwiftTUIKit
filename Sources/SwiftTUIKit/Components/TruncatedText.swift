import Foundation

public final class TruncatedText: Component, @unchecked Sendable {
    private var text: String
    private var paddingX: Int
    private var paddingY: Int

    private var cachedWidth: Int?
    private var cachedLines: [String]?

    public init(_ text: String, paddingX: Int = 0, paddingY: Int = 0) {
        self.text = text
        self.paddingX = max(0, paddingX)
        self.paddingY = max(0, paddingY)
    }

    public func setText(_ text: String) {
        if self.text == text { return }
        self.text = text
        invalidate()
    }

    public func invalidate() {
        cachedWidth = nil
        cachedLines = nil
    }

    public func render(width: Int) -> [String] {
        if cachedWidth == width, let cachedLines { return cachedLines }
        let w = max(0, width)
        let innerWidth = max(0, w - paddingX * 2)

        var line = ANSI.truncateToWidth(text, width: innerWidth)
        // Remove the hard resets from truncateToWidth: we'll reset per line anyway.
        line = line.replacingOccurrences(of: ANSI.sgrReset + ANSI.osc8Reset, with: "")

        line = String(repeating: " ", count: paddingX) + line + String(repeating: " ", count: paddingX)
        line = padToWidth(line, width: w)

        var out: [String] = []
        out.reserveCapacity(1 + paddingY * 2)
        for _ in 0..<paddingY { out.append("") }
        out.append(line)
        for _ in 0..<paddingY { out.append("") }

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

