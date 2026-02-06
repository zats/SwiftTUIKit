import Foundation

public final class Spacer: Component, @unchecked Sendable {
    private let lines: Int

    public init(_ lines: Int = 1) {
        self.lines = max(0, lines)
    }

    public func invalidate() {}

    public func render(width _: Int) -> [String] {
        Array(repeating: "", count: lines)
    }
}

