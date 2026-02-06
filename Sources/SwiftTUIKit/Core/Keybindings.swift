import Foundation

public enum EditorAction: String, CaseIterable, Sendable {
    // Cursor movement
    case cursorUp
    case cursorDown
    case cursorLeft
    case cursorRight
    case cursorWordLeft
    case cursorWordRight
    case cursorLineStart
    case cursorLineEnd
    case pageUp
    case pageDown

    // Deletion
    case deleteCharBackward
    case deleteCharForward
    case deleteWordBackward
    case deleteWordForward
    case deleteToLineStart
    case deleteToLineEnd

    // Text input
    case newLine
    case submit
    case tab

    // Selection/autocomplete
    case selectUp
    case selectDown
    case selectPageUp
    case selectPageDown
    case selectConfirm
    case selectCancel
}

public struct EditorKeybindingsConfig: Sendable, Equatable {
    public var actionToKeys: [EditorAction: [KeyId]]

    public init(actionToKeys: [EditorAction: [KeyId]] = [:]) {
        self.actionToKeys = actionToKeys
    }
}

public final class EditorKeybindingsManager: @unchecked Sendable {
    private var actionToKeys: [EditorAction: [KeyId]] = [:]

    public static let shared = EditorKeybindingsManager()

    public init(config: EditorKeybindingsConfig = .init()) {
        rebuild(config: config)
    }

    public func matches(_ event: KeyEvent, action: EditorAction) -> Bool {
        for k in actionToKeys[action] ?? [] {
            if k.matches(event) { return true }
        }
        return false
    }

    public func getKeys(_ action: EditorAction) -> [KeyId] {
        actionToKeys[action] ?? []
    }

    public func setConfig(_ config: EditorKeybindingsConfig) {
        rebuild(config: config)
    }

    private func rebuild(config: EditorKeybindingsConfig) {
        actionToKeys = Self.defaultBindings
        for (a, ks) in config.actionToKeys {
            actionToKeys[a] = ks
        }
    }

    // Mirrors pi-mono DEFAULT_EDITOR_KEYBINDINGS where it matters.
    private static let defaultBindings: [EditorAction: [KeyId]] = [
        .cursorUp: [KeyId.parse("up")!],
        .cursorDown: [KeyId.parse("down")!],
        .cursorLeft: [KeyId.parse("left")!, KeyId.parse("ctrl+b")!],
        .cursorRight: [KeyId.parse("right")!, KeyId.parse("ctrl+f")!],
        .cursorWordLeft: [KeyId.parse("alt+left")!, KeyId.parse("ctrl+left")!, KeyId.parse("alt+b")!],
        .cursorWordRight: [KeyId.parse("alt+right")!, KeyId.parse("ctrl+right")!, KeyId.parse("alt+f")!],
        .cursorLineStart: [KeyId.parse("home")!, KeyId.parse("ctrl+a")!],
        .cursorLineEnd: [KeyId.parse("end")!, KeyId.parse("ctrl+e")!],
        .pageUp: [KeyId.parse("pageUp")!],
        .pageDown: [KeyId.parse("pageDown")!],

        .deleteCharBackward: [KeyId.parse("backspace")!],
        .deleteCharForward: [KeyId.parse("delete")!, KeyId.parse("ctrl+d")!],
        .deleteWordBackward: [KeyId.parse("ctrl+w")!, KeyId.parse("alt+backspace")!],
        .deleteWordForward: [KeyId.parse("alt+d")!, KeyId.parse("alt+delete")!],
        .deleteToLineStart: [KeyId.parse("ctrl+u")!],
        .deleteToLineEnd: [KeyId.parse("ctrl+k")!],

        // Note: Shift+Enter isn't reliably distinguishable without Kitty CSI-u.
        // Our KeyDecoder does support CSI-u printable keys, but terminals may not enable it.
        .newLine: [KeyId.parse("shift+enter")!],
        .submit: [KeyId.parse("enter")!],
        .tab: [KeyId.parse("tab")!],

        .selectUp: [KeyId.parse("up")!],
        .selectDown: [KeyId.parse("down")!],
        .selectPageUp: [KeyId.parse("pageUp")!],
        .selectPageDown: [KeyId.parse("pageDown")!],
        .selectConfirm: [KeyId.parse("enter")!],
        .selectCancel: [KeyId.parse("escape")!, KeyId.parse("ctrl+c")!],
    ]
}

public func getEditorKeybindings() -> EditorKeybindingsManager {
    EditorKeybindingsManager.shared
}

