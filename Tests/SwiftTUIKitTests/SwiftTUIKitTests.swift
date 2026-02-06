import Testing
@testable import SwiftTUIKit

@Test func visibleWidthIgnoresAnsi() async throws {
    #expect(ANSI.visibleWidth("abc") == 3)
    #expect(ANSI.visibleWidth("\u{001B}[31mabc\u{001B}[0m") == 3)
}

@Test func truncateToWidthKeepsWidth() async throws {
    let s = ANSI.truncateToWidth("abcdef", width: 3, ellipsis: "")
    #expect(ANSI.visibleWidth(s) == 3)
    #expect(s.contains("abc"))
}

@Test func wrapTextNeverExceedsWidth() async throws {
    let lines = ANSI.wrapTextWithAnsi("hello world", width: 5)
    #expect(lines.count >= 2)
    for l in lines {
        #expect(ANSI.visibleWidth(l) <= 5)
    }
}

@Test func fuzzyMatchBasics() async throws {
    #expect(fuzzyMatch("abc", "a_b_c").matches == true)
    #expect(fuzzyMatch("zzz", "abc").matches == false)
}

@Test func fuzzyFilterOrdersBestFirst() async throws {
    let items = ["abc", "axbyc", "a___b___c"]
    let out = fuzzyFilter(items, query: "abc", getText: { $0 })
    #expect(out.contains("abc"))
    #expect(out.first == "abc")
}

@Test func imageLineDetection() async throws {
    #expect(isImageLine("\u{001B}_Gf=100;abcd\u{001B}\\") == true)
    #expect(isImageLine("nope") == false)
}

@Test func keyDecoderBracketedPaste() async throws {
    let d = Data("\u{001B}[200~hello\nworld\u{001B}[201~".utf8)
    let dec = KeyDecoder()
    let events = dec.feed(d)
    #expect(events == [.paste("hello\nworld")])
}

@Test func keyDecoderCtrlC() async throws {
    let dec = KeyDecoder()
    let events = dec.feed(Data([3]))
    #expect(events.count == 1)
    guard case let .key(k) = events[0] else {
        #expect(Bool(false))
        return
    }
    #expect(k.modifiers.contains(.ctrl))
    if case let .char(c) = k.key {
        #expect(String(c).lowercased() == "c")
    } else {
        #expect(Bool(false))
    }
}
