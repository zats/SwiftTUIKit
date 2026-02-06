import Foundation

public final class Box: Container, @unchecked Sendable {
    private var paddingX: Int
    private var paddingY: Int
    private var bgFn: ((String) -> String)?

    public init(paddingX: Int = 1, paddingY: Int = 1, background: ((String) -> String)? = nil) {
        self.paddingX = max(0, paddingX)
        self.paddingY = max(0, paddingY)
        self.bgFn = background
        super.init()
    }

    public func setBackground(_ fn: ((String) -> String)?) {
        bgFn = fn
        invalidate()
    }

    public override func render(width: Int) -> [String] {
        let w = max(0, width)
        let innerWidth = max(1, w - paddingX * 2)
        let childLines = super.render(width: innerWidth)

        var out: [String] = []
        out.reserveCapacity(childLines.count + paddingY * 2)

        for _ in 0..<paddingY { out.append("") }
        for l in childLines {
            let padded = String(repeating: " ", count: paddingX) + l + String(repeating: " ", count: paddingX)
            out.append(padToWidth(padded, width: w))
        }
        for _ in 0..<paddingY { out.append("") }

        if let bgFn {
            out = out.map { bgFn(padToWidth($0, width: w)) }
        }

        return out
    }

    private func padToWidth(_ s: String, width: Int) -> String {
        let w = ANSI.visibleWidth(s)
        if w >= width { return s }
        return s + String(repeating: " ", count: width - w)
    }
}
