import Foundation

public struct AutocompleteItem: Sendable, Equatable {
    public var value: String
    public var label: String
    public var description: String?

    public init(value: String, label: String? = nil, description: String? = nil) {
        self.value = value
        self.label = label ?? value
        self.description = description
    }
}

public struct SlashCommand: Sendable {
    public var name: String
    public var description: String?
    public var getArgumentCompletions: (@Sendable (_ argumentPrefix: String) -> [AutocompleteItem]?)?

    public init(
        name: String,
        description: String? = nil,
        getArgumentCompletions: (@Sendable (_ argumentPrefix: String) -> [AutocompleteItem]?)? = nil
    ) {
        self.name = name
        self.description = description
        self.getArgumentCompletions = getArgumentCompletions
    }
}

public protocol AutocompleteProvider: AnyObject, Sendable {
    func getSuggestions(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int
    ) -> (items: [AutocompleteItem], prefix: String)?

    func applyCompletion(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int,
        item: AutocompleteItem,
        prefix: String
    ) -> (lines: [String], cursorLine: Int, cursorCol: Int)
}

public final class CombinedAutocompleteProvider: AutocompleteProvider, @unchecked Sendable {
    private enum CommandEntry {
        case command(SlashCommand)
        case item(AutocompleteItem)

        var name: String {
            switch self {
            case let .command(c): return c.name
            case let .item(i): return i.value
            }
        }

        var label: String {
            switch self {
            case let .command(c): return c.name
            case let .item(i): return i.label
            }
        }

        var description: String? {
            switch self {
            case let .command(c): return c.description
            case let .item(i): return i.description
            }
        }
    }

    private let commands: [CommandEntry]
    private let basePath: String
    private let fdPath: String?
    private let maxResults: Int

    private static let pathDelimiters: Set<Character> = [" ", "\t", "\"", "'", "="]

    public init(
        commands: [SlashCommand] = [],
        extraItems: [AutocompleteItem] = [],
        basePath: String = FileManager.default.currentDirectoryPath,
        fdPath: String? = nil,
        maxResults: Int = 200
    ) {
        self.basePath = basePath
        self.maxResults = max(10, maxResults)
        self.commands =
            commands.map { .command($0) } +
            extraItems.map { .item($0) }
        self.fdPath = fdPath ?? Self.resolveExecutable(named: "fd")
    }

    public func getSuggestions(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int
    ) -> (items: [AutocompleteItem], prefix: String)? {
        let currentLine = (cursorLine >= 0 && cursorLine < lines.count) ? lines[cursorLine] : ""
        let beforeCursor = String(currentLine.prefix(max(0, cursorCol)))

        if let atPrefix = extractAtPrefix(beforeCursor) {
            let parsed = parsePathPrefix(atPrefix)
            let items = getFuzzyFileSuggestions(rawPrefix: parsed.rawPrefix, isAtPrefix: parsed.isAtPrefix, isQuotedPrefix: parsed.isQuotedPrefix)
            if items.isEmpty { return nil }
            return (items: items, prefix: atPrefix)
        }

        // Slash commands: only at the beginning of the line.
        if beforeCursor.hasPrefix("/") {
            if let spaceIdx = beforeCursor.firstIndex(of: " ") {
                let cmdName = String(beforeCursor[beforeCursor.index(after: beforeCursor.startIndex)..<spaceIdx])
                let argPrefix = String(beforeCursor[beforeCursor.index(after: spaceIdx)...])

                guard let cmd = commands.compactMap({ entry -> SlashCommand? in
                    if case let .command(c) = entry, c.name == cmdName { return c }
                    return nil
                }).first else { return nil }

                guard let getArgs = cmd.getArgumentCompletions else { return nil }
                guard let argItems = getArgs(argPrefix), !argItems.isEmpty else { return nil }

                return (items: argItems, prefix: argPrefix)
            }

            let prefix = String(beforeCursor.dropFirst())
            let haystack: [AutocompleteItem] = commands.map {
                AutocompleteItem(value: $0.name, label: $0.label, description: $0.description)
            }
            let filtered = fuzzyFilter(haystack, query: prefix, getText: { $0.value })
            if filtered.isEmpty { return nil }
            return (items: filtered, prefix: beforeCursor)
        }

        return nil
    }

