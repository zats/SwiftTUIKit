import Foundation

public final class Loader: Component, @unchecked Sendable {
    private let frames: [String] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private var currentFrame: Int = 0

    private let spinnerColor: @Sendable (String) -> String
    private let messageColor: @Sendable (String) -> String
    private var message: String

    private weak var tui: TUI?
    private var timer: DispatchSourceTimer?

    public init(
        tui: TUI,
        spinnerColor: @escaping @Sendable (String) -> String = { $0 },
        messageColor: @escaping @Sendable (String) -> String = { $0 },
        message: String = "Loading..."
    ) {
        self.tui = tui
        self.spinnerColor = spinnerColor
        self.messageColor = messageColor
        self.message = message
        start()
    }

    deinit { stop() }

    public func setMessage(_ message: String) {
        self.message = message
        tui?.requestRender()
    }

    public func start() {
        stop()

        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(80))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.currentFrame = (self.currentFrame + 1) % self.frames.count
            self.tui?.requestRender()
        }
        t.resume()
        timer = t
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    public func invalidate() {}

    public func render(width: Int) -> [String] {
        let frame = frames[currentFrame]
        let line = spinnerColor(frame) + " " + messageColor(message)
        // Match TS behavior: top padding empty line.
        return ["", ANSI.truncateToWidth(line, width: width, ellipsis: "")]
    }
}

