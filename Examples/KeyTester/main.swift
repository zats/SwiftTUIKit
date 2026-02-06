import Foundation
import SwiftTUIKit

final class KeyTester: Component, @unchecked Sendable {
    private weak var tui: TUI?
    private var last: String = "Press keys (Esc/Ctrl+C to exit)."

    init(tui: TUI) {
        self.tui = tui
    }

    func invalidate() {}

    func render(width: Int) -> [String] {
        var out: [String] = []
        out.append("key tester")
        out.append("")
        out.append(contentsOf: ANSI.wrapTextWithAnsi(last, width: max(1, width)))
        out.append("")
        out.append("Esc/Ctrl+C: exit")
        return out
    }

    func handleInput(_ event: InputEvent) {
        switch event {
        case let .key(k):
            let kb = getEditorKeybindings()
            if kb.matches(k, action: .selectCancel) {
                tui?.stop()
                Foundation.exit(0)
            }
            last = "key=\(k.key) modifiers=\(k.modifiers) type=\(k.type)"
        case let .paste(s):
            last = "paste(\(s.count) chars): " + s.replacingOccurrences(of: "\n", with: "\\n")
        case .resize:
            let cols = tui?.terminal.columns ?? 0
            let rows = tui?.terminal.rows ?? 0
            last = "resize: \(cols)x\(rows)"
        case let .raw(d):
            last = "raw(\(d.count) bytes)"
        }
        tui?.requestRender()
    }
}

let tui = TUI {
    AnyTUIView { tui in
        KeyTester(tui: tui)
    }
}

tui.start()
dispatchMain()
