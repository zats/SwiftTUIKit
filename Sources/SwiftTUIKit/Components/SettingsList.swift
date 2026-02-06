import Foundation

public struct SettingItem {
    public var id: String
    public var label: String
    public var description: String?
    public var currentValue: String
    public var values: [String]?
    public var submenu: ((_ currentValue: String, _ done: @escaping @Sendable (String?) -> Void) -> Component)?

    public init(
        id: String,
        label: String,
        description: String? = nil,
        currentValue: String,
        values: [String]? = nil,
        submenu: ((_ currentValue: String, _ done: @escaping @Sendable (String?) -> Void) -> Component)? = nil
    ) {
        self.id = id
        self.label = label
        self.description = description
        self.currentValue = currentValue
        self.values = values
        self.submenu = submenu
    }
}

public struct SettingsListTheme: Sendable {
    public var label: @Sendable (_ text: String, _ selected: Bool) -> String
    public var value: @Sendable (_ text: String, _ selected: Bool) -> String
    public var description: @Sendable (String) -> String
    public var cursor: String
    public var hint: @Sendable (String) -> String

    public init(
        label: @escaping @Sendable (_ text: String, _ selected: Bool) -> String = { t, _ in t },
        value: @escaping @Sendable (_ text: String, _ selected: Bool) -> String = { t, _ in t },
        description: @escaping @Sendable (String) -> String = { $0 },
        cursor: String = "→ ",
        hint: @escaping @Sendable (String) -> String = { $0 }
    ) {
        self.label = label
        self.value = value
        self.description = description
        self.cursor = cursor
        self.hint = hint
    }
}

public struct SettingsListOptions: Sendable, Equatable {
    public var enableSearch: Bool

    public init(enableSearch: Bool = false) {
        self.enableSearch = enableSearch
    }
}

public final class SettingsList: Component, Focusable, @unchecked Sendable {
    private var items: [SettingItem]
    private var filteredItems: [SettingItem]
    private let theme: SettingsListTheme
    private var selectedIndex: Int = 0
    private let maxVisible: Int
    private let onChange: @Sendable (_ id: String, _ newValue: String) -> Void
    private let onCancel: @Sendable () -> Void
    private let searchEnabled: Bool
    private let searchInput: Input?

    private var submenuComponent: Component?
    private var submenuItemIndex: Int?

    public var focused: Bool = false {
        didSet {
            searchInput?.focused = focused
            if let f = submenuComponent as? Focusable {
                f.focused = focused
            }
        }
    }

    public init(
        items: [SettingItem],
        maxVisible: Int = 6,
        theme: SettingsListTheme = .init(),
        onChange: @escaping @Sendable (_ id: String, _ newValue: String) -> Void,
        onCancel: @escaping @Sendable () -> Void,
        options: SettingsListOptions = .init()
    ) {
        self.items = items
        self.filteredItems = items
        self.maxVisible = max(1, maxVisible)
        self.theme = theme
        self.onChange = onChange
        self.onCancel = onCancel
        self.searchEnabled = options.enableSearch
        self.searchInput = options.enableSearch ? Input() : nil
    }

