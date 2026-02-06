import Foundation

public struct FuzzyMatch: Sendable, Equatable {
    public var matches: Bool
    public var score: Double

    public init(matches: Bool, score: Double) {
        self.matches = matches
        self.score = score
    }
}

/// Matches if all query characters appear in order (not necessarily consecutive).
/// Lower score is a better match.
public func fuzzyMatch(_ query: String, _ text: String) -> FuzzyMatch {
    let queryLower = query.lowercased()
    let textLower = text.lowercased()

    func matchQuery(_ q: String) -> FuzzyMatch {
        if q.isEmpty { return FuzzyMatch(matches: true, score: 0) }
        if q.count > textLower.count { return FuzzyMatch(matches: false, score: 0) }

        let qChars = Array(q)
        let tChars = Array(textLower)

        var qi = 0
        var score: Double = 0
        var lastMatchIndex = -1
        var consecutiveMatches = 0

        func isWordBoundary(_ i: Int) -> Bool {
            if i == 0 { return true }
            let prev = tChars[i - 1]
            return prev.isWhitespace || prev == "-" || prev == "_" || prev == "." || prev == "/" || prev == ":" // match TS
        }

        for i in 0..<tChars.count {
            if qi >= qChars.count { break }
            if tChars[i] == qChars[qi] {
                if lastMatchIndex == i - 1 {
                    consecutiveMatches += 1
                    score -= Double(consecutiveMatches) * 5
                } else {
                    consecutiveMatches = 0
                    if lastMatchIndex >= 0 {
                        score += Double(i - lastMatchIndex - 1) * 2
                    }
                }

                if isWordBoundary(i) {
                    score -= 10
                }

                score += Double(i) * 0.1

                lastMatchIndex = i
                qi += 1
            }
        }

        if qi < qChars.count { return FuzzyMatch(matches: false, score: 0) }
        return FuzzyMatch(matches: true, score: score)
    }

    let primary = matchQuery(queryLower)
    if primary.matches { return primary }

    // Match TS behavior: swap alpha/digit groups (e.g. "abc12" -> "12abc").
    func asciiLettersThenDigits(_ s: String) -> (letters: String, digits: String)? {
        let chars = Array(s)
        var i = 0
        var letters = ""
        while i < chars.count {
            let c = chars[i]
            guard ("a"..."z").contains(String(c)) else { break }
            letters.append(c)
            i += 1
        }
        if letters.isEmpty { return nil }
        var digits = ""
        while i < chars.count {
            let c = chars[i]
            guard c.isNumber else { break }
            digits.append(c)
            i += 1
        }
        if digits.isEmpty { return nil }
        if i != chars.count { return nil }
        return (letters, digits)
    }

    func asciiDigitsThenLetters(_ s: String) -> (digits: String, letters: String)? {
        let chars = Array(s)
        var i = 0
        var digits = ""
        while i < chars.count {
            let c = chars[i]
            guard c.isNumber else { break }
            digits.append(c)
            i += 1
        }
        if digits.isEmpty { return nil }
        var letters = ""
        while i < chars.count {
            let c = chars[i]
            guard ("a"..."z").contains(String(c)) else { break }
            letters.append(c)
            i += 1
        }
        if letters.isEmpty { return nil }
        if i != chars.count { return nil }
        return (digits, letters)
    }

    let swapped: String = {
        if let m = asciiLettersThenDigits(queryLower) {
            return m.digits + m.letters
        }
        if let m = asciiDigitsThenLetters(queryLower) {
            return m.letters + m.digits
        }
        return ""
    }()

    if swapped.isEmpty { return primary }

    let swappedMatch = matchQuery(swapped)
    if !swappedMatch.matches { return primary }
    return FuzzyMatch(matches: true, score: swappedMatch.score + 5)
}

/// Filter and sort items by fuzzy match quality (best matches first).
/// Supports space-separated tokens: all tokens must match.
public func fuzzyFilter<T>(_ items: [T], query: String, getText: (T) -> String) -> [T] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return items }

    let tokens = trimmed
        .split(whereSeparator: { $0.isWhitespace })
        .map(String.init)
        .filter { !$0.isEmpty }

    if tokens.isEmpty { return items }

    var results: [(item: T, totalScore: Double)] = []
    results.reserveCapacity(items.count)

    for item in items {
        let text = getText(item)
        var total: Double = 0
        var allMatch = true
        for tok in tokens {
            let m = fuzzyMatch(tok, text)
            if m.matches {
                total += m.score
            } else {
                allMatch = false
                break
            }
        }
        if allMatch {
            results.append((item: item, totalScore: total))
        }
    }

    results.sort { $0.totalScore < $1.totalScore }
    return results.map(\.item)
}
