import Foundation
import SwiftTUIKit

enum Styles {
    static func bold(_ s: String) -> String { "\u{001B}[1m" + s + "\u{001B}[22m" }
    static func dim(_ s: String) -> String { "\u{001B}[2m" + s + "\u{001B}[22m" }
    static func cyan(_ s: String) -> String { "\u{001B}[36m" + s + "\u{001B}[39m" }
    static func yellow(_ s: String) -> String { "\u{001B}[33m" + s + "\u{001B}[39m" }
    static func underline(_ s: String) -> String { "\u{001B}[4m" + s + "\u{001B}[24m" }
    static func strike(_ s: String) -> String { "\u{001B}[9m" + s + "\u{001B}[29m" }
    static func italic(_ s: String) -> String { "\u{001B}[3m" + s + "\u{001B}[23m" }
    static func bg(_ s: String) -> String { "\u{001B}[48;5;236m" + s + "\u{001B}[49m" }
}

final class App: Component, @unchecked Sendable {
    private weak var tui: TUI?
    private let md: Markdown

    init(tui: TUI) {
        self.tui = tui
        let theme = MarkdownTheme(
            heading: { Styles.bold($0) },
            link: { Styles.cyan($0) },
            linkUrl: { Styles.dim($0) },
            code: { Styles.yellow($0) },
            codeBlock: { Styles.yellow($0) },
            codeBlockBorder: { Styles.dim($0) },
            quote: { $0 },
            quoteBorder: { Styles.dim($0) },
            hr: { Styles.dim($0) },
            listBullet: { Styles.dim($0) },
            bold: { Styles.bold($0) },
            italic: { Styles.italic($0) },
            strikethrough: { Styles.strike($0) },
            underline: { Styles.underline($0) }
        )

        let text = """
# SwiftTUIKit Markdown

This is a minimal markdown renderer (port of `pi-mono/packages/tui`).

- `inline code`
- **bold**, *italic*, ~~strike~~
- Links: [OpenAI](https://openai.com)

> Quotes are supported.

---

```swift
print("hello")
```
"""

        self.md = Markdown(
            text,
            paddingX: 1,
            paddingY: 0,
            theme: theme,
            defaultTextStyle: DefaultTextStyle(bgColor: Styles.bg)
        )
    }

    func invalidate() {}

    func render(width: Int) -> [String] {
        var out: [String] = []
        out.append("markdown demo (Esc/Ctrl+C to exit)")
        out.append("")
        out.append(contentsOf: md.render(width: width))
        return out
    }

    func handleInput(_ event: InputEvent) {
        guard case let .key(k) = event else { return }
        if getEditorKeybindings().matches(k, action: .selectCancel) {
            tui?.stop()
            Foundation.exit(0)
        }
    }
}

let tui = TUI(terminal: ProcessTerminal())
let app = App(tui: tui)
tui.addChild(app)
tui.setFocus(app)
tui.start()
dispatchMain()

