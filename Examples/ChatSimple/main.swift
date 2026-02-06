import Foundation
import SwiftTUIKit

enum Styles {
    static func dim(_ s: String) -> String { "\u{001B}[2m" + s + "\u{001B}[22m" }
    static func bold(_ s: String) -> String { "\u{001B}[1m" + s + "\u{001B}[22m" }
}

final class ChatApp: Component, Focusable, @unchecked Sendable {
    private var messages: [String] = [
        "Pi: Hello! Type something and press Enter.",
    ]

    private let input = Input()
    private weak var tui: TUI?

    var focused: Bool = false {
        didSet { input.focused = focused }
    }

    init(tui: TUI) {
        self.tui = tui
        input.onSubmit = { [weak self] text in
            guard let self else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return }
            self.messages.append("You: \(trimmed)")
            self.messages.append("Pi: (echo) \(trimmed)")
            self.input.setValue("")
            self.tui?.requestRender()
        }
        input.onEscape = { [weak self] in
            self?.tui?.stop()
            Foundation.exit(0)
        }
    }

    func invalidate() {}

    func render(width: Int) -> [String] {
        var out: [String] = []
        out.reserveCapacity(messages.count + 8)

        out.append(Styles.bold("swift-tui chat (demo)  Esc/Ctrl+C: quit"))
        out.append("")

        for m in messages.suffix(200) {
            out.append(contentsOf: ANSI.wrapTextWithAnsi(m, width: max(1, width)))
        }

        out.append("")
        out.append(contentsOf: input.render(width: width))
        out.append("")
        out.append(Styles.dim("enter: send  esc/ctrl+c: exit"))
        return out
    }

    func handleInput(_ event: InputEvent) {
        input.handleInput(event)
    }
}

let tui = TUI {
    AnyTUIView { tui in
        ChatApp(tui: tui)
    }
}

tui.start()

dispatchMain()
