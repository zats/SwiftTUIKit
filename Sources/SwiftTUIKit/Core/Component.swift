import Foundation

public protocol Component: AnyObject, Sendable {
    /// Render the component to lines for the given viewport width.
    /// Each returned line must not exceed `width` visible columns.
    func render(width: Int) -> [String]

    /// Handle an input event when the component is focused.
    func handleInput(_ event: InputEvent)

    /// Invalidate any cached rendering state.
    func invalidate()

    /// If true, the component wants key release events (Kitty protocol).
    var wantsKeyRelease: Bool { get }
}

public extension Component {
    func handleInput(_: InputEvent) {}
    var wantsKeyRelease: Bool { false }
}

/// Components that can receive focus and want a hardware cursor for IME positioning.
///
/// When focused, the component should emit `ANSI.cursorMarker` at the cursor position
/// in its render output. `TUI` will strip that marker and position the terminal cursor
/// at that location.
public protocol Focusable: AnyObject, Sendable {
    var focused: Bool { get set }
}

