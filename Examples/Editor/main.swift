import Foundation
import SwiftTUIKit

enum Styles {
    static func dim(_ s: String) -> String { "\u{001B}[2m" + s + "\u{001B}[22m" }
    static func bold(_ s: String) -> String { "\u{001B}[1m" + s + "\u{001B}[22m" }
    static func inv(_ s: String) -> String { "\u{001B}[7m" + s + "\u{001B}[27m" }
}

final class App: Component, Focusable, @unchecked Sendable {
    private weak var tui: TUI?
    private let editor: Editor
    private var log: [String] = []

    var focused: Bool = false {
        didSet { editor.focused = focused }
    }

    init(tui: TUI) {
        self.tui = tui

        let listTheme = SelectListTheme(
            selectedText: { Styles.inv($0) },
            description: { Styles.dim($0) },
            scrollInfo: { Styles.dim($0) },
            noMatch: { Styles.dim($0) }
        )
        let theme = EditorTheme(borderColor: { Styles.dim($0) }, selectList: listTheme)
        self.editor = Editor(tui: tui, theme: theme, options: EditorOptions(paddingX: 1, autocompleteMaxVisible: 6))

        let cmds: [SlashCommand] = [
            SlashCommand(name: "model", description: "Switch model") { prefix in
                let items = ["gpt-5.2-codex", "gpt-4.1", "gpt-4o-mini"].map { AutocompleteItem(value: $0) }
                return fuzzyFilter(items, query: prefix, getText: { $0.value })
            },
            SlashCommand(name: "help", description: "Show help"),
            SlashCommand(name: "exit", description: "Exit"),
        ]
        let provider = CombinedAutocompleteProvider(commands: cmds, basePath: FileManager.default.currentDirectoryPath)
        editor.setAutocompleteProvider(provider)

        editor.onSubmit = { [weak self] text in
            guard let self else { return }
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "/exit" {
                self.tui?.stop()
                Foundation.exit(0)
            }
            self.log.append("submitted: \(t)")
            if self.log.count > 6 { self.log.removeFirst(self.log.count - 6) }
            self.tui?.requestRender()
        }
    }

    func invalidate() {}

    func render(width: Int) -> [String] {
        var out: [String] = []
        out.append("editor demo")
        out.append(Styles.dim("type /model <tab> for arg completion, or @\"... for file completion"))
        out.append(Styles.dim("Esc/Ctrl+C exits"))
        out.append("")
        out.append(contentsOf: editor.render(width: width))
        if !log.isEmpty {
            out.append("")
            out.append(Styles.dim("log:"))
            for l in log { out.append(Styles.dim("  " + l)) }
        }
        return out
    }

    func handleInput(_ event: InputEvent) {
        if case let .key(k) = event, getEditorKeybindings().matches(k, action: .selectCancel) {
            tui?.stop()
            Foundation.exit(0)
        }
        editor.handleInput(event)
    }
}

let tui = TUI {
    AnyTUIView { tui in
        App(tui: tui)
    }
}

tui.start()
dispatchMain()
