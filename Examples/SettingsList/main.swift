import Foundation
import SwiftTUIKit

enum Styles {
    static func dim(_ s: String) -> String { "\u{001B}[2m" + s + "\u{001B}[22m" }
    static func bold(_ s: String) -> String { "\u{001B}[1m" + s + "\u{001B}[22m" }
}

func makeSubmenu(title: String, values: [String], selected: String, done: @escaping @Sendable (String?) -> Void) -> Component {
    let theme = SelectListTheme(
        selectedText: { "\u{001B}[7m" + $0 + "\u{001B}[27m" },
        description: { Styles.dim($0) },
        scrollInfo: { Styles.dim($0) },
        noMatch: { Styles.dim($0) }
    )

    let list = SelectList(
        items: values.map { SelectItem(value: $0) },
        maxVisible: 8,
        theme: theme
    )
    if let idx = values.firstIndex(of: selected) {
        list.setSelectedIndex(idx)
    }

    final class Wrapper: Component, @unchecked Sendable {
        let list: SelectList
        let title: String
        init(list: SelectList, title: String) {
            self.list = list
            self.title = title
        }
        func invalidate() {}
        func render(width: Int) -> [String] {
            var out: [String] = []
            out.append(Styles.bold(title))
            out.append("")
            out.append(contentsOf: list.render(width: width))
            return out
        }
        func handleInput(_ event: InputEvent) {
            list.handleInput(event)
        }
    }

    list.onSelect = { item in done(item.value) }
    list.onCancel = { done(nil) }

    return Wrapper(list: list, title: title)
}

final class App: Component, Focusable, @unchecked Sendable {
    private final class CurrentBox: @unchecked Sendable {
        var values: [String: String]
        init(values: [String: String]) { self.values = values }
    }

    private let currentBox: CurrentBox
    private let settings: SettingsList

    var focused: Bool = false {
        didSet { settings.focused = focused }
    }

    init(tui: TUI) {
        let currentBox = CurrentBox(values: [:])
        self.currentBox = currentBox

        let theme = SettingsListTheme(
            label: { t, selected in selected ? "\u{001B}[1m" + t + "\u{001B}[22m" : t },
            value: { t, selected in selected ? "\u{001B}[7m" + t + "\u{001B}[27m" : t },
            description: { Styles.dim($0) },
            cursor: "→ ",
            hint: { Styles.dim($0) }
        )

        let items: [SettingItem] = [
            SettingItem(
                id: "model",
                label: "Model",
                description: "Choose the model used for requests.",
                currentValue: "gpt-5.2-codex",
                values: ["gpt-5.2-codex", "gpt-4.1", "gpt-4o-mini"]
            ),
            SettingItem(
                id: "stream",
                label: "Streaming",
                description: "Stream tokens as they arrive.",
                currentValue: "on",
                values: ["on", "off"]
            ),
            SettingItem(
                id: "theme",
                label: "Theme",
                description: "Pick a theme (demo submenu).",
                currentValue: "default",
                submenu: { current, done in
                    makeSubmenu(title: "Theme", values: ["default", "mono", "solarized"], selected: current, done: done)
                }
            ),
        ]

        currentBox.values = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.currentValue) })

        self.settings = SettingsList(
            items: items,
            maxVisible: 7,
            theme: theme,
            onChange: { id, value in
                currentBox.values[id] = value
                tui.requestRender()
            },
            onCancel: {
                tui.stop()
                Foundation.exit(0)
            },
            options: SettingsListOptions(enableSearch: true)
        )
    }

    func invalidate() {}

    func render(width: Int) -> [String] {
        var out: [String] = []
        out.append("settings list demo")
        out.append("")
        out.append(contentsOf: settings.render(width: width))
        return out
    }

    func handleInput(_ event: InputEvent) {
        settings.handleInput(event)
    }
}

let tui = TUI(terminal: ProcessTerminal())
let app = App(tui: tui)
tui.addChild(app)
tui.setFocus(app)
tui.start()
dispatchMain()