    public func applyCompletion(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int,
        item: AutocompleteItem,
        prefix: String
    ) -> (lines: [String], cursorLine: Int, cursorCol: Int) {
        var outLines = lines
        if outLines.isEmpty { outLines = [""] }
        let lineIdx = max(0, min(cursorLine, outLines.count - 1))
        let currentLine = outLines[lineIdx]

        let col = max(0, min(cursorCol, currentLine.count))
        let before = String(currentLine.prefix(col))
        let after = String(currentLine.dropFirst(col))

        if before.hasPrefix("/") {
            // Command name completion.
            if !before.contains(" ") {
                let newBefore = "/" + item.value + " "
                outLines[lineIdx] = newBefore + after
                return (outLines, lineIdx, newBefore.count)
            }
            // Command argument completion: `prefix` is the arg prefix.
            let argStart = before.count - prefix.count
            let newBefore = String(before.prefix(argStart)) + item.value + " "
            outLines[lineIdx] = newBefore + after
            return (outLines, lineIdx, newBefore.count)
        }

        // File completion: replace the provided prefix at the end of before-cursor.
        let start = max(0, before.count - prefix.count)
        let completion = item.value
        let newBefore = String(before.prefix(start)) + completion
        outLines[lineIdx] = newBefore + after
        return (outLines, lineIdx, newBefore.count)
    }

    // MARK: - @ File Prefix

    private func extractAtPrefix(_ textBeforeCursor: String) -> String? {
        // Look for an unclosed quote which may contain an @ path.
        if let quoted = extractQuotedPrefix(textBeforeCursor) {
            return quoted
        }

        // Otherwise: use the last delimiter-based token.
        let lastDelim = findLastDelimiter(textBeforeCursor)
        let token = lastDelim >= 0 ? String(textBeforeCursor[textBeforeCursor.index(textBeforeCursor.startIndex, offsetBy: lastDelim + 1)...]) : textBeforeCursor
        if token.hasPrefix("@") {
            return token
        }
        return nil
    }

    private func findLastDelimiter(_ s: String) -> Int {
        let chars = Array(s)
        for i in stride(from: chars.count - 1, through: 0, by: -1) {
            if Self.pathDelimiters.contains(chars[i]) { return i }
        }
        return -1
    }

    private func findUnclosedQuoteStart(_ s: String) -> Int? {
        var inQuotes = false
        var quoteStart = -1
        for (i, ch) in s.enumerated() {
            if ch == "\"" {
                inQuotes.toggle()
                if inQuotes { quoteStart = i }
            }
        }
        return inQuotes ? quoteStart : nil
    }

    private func isTokenStart(_ s: String, index: Int) -> Bool {
        if index == 0 { return true }
        let chars = Array(s)
        let prev = chars[index - 1]
        return Self.pathDelimiters.contains(prev)
    }

    private func extractQuotedPrefix(_ s: String) -> String? {
        guard let quoteStart = findUnclosedQuoteStart(s) else { return nil }

        if quoteStart > 0, Array(s)[quoteStart - 1] == "@" {
            if !isTokenStart(s, index: quoteStart - 1) { return nil }
            let start = s.index(s.startIndex, offsetBy: quoteStart - 1)
            return String(s[start...])
        }

        if !isTokenStart(s, index: quoteStart) { return nil }
        let start = s.index(s.startIndex, offsetBy: quoteStart)
        return String(s[start...])
    }

    private func parsePathPrefix(_ prefix: String) -> (rawPrefix: String, isAtPrefix: Bool, isQuotedPrefix: Bool) {
        if prefix.hasPrefix("@\"") {
            return (rawPrefix: String(prefix.dropFirst(2)), isAtPrefix: true, isQuotedPrefix: true)
        }
        if prefix.hasPrefix("\"") {
            return (rawPrefix: String(prefix.dropFirst(1)), isAtPrefix: false, isQuotedPrefix: true)
        }
        if prefix.hasPrefix("@") {
            return (rawPrefix: String(prefix.dropFirst(1)), isAtPrefix: true, isQuotedPrefix: false)
        }
        return (rawPrefix: prefix, isAtPrefix: false, isQuotedPrefix: false)
    }

    private func buildCompletionValue(
        path: String,
        isDirectory: Bool,
        isAtPrefix: Bool,
        isQuotedPrefix: Bool
    ) -> String {
        let needsQuotes = isQuotedPrefix || path.contains(" ")
        let prefix = isAtPrefix ? "@" : ""
        let completionPath = isDirectory && !path.hasSuffix("/") ? path + "/" : path

        if !needsQuotes {
            return prefix + completionPath
        }

        return prefix + "\"" + completionPath + "\""
    }

