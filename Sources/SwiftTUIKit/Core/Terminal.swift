import Foundation

#if canImport(Darwin)
import Darwin
#endif

public protocol Terminal: AnyObject, Sendable {
    var columns: Int { get }
    var rows: Int { get }

    func start(onInput: @escaping @Sendable (Data) -> Void, onResize: @escaping @Sendable () -> Void)
    func stop()

    func write(_ data: Data)
    func write(_ s: String)

    func moveBy(lines: Int)
    func hideCursor()
    func showCursor()
    func clearLine()
    func clearFromCursor()
    func clearScreen()
}

public final class ProcessTerminal: Terminal, @unchecked Sendable {
    private var onInput: (@Sendable (Data) -> Void)?
    private var onResize: (@Sendable () -> Void)?

    // DispatchSourceRead can be unreliable on PTYs in some setups; use FileHandle readabilityHandler.
    private let stdinHandle = FileHandle.standardInput
    private var winchSource: DispatchSourceSignal?
    private let queue = DispatchQueue(label: "SwiftTUIKit.ProcessTerminal", qos: .userInteractive)

    private var raw: RawTerminal?

    public init() {}

    public var columns: Int { RawTerminal.getSize().cols }
    public var rows: Int { RawTerminal.getSize().rows }

    public func start(onInput: @escaping @Sendable (Data) -> Void, onResize: @escaping @Sendable () -> Void) {
        self.onInput = onInput
        self.onResize = onResize

        let raw = RawTerminal()
        self.raw = raw
        do {
            try raw.enter()
        } catch {
            // Best effort: still attempt to operate.
        }

        // Enable bracketed paste so paste blocks are delimited.
        write(ANSI.bracketedPasteOn)

        // stdin readability handler
        stdinHandle.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let d = handle.availableData
            if d.isEmpty { return }
            self.onInput?(d)
        }

        // SIGWINCH for resize
        #if canImport(Darwin)
        signal(SIGWINCH, SIG_IGN)
        let ws = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: queue)
        ws.setEventHandler { [weak self] in
            self?.onResize?()
        }
        ws.resume()
        winchSource = ws
        #endif
    }

    public func stop() {
        stdinHandle.readabilityHandler = nil

        winchSource?.cancel()
        winchSource = nil

        // Disable bracketed paste.
        write(ANSI.bracketedPasteOff)

        raw?.exit()
        raw = nil
    }

    public func write(_ data: Data) {
        FileHandle.standardOutput.write(data)
    }

    public func write(_ s: String) {
        guard let d = s.data(using: .utf8) else { return }
        write(d)
    }

    public func moveBy(lines: Int) {
        if lines == 0 { return }
        if lines > 0 {
            write(ANSI.moveDown(lines))
        } else {
            write(ANSI.moveUp(-lines))
        }
    }

    public func hideCursor() { write(ANSI.hideCursor) }
    public func showCursor() { write(ANSI.showCursor) }
    public func clearLine() { write(ANSI.clearLine) }
    public func clearFromCursor() { write(ANSI.clearFromCursor) }
    public func clearScreen() { write(ANSI.clearScreen) }
}

public struct TerminalSize: Sendable, Equatable {
    public var cols: Int
    public var rows: Int

    public init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
    }
}

public final class RawTerminal: @unchecked Sendable {
    private var original: termios?
    private var isActive: Bool = false

    public init() {}

    public func enter() throws {
        #if !canImport(Darwin)
        throw NSError(domain: "RawTerminal", code: 1, userInfo: [NSLocalizedDescriptionKey: "Raw terminal mode is only supported on Darwin"])
        #else
        guard !isActive else { return }

        var t = termios()
        if tcgetattr(STDIN_FILENO, &t) != 0 {
            throw NSError(domain: "RawTerminal", code: 2, userInfo: [NSLocalizedDescriptionKey: "tcgetattr failed"])
        }
        original = t

        // Raw-ish mode:
        // - disable canonical mode so we get keypresses immediately
        // - disable echo
        // - disable ISIG so Ctrl+C is delivered as input
        t.c_iflag &= ~tcflag_t(IXON | ICRNL | BRKINT | INPCK | ISTRIP)
        t.c_oflag &= ~tcflag_t(OPOST)
        t.c_cflag |= tcflag_t(CS8)
        t.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN | ISIG)

        // Configure read() behavior: return as soon as at least 1 byte is available.
        withUnsafeMutablePointer(to: &t.c_cc) { ccPtr in
            ccPtr.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { cc in
                cc[Int(VMIN)] = 1
                cc[Int(VTIME)] = 0
            }
        }

        if tcsetattr(STDIN_FILENO, TCSAFLUSH, &t) != 0 {
            throw NSError(domain: "RawTerminal", code: 3, userInfo: [NSLocalizedDescriptionKey: "tcsetattr failed"])
        }

        isActive = true
        #endif
    }

    public func exit() {
        #if canImport(Darwin)
        guard isActive else { return }
        if var orig = original {
            _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig)
        }
        isActive = false
        #endif
    }

    deinit { exit() }

    public static func getSize() -> TerminalSize {
        #if canImport(Darwin)
        var ws = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 {
            return TerminalSize(cols: max(1, Int(ws.ws_col)), rows: max(1, Int(ws.ws_row)))
        }
        #endif
        return TerminalSize(cols: 80, rows: 24)
    }
}
