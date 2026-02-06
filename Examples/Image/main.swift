import Foundation
import SwiftTUIKit

enum Styles {
    static func dim(_ s: String) -> String { "\u{001B}[2m" + s + "\u{001B}[22m" }
}

final class App: Component, @unchecked Sendable {
    private weak var tui: TUI?
    private let image: Image

    init(tui: TUI) {
        self.tui = tui
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X9Z0AAAAASUVORK5CYII="
        self.image = Image(
            base64Data: base64,
            mimeType: "image/png",
            theme: ImageTheme(fallbackColor: Styles.dim),
            options: ImageOptions(maxWidthCells: 20, maxHeightCells: 10, filename: "dot.png")
        )
    }

    func invalidate() {}

    func render(width: Int) -> [String] {
        var out: [String] = []
        out.append("image demo (Esc/Ctrl+C exits)")
        out.append(Styles.dim("if your terminal supports Kitty or iTerm2 images, you'll see a tiny PNG"))
        out.append("")
        out.append(contentsOf: image.render(width: width))
        out.append("")
        out.append(Styles.dim("caps: images=\(getCapabilities().images.rawValue) cell=\(getCellDimensions().widthPx)x\(getCellDimensions().heightPx)px"))
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

