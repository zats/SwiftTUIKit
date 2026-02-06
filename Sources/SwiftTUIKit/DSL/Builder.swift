import Foundation

public protocol TUIView {
    func makeComponent(in tui: TUI) -> Component
}

public struct AnyTUIView: TUIView {
    private let _make: (TUI) -> Component

    public init(_ make: @escaping (TUI) -> Component) {
        self._make = make
    }

    public func makeComponent(in tui: TUI) -> Component { _make(tui) }
}

@resultBuilder
public enum TUIViewBuilder {
    public static func buildBlock(_ parts: [AnyTUIView]...) -> [AnyTUIView] { parts.flatMap { $0 } }
    public static func buildOptional(_ part: [AnyTUIView]?) -> [AnyTUIView] { part ?? [] }
    public static func buildEither(first: [AnyTUIView]) -> [AnyTUIView] { first }
    public static func buildEither(second: [AnyTUIView]) -> [AnyTUIView] { second }
    public static func buildArray(_ parts: [[AnyTUIView]]) -> [AnyTUIView] { parts.flatMap { $0 } }

    public static func buildExpression(_ expr: AnyTUIView) -> [AnyTUIView] { [expr] }
    public static func buildExpression(_ expr: TUIView) -> [AnyTUIView] { [AnyTUIView { expr.makeComponent(in: $0) }] }
    public static func buildExpression(_ expr: Component) -> [AnyTUIView] { [AnyTUIView { _ in expr }] }
    public static func buildExpression(_ expr: [AnyTUIView]) -> [AnyTUIView] { expr }

    public static func buildFinalResult(_ parts: [AnyTUIView]) -> [AnyTUIView] { parts }
}

public extension TUI {
    convenience init(terminal: Terminal = ProcessTerminal(), @TUIViewBuilder content: () -> [AnyTUIView]) {
        self.init(terminal: terminal)
        setRoot(content)
    }

    func setRoot(@TUIViewBuilder _ content: () -> [AnyTUIView]) {
        clear()
        for v in content() {
            addChild(v.makeComponent(in: self))
        }
    }
}

public struct VStack: TUIView {
    private let children: [AnyTUIView]

    public init(@TUIViewBuilder _ content: () -> [AnyTUIView]) {
        self.children = content()
    }

    public func makeComponent(in tui: TUI) -> Component {
        let c = Container()
        for v in children {
            c.addChild(v.makeComponent(in: tui))
        }
        return c
    }
}