    public func updateValue(id: String, newValue: String) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].currentValue = newValue
        }
        if let idx = filteredItems.firstIndex(where: { $0.id == id }) {
            filteredItems[idx].currentValue = newValue
        }
    }

    public func invalidate() {
        submenuComponent?.invalidate()
    }

    public func render(width: Int) -> [String] {
        if let submenuComponent {
            return submenuComponent.render(width: width)
        }
        return renderMainList(width: width)
    }

    private func renderMainList(width: Int) -> [String] {
        var lines: [String] = []

        if searchEnabled, let searchInput {
            lines.append(contentsOf: searchInput.render(width: width))
            lines.append("")
        }

        if items.isEmpty {
            lines.append(theme.hint("  No settings available"))
            if searchEnabled { addHintLine(&lines, width: width) }
            return lines
        }

        let displayItems = searchEnabled ? filteredItems : items
        if displayItems.isEmpty {
            lines.append(ANSI.truncateToWidth(theme.hint("  No matching settings"), width: width, ellipsis: ""))
            addHintLine(&lines, width: width)
            return lines
        }

        let startIndex = max(
            0,
            min(selectedIndex - (maxVisible / 2), displayItems.count - maxVisible)
        )
        let endIndex = min(startIndex + maxVisible, displayItems.count)

        let maxLabelWidth: Int = min(30, items.map { ANSI.visibleWidth($0.label) }.max() ?? 0)

        for i in startIndex..<endIndex {
            let item = displayItems[i]
            let isSelected = (i == selectedIndex)
            let prefix = isSelected ? theme.cursor : "  "
            let prefixWidth = ANSI.visibleWidth(prefix)

            let labelPadded = item.label + String(repeating: " ", count: max(0, maxLabelWidth - ANSI.visibleWidth(item.label)))
            let labelText = theme.label(labelPadded, isSelected)

            let separator = "  "
            let usedWidth = prefixWidth + maxLabelWidth + ANSI.visibleWidth(separator)
            let valueMaxWidth = max(0, width - usedWidth - 2)
            let valueText = theme.value(ANSI.truncateToWidth(item.currentValue, width: valueMaxWidth, ellipsis: ""), isSelected)

            lines.append(ANSI.truncateToWidth(prefix + labelText + separator + valueText, width: width, ellipsis: ""))
        }

        if startIndex > 0 || endIndex < displayItems.count {
            let scrollText = "  (\(selectedIndex + 1)/\(displayItems.count))"
            lines.append(theme.hint(ANSI.truncateToWidth(scrollText, width: max(0, width - 2), ellipsis: "")))
        }

        if let selected = displayItems[safe: selectedIndex], let desc = selected.description, !desc.isEmpty {
            lines.append("")
            let wrapped = ANSI.wrapTextWithAnsi(desc, width: max(1, width - 4))
            for w in wrapped {
                lines.append(theme.description("  " + w))
            }
        }

        addHintLine(&lines, width: width)
        return lines
    }

    public func handleInput(_ event: InputEvent) {
        if let submenuComponent {
            submenuComponent.handleInput(event)
            return
        }

        guard case let .key(k) = event else {
            if case let .paste(s) = event, searchEnabled, let searchInput {
                searchInput.handleInput(.paste(s))
                applyFilter(searchInput.getValue())
            }
            return
        }

        let kb = getEditorKeybindings()
        let displayItems = searchEnabled ? filteredItems : items

        if kb.matches(k, action: .selectUp) {
            guard !displayItems.isEmpty else { return }
            selectedIndex = (selectedIndex == 0) ? (displayItems.count - 1) : (selectedIndex - 1)
            return
        }

        if kb.matches(k, action: .selectDown) {
            guard !displayItems.isEmpty else { return }
            selectedIndex = (selectedIndex == displayItems.count - 1) ? 0 : (selectedIndex + 1)
            return
        }

        if kb.matches(k, action: .selectConfirm) || k.key == .space {
            activateItem()
            return
        }

        if kb.matches(k, action: .selectCancel) {
            onCancel()
            return
        }

        if searchEnabled, let searchInput {
            // Treat non-navigation keys as search input.
            searchInput.handleInput(.key(k))
            applyFilter(searchInput.getValue())
        }
    }

    private func activateItem() {
        let item = (searchEnabled ? filteredItems : items)[safe: selectedIndex]
        guard let item else { return }

        if let submenu = item.submenu {
            let itemId = item.id
            submenuItemIndex = selectedIndex
            submenuComponent = submenu(item.currentValue) { [weak self] selectedValue in
                guard let self else { return }
                if let selectedValue {
                    self.updateValue(id: itemId, newValue: selectedValue)
                    self.onChange(itemId, selectedValue)
                }
                self.closeSubmenu()
            }
            return
        }

        if let values = item.values, !values.isEmpty {
            let idx = values.firstIndex(of: item.currentValue) ?? -1
            let next = (idx + 1) % values.count
            let newValue = values[next]
            updateValue(id: item.id, newValue: newValue)
            onChange(item.id, newValue)
        }
    }

    private func closeSubmenu() {
        submenuComponent = nil
        if let idx = submenuItemIndex {
            selectedIndex = idx
        }
        submenuItemIndex = nil
    }

    private func applyFilter(_ query: String) {
        filteredItems = fuzzyFilter(items, query: query) { $0.label }
        selectedIndex = 0
    }

    private func addHintLine(_ lines: inout [String], width: Int) {
        lines.append("")
        let msg = searchEnabled
            ? "  Type to search · Enter/Space to change · Esc to cancel"
            : "  Enter/Space to change · Esc to cancel"
        lines.append(ANSI.truncateToWidth(theme.hint(msg), width: width, ellipsis: ""))
    }
}

private extension Array {
    subscript(safe idx: Int) -> Element? {
        guard idx >= 0, idx < count else { return nil }
        return self[idx]
    }
}
