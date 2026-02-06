import Foundation

public enum InputEvent: Sendable, Equatable {
    case key(KeyEvent)
    case paste(String)
    case resize

    /// Unclassified bytes (rare): forwarded to focused component as `.key(.raw(...))` when needed.
    case raw(Data)
}

public struct KeyEvent: Sendable, Equatable {
    public enum EventType: String, Sendable, Equatable { case press, `repeat`, release }

    public struct Modifiers: OptionSet, Sendable, Equatable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let ctrl = Modifiers(rawValue: 1 << 0)
        public static let alt = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
    }

    public enum Key: Sendable, Equatable {
        case char(Character)
        case enter
        case tab
        case backspace
        case delete
        case escape
        case space

        case up
        case down
        case left
        case right
        case home
        case end
        case pageUp
        case pageDown

        case f(Int)

        // Non-standard / debugging
        case unknown(String)
    }

    public var key: Key
    public var modifiers: Modifiers
    public var type: EventType

    public init(key: Key, modifiers: Modifiers = [], type: EventType = .press) {
        self.key = key
        self.modifiers = modifiers
        self.type = type
    }
}

public struct KeyId: Sendable, Equatable, Hashable {
    public var modifiers: KeyEvent.Modifiers
    public var key: String

    public init(modifiers: KeyEvent.Modifiers = [], key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    public func matches(_ event: KeyEvent) -> Bool {
        KeyId.from(event) == self
    }

    public static func from(_ event: KeyEvent) -> KeyId {
        let key: String = {
            switch event.key {
            case let .char(c):
                return String(c).lowercased()
            case .enter:
                return "enter"
            case .tab:
                return "tab"
            case .backspace:
                return "backspace"
            case .delete:
                return "delete"
            case .escape:
                return "escape"
            case .space:
                return "space"
            case .up:
                return "up"
            case .down:
                return "down"
            case .left:
                return "left"
            case .right:
                return "right"
            case .home:
                return "home"
            case .end:
                return "end"
            case .pageUp:
                return "pageUp"
            case .pageDown:
                return "pageDown"
            case let .f(n):
                return "f\(n)"
            case let .unknown(s):
                return s.lowercased()
            }
        }()
        return KeyId(modifiers: event.modifiers, key: key)
    }

    public static func parse(_ s: String) -> KeyId? {
        let raw = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }

        let parts = raw.split(separator: "+").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var mods: KeyEvent.Modifiers = []
        var key: String?

        for p in parts {
            switch p {
            case "ctrl", "control":
                mods.insert(.ctrl)
            case "alt", "option", "meta":
                mods.insert(.alt)
            case "shift":
                mods.insert(.shift)
            case "esc":
                key = "escape"
            case "return":
                key = "enter"
            case "pageup":
                key = "pageUp"
            case "pagedown":
                key = "pageDown"
            default:
                key = p
            }
        }

        guard let key else { return nil }
        return KeyId(modifiers: mods, key: key)
    }

    public var description: String {
        var parts: [String] = []
        if modifiers.contains(.ctrl) { parts.append("ctrl") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.alt) { parts.append("alt") }
        parts.append(key)
        return parts.joined(separator: "+")
    }
}
