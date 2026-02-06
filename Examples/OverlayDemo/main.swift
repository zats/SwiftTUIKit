import Foundation
import SwiftTUIKit

final class Modal: Component, @unchecked Sendable {
    private weak var tui: TUI?
    private let content: String

    init(tui: TUI, content: String) {
        self.tui = tui
        self.content = content
    }

    func invalidate() {}

    func render(width: Int) -> [String] {
        let inner = max(1, width - 4)
        var lines: [String] = []
        lines.append("┌" + String(repeating: "─", count: max(0, width - 2)) + "┐")
        for l in ANSI.wrapTextWithAnsi(content, width: inner) {
            let padded = "│ " + l + String(repeating: " ", count: max(0, inner - ANSI.visibleWidth(l))) + " │"
            lines.append(padded)
        }
        lines.append("└" + String(repeating: "─", count: max(0, width - 2)) + "┘")
        return lines
    }

    func handleInput(_ event: InputEvent) {
        guard case let .key(k) = event else { return }
        let kb = getEditorKeybindings()
        if kb.matches(k, action: .selectCancel) {
            tui?.hideOverlay()
        }
    }
}

final class App: Component, @unchecked Sendable {
    private weak var tui: TUI?

    init(tui: TUI) { self.tui = tui }

    func invalidate() {}

    func render(width: Int) -> [String] {
        [
            "overlay demo",
            "",
            "press 'o' to show overlay",
            "esc/ctrl+c: exit",
        ]
    }

    func handleInput(_ event: InputEvent) {
        guard case let .key(k) = event else { return }
        let kb = getEditorKeybindings()
        if kb.matches(k, action: .selectCancel) {
            tui?.stop()
            Foundation.exit(0)
        }
        if case let .char(c) = k.key, String(c).lowercased() == "o" {
            guard let tui else { return }
            _ = tui.showOverlay(
                Modal(tui: tui, content: "Hello from an overlay.\n\nPress Esc to close."),
                options: {
                    var o = OverlayOptions()
                    o.width = .absolute(min(60, tui.terminal.columns))
                    o.maxHeight = .percent(50)
                    o.anchor = .center
                    o.marginAll = 2
                    return o
                }()
            )
        }
    }
}

let tui = TUI {
    AnyTUIView { tui in
        App(tui: tui)
    }
}

tui.start()
dispatchMain()
