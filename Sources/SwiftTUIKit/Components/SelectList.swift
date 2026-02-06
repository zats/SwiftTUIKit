import Foundation

public struct SelectItem: Sendable, Equatable {
    public var value: String
    public var label: String
    public var description: String?

    public init(value: String, label: String? = nil, description: String? = nil) {
        self.value = value
        self.label = label ?? value
        self.description = description
    }
}

public struct SelectListTheme: Sendable {
    public var selectedText: @Sendable (String) -> String
    public var description: @Sendable (String) -> String
    public var scrollInfo: @Sendable (String) -> String
    public var noMatch: @Sendable (String) -> String

    public init(
        selectedText: @escaping @Sendable (String) -> String = { $0 },
        description: @escaping @Sendable (String) -> String = { $0 },
        scrollInfo: @escaping @Sendable (String) -> String = { $0 },
        noMatch: @escaping @Sendable (String) -> String = { $0 }
    ) {
        self.selectedText = selectedText
        self.description = description
        self.scrollInfo = scrollInfo
        self.noMatch = noMatch
    }
}

public final class SelectList: Component, @unchecked Sendable {
    private var items: [SelectItem]
    private var filteredItems: [SelectItem]
    private var selectedIndex: Int
    private var maxVisible: Int
    private let theme: SelectListTheme

    public var onSelect: (@Sendable (SelectItem) -> Void)?
    public var onCancel: (@Sendable () -> Void)?
    public var onSelectionChange: (@Sendable (SelectItem) -> Void)?

    public init(items: [SelectItem], maxVisible: Int = 5, theme: SelectListTheme = .init()) {
        self.items = items
        self.filteredItems = items
        self.selectedIndex = 0
        self.maxVisible = max(1, maxVisible)
        self.theme = theme
    }

    public func setItems(_ items: [SelectItem]) {
        self.items = items
        self.filteredItems = items
        self.selectedIndex = 0
    }

    public func setFilter(_ filter: String) {
        let f = filter.lowercased()
        filteredItems = items.filter { $0.value.lowercased().hasPrefix(f) }
        selectedIndex = 0
    }

    public func setSelectedIndex(_ index: Int) {
        selectedIndex = max(0, min(index, filteredItems.count - 1))
    }

    public func getSelectedItem() -> SelectItem? {
        guard selectedIndex >= 0, selectedIndex < filteredItems.count else { return nil }
        return filteredItems[selectedIndex]
    }

    public func invalidate() {}

    public func render(width: Int) -> [String] {
        var lines: [String] = []

        if filteredItems.isEmpty {
            lines.append(theme.noMatch("  No matching commands"))
            return lines
        }

        let maxVisible = max(1, self.maxVisible)
        let startIndex = max(
            0,
            min(selectedIndex - (maxVisible / 2), filteredItems.count - maxVisible)
        )
        let endIndex = min(startIndex + maxVisible, filteredItems.count)

        for i in startIndex..<endIndex {
            let item = filteredItems[i]
            let isSelected = (i == selectedIndex)
            let descSingle = item.description.map(normalizeToSingleLine)

            let displayValue = item.label
            let prefix = isSelected ? "→ " : "  "
            let prefixWidth = ANSI.visibleWidth(prefix)

            if isSelected {
                if let descSingle, width > 40 {
                    let maxValueWidth = min(30, width - prefixWidth - 4)
                    let truncatedValue = ANSI.truncateToWidth(displayValue, width: maxValueWidth, ellipsis: "")
                    let spacing = String(repeating: " ", count: max(1, 32 - ANSI.visibleWidth(truncatedValue)))
                    let descStart = prefixWidth + ANSI.visibleWidth(truncatedValue) + ANSI.visibleWidth(spacing)
                    let remaining = width - descStart - 2
                    if remaining > 10 {
                        let truncatedDesc = ANSI.truncateToWidth(descSingle, width: remaining, ellipsis: "")
                        lines.append(theme.selectedText(prefix + truncatedValue + spacing + truncatedDesc))
                    } else {
                        let maxW = width - prefixWidth - 2
                        lines.append(theme.selectedText(prefix + ANSI.truncateToWidth(displayValue, width: maxW, ellipsis: "")))
                    }
                } else {
                    let maxW = width - prefixWidth - 2
                    lines.append(theme.selectedText(prefix + ANSI.truncateToWidth(displayValue, width: maxW, ellipsis: "")))
                }
                continue
            }

            // Not selected.
            if let descSingle, width > 40 {
                let maxValueWidth = min(30, width - prefixWidth - 4)
                let truncatedValue = ANSI.truncateToWidth(displayValue, width: maxValueWidth, ellipsis: "")
                let spacing = String(repeating: " ", count: max(1, 32 - ANSI.visibleWidth(truncatedValue)))
                let descStart = prefixWidth + ANSI.visibleWidth(truncatedValue) + ANSI.visibleWidth(spacing)
                let remaining = width - descStart - 2
                if remaining > 10 {
                    let truncatedDesc = ANSI.truncateToWidth(descSingle, width: remaining, ellipsis: "")
                    let descText = theme.description(spacing + truncatedDesc)
                    lines.append(prefix + truncatedValue + descText)
                } else {
                    let maxW = width - prefixWidth - 2
                    lines.append(prefix + ANSI.truncateToWidth(displayValue, width: maxW, ellipsis: ""))
                }
            } else {
                let maxW = width - prefixWidth - 2
                lines.append(prefix + ANSI.truncateToWidth(displayValue, width: maxW, ellipsis: ""))
            }
        }

        if startIndex > 0 || endIndex < filteredItems.count {
            let scrollText = "  (\(selectedIndex + 1)/\(filteredItems.count))"
            lines.append(theme.scrollInfo(ANSI.truncateToWidth(scrollText, width: max(0, width - 2), ellipsis: "")))
        }

        return lines
    }

    public func handleInput(_ event: InputEvent) {
        guard case let .key(k) = event else { return }

        let kb = getEditorKeybindings()

        if kb.matches(k, action: .selectUp) {
            if filteredItems.isEmpty { return }
            selectedIndex = (selectedIndex == 0) ? (filteredItems.count - 1) : (selectedIndex - 1)
            notifySelectionChange()
        } else if kb.matches(k, action: .selectDown) {
            if filteredItems.isEmpty { return }
            selectedIndex = (selectedIndex == filteredItems.count - 1) ? 0 : (selectedIndex + 1)
            notifySelectionChange()
        } else if kb.matches(k, action: .selectConfirm) {
            if let item = getSelectedItem() { onSelect?(item) }
        } else if kb.matches(k, action: .selectCancel) {
            onCancel?()
        }
    }

    private func notifySelectionChange() {
        if let item = getSelectedItem() {
            onSelectionChange?(item)
        }
    }

    private func normalizeToSingleLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

