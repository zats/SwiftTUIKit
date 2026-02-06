import Foundation

public final class AbortSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var _aborted: Bool = false
    private var handlers: [@Sendable () -> Void] = []

    public init() {}

    public var aborted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _aborted
    }

    public func onAbort(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        if _aborted {
            lock.unlock()
            handler()
            return
        }
        handlers.append(handler)
        lock.unlock()
    }

    fileprivate func _abort() {
        let toRun: [@Sendable () -> Void]
        lock.lock()
        if _aborted {
            lock.unlock()
            return
        }
        _aborted = true
        toRun = handlers
        handlers.removeAll(keepingCapacity: false)
        lock.unlock()
        for h in toRun { h() }
    }
}

public final class AbortController: @unchecked Sendable {
    public let signal: AbortSignal

    public init() {
        self.signal = AbortSignal()
    }

    public func abort() {
        signal._abort()
    }
}

