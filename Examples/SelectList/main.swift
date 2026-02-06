import Foundation
import SwiftTUIKit

final class SelectListApp: Component, Focusable, @unchecked Sendable {
    private weak var tui: TUI?
    private let input = Input()
    private let list: SelectList
    private var selected: String = ""

    var focused: Bool = false {
        didSet { input.focused = focused }
    }

    init(tui: TUI) {
        self.tui = tui

        let theme = SelectListTheme(
            selectedText: { "\u{001B}[7m" + $0 + "\u{001B}[27m" },
            description: { "\u{001B}[2m" + $0 + "\u{001B}[22m" },
            scrollInfo: { "\u{001B}[2m" + $0 + "\u{001B}[22m" },
            noMatch: { "\u{001B}[2m" + $0 + "\u{001B}[22m" }
        )

        self.list = SelectList(
            items: [
                SelectItem(value: "/login", description: "OAuth login flow"),
                SelectItem(value: "/logout", description: "Clear auth"),
                SelectItem(value: "/model", description: "Switch model"),
                SelectItem(value: "/help", description: "Show help"),
                SelectItem(value: "/exit", description: "Exit app"),
            ],
            maxVisible: 5,
            theme: theme
        )

        list.onSelect = { [weak self] item in
            self?.selected = "selected: \(item.value)"
            self?.tui?.requestRender()
        }
        list.onCancel = { [weak self] in
            self?.tui?.stop()
            Foundation.exit(0)
        }

        input.onEscape = { [weak self] in
            self?.tui?.stop()
            Foundation.exit(0)
        }
    }

    func invalidate() {}

    func render(width: Int) -> [String] {
        var out: [String] = []
        out.append("select list demo")
        out.append("type to filter by prefix, use arrows + enter")
        out.append("")
        out.append(contentsOf: input.render(width: width))
        out.append("")
        out.append(contentsOf: list.render(width: width))
        out.append("")
        if !selected.isEmpty {
            out.append(selected)
        }
        return out
    }

    func handleInput(_ event: InputEvent) {
        switch event {
        case let .key(k):
            let kb = getEditorKeybindings()
            if kb.matches(k, action: .selectUp)
                || kb.matches(k, action: .selectDown)
                || kb.matches(k, action: .selectConfirm)
                || kb.matches(k, action: .selectCancel)
            {
                list.handleInput(.key(k))
                return
            }
            // Filter input for everything else.
            input.handleInput(.key(k))
            list.setFilter(input.getValue())
            tui?.requestRender()
        case let .paste(s):
            input.handleInput(.paste(s))
            list.setFilter(input.getValue())
            tui?.requestRender()
        default:
            break
        }
    }
}

let tui = TUI(terminal: ProcessTerminal())
let app = SelectListApp(tui: tui)
tui.addChild(app)
tui.setFocus(app)
tui.start()
dispatchMain()