    // MARK: - File Suggestions

    private func getFuzzyFileSuggestions(rawPrefix: String, isAtPrefix: Bool, isQuotedPrefix: Bool) -> [AutocompleteItem] {
        let expanded = expandTilde(rawPrefix)

        let (dirPart, queryPart): (String, String) = {
            if let slash = expanded.lastIndex(of: "/") {
                let d = String(expanded[..<slash])
                let q = String(expanded[expanded.index(after: slash)...])
                return (d.isEmpty ? "." : d, q)
            }
            return (".", expanded)
        }()

        let baseDir = resolveBaseDir(dirPart)
        let candidates = walkDirectory(baseDir: baseDir, query: queryPart, maxResults: maxResults)

        let filtered = fuzzyFilter(candidates, query: queryPart) { $0.path }

        return filtered.prefix(30).map { c in
            let v = buildCompletionValue(
                path: c.path,
                isDirectory: c.isDirectory,
                isAtPrefix: isAtPrefix,
                isQuotedPrefix: isQuotedPrefix
            )
            return AutocompleteItem(value: v, label: c.path, description: c.isDirectory ? "directory" : nil)
        }
    }

    private func resolveBaseDir(_ dirPart: String) -> String {
        if dirPart.hasPrefix("/") { return dirPart }
        if dirPart.hasPrefix("~") { return expandTilde(dirPart) }
        return (basePath as NSString).appendingPathComponent(dirPart)
    }

    private func expandTilde(_ s: String) -> String {
        if s.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            if s == "~" { return home }
            if s.hasPrefix("~/") { return home + String(s.dropFirst(1)) }
        }
        return s
    }

    private struct WalkResult: Sendable {
        var path: String
        var isDirectory: Bool
    }

    private func walkDirectory(baseDir: String, query: String, maxResults: Int) -> [WalkResult] {
        if let fdPath {
            let results = walkDirectoryWithFd(baseDir: baseDir, fdPath: fdPath, query: query, maxResults: maxResults)
            if !results.isEmpty { return results }
        }

        // Fallback: shallow-ish recursive walk. We stop after maxResults.
        var out: [WalkResult] = []
        out.reserveCapacity(min(256, maxResults))

        let fm = FileManager.default
        let url = URL(fileURLWithPath: baseDir)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        let opts: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        let en = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: opts)
        while let next = en?.nextObject() as? URL {
            if out.count >= maxResults { break }
            if next.path.contains("/.git/") { continue }
            let name = next.lastPathComponent
            if name == ".git" { continue }
            let res = try? next.resourceValues(forKeys: Set(keys))
            let isDir = res?.isDirectory ?? false
            let rel = next.path.replacingOccurrences(of: url.path + "/", with: "")
            out.append(WalkResult(path: rel + (isDir ? "/" : ""), isDirectory: isDir))
        }

        return out
    }

    private func walkDirectoryWithFd(baseDir: String, fdPath: String, query: String, maxResults: Int) -> [WalkResult] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: fdPath)
        p.currentDirectoryURL = URL(fileURLWithPath: baseDir)

        var args: [String] = [
            "--max-results", String(maxResults),
            "--type", "f",
            "--type", "d",
            "--full-path",
            "--hidden",
            "--exclude", ".git",
            "--exclude", ".git/*",
            "--exclude", ".git/**",
        ]
        if !query.isEmpty {
            args.append(query)
        }
        p.arguments = args

        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = Pipe()

        do {
            try p.run()
        } catch {
            return []
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return [] }

        let s = String(decoding: data, as: UTF8.self)
        if s.isEmpty { return [] }

        var out: [WalkResult] = []
        out.reserveCapacity(64)

        for line in s.split(separator: "\n") {
            if out.count >= maxResults { break }
            let raw = String(line)
            if raw == ".git" || raw.hasPrefix(".git/") || raw.contains("/.git/") { continue }
            let isDir = raw.hasSuffix("/")
            out.append(WalkResult(path: raw, isDirectory: isDir))
        }

        return out
    }

    private static func resolveExecutable(named name: String) -> String? {
        let env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? ""
        for p in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(p)).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}
