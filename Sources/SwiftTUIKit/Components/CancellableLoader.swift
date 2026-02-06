import Foundation

public final class CancellableLoader: Component, @unchecked Sendable {
    private let loader: Loader
    private let abortController = AbortController()

    public var onAbort: (@Sendable () -> Void)?

    public var signal: AbortSignal { abortController.signal }
    public var aborted: Bool { abortController.signal.aborted }

    public init(
        tui: TUI,
        spinnerColor: @escaping @Sendable (String) -> String = { $0 },
        messageColor: @escaping @Sendable (String) -> String = { $0 },
        message: String = "Loading..."
    ) {
        self.loader = Loader(tui: tui, spinnerColor: spinnerColor, messageColor: messageColor, message: message)
    }

    public func setMessage(_ message: String) {
        loader.setMessage(message)
    }

    public func dispose() {
        loader.stop()
    }

    public func invalidate() {
        loader.invalidate()
    }

    public func render(width: Int) -> [String] {
        loader.render(width: width)
    }

    public func handleInput(_ event: InputEvent) {
        guard case let .key(k) = event else { return }
        let kb = getEditorKeybindings()
        if kb.matches(k, action: .selectCancel) {
            abortController.abort()
            onAbort?()
        }
    }
}

