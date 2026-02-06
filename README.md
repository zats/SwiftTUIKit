# SwiftTUIKit

SwiftTUIKit is a minimal terminal UI (TUI) framework for interactive CLI apps.
It is a Swift port of the TUI library in `pi-mono/packages/tui`, with a component
API and a small SwiftUI-like builder DSL.

This package is designed to run in a real TTY (Terminal, iTerm2, Kitty, tmux).
It will generally not behave correctly in Xcode's Run console.

## Features

- Flicker-free rendering via synchronized output (DECSET 2026) when supported
- Bracketed paste mode support (handles multi-line pastes reliably)
- Component-based rendering (`Component.render(width:) -> [String]`)
- Focus + IME cursor placement via a zero-width cursor marker
- Overlays (dialogs/menus) rendered on top of existing content
- Autocomplete helpers (slash commands + `@` file path completion)
- Inline images (Kitty / iTerm2 graphics protocols) with fallback text

## Installation (SwiftPM)

```swift
// Package.swift
// Option A: local development dependency (relative path)
.package(path: "../SwiftTUIKit"),

// Option B: Git dependency (replace with your fork/org)
// .package(url: "https://github.com/<your-org>/SwiftTUIKit.git", branch: "main"),
```

Then add the product to your target:

```swift
.target(
  name: "YourApp",
  dependencies: [
    .product(name: "SwiftTUIKit", package: "SwiftTUIKit"),
  ]
)
```

## Quick Start

The DSL is intentionally small and is not a full SwiftUI reimplementation. It
is meant to make simple layouts less verbose.

```swift
import SwiftTUIKit

let tui = TUI {
  VStack {
    Text("Hello from SwiftTUIKit", paddingX: 1, paddingY: 1)
    Spacer(lines: 1)
    TruncatedText("This will be truncated to the terminal width", paddingX: 1, paddingY: 0)
  }
}

tui.start()
dispatchMain()
```

## Components

All components conform to:

```swift
public protocol Component: AnyObject, Sendable {
  func render(width: Int) -> [String]
  func handleInput(_ event: InputEvent)
  func invalidate()
  var wantsKeyRelease: Bool { get }
}
```

Built-in components:

- `Text`: wraps text, optional padding/background
- `TruncatedText`: single-line truncate-to-width
- `Spacer`: vertical spacing
- `Box`: container with padding + optional background
- `Input`: single-line input with cursor windowing, paste support
- `Editor`: multi-line editor with optional autocomplete UI (SelectList)
- `Markdown`: minimal markdown renderer with a theme API
- `Loader`: spinner text that updates periodically
- `CancellableLoader`: loader that exposes an abort signal and cancels on Esc/Ctrl+C
- `SelectList`: selectable list UI (up/down/enter/esc)
- `SettingsList`: settings UI with optional fuzzy search and submenu support
- `Image`: Kitty/iTerm2 inline image rendering (with fallback text)

Containers:

- `Container`: composes children by concatenating their rendered lines
- `TUI`: the root container + renderer + input/focus management

## Overlays

Overlays are components composited on top of the base UI.

```swift
let handle = tui.showOverlay(myDialog, options: {
  var o = OverlayOptions()
  o.width = .absolute(60)
  o.maxHeight = .percent(50)
  o.anchor = .center
  o.marginAll = 2
  return o
}())

handle.setHidden(true)
handle.setHidden(false)
handle.hide()
```

## IME Cursor Placement (Focusable)

For CJK input methods, focused components can emit a cursor marker at the cursor
location so the hardware cursor can be positioned there.

Use `ANSI.cursorMarker` immediately before the cell you draw as your "fake"
cursor. When `PI_HARDWARE_CURSOR=1`, `TUI` will place the hardware cursor at the
marker and show it.

`Input` and `Editor` already do this.

## Examples

This package ships multiple executable examples (run them from a real terminal):

```sh
swift run SwiftTUIKitExampleChatSimple
swift run SwiftTUIKitExampleKeyTester
swift run SwiftTUIKitExampleOverlayDemo
swift run SwiftTUIKitExampleSelectList
swift run SwiftTUIKitExampleSettingsList
swift run SwiftTUIKitExampleMarkdown
swift run SwiftTUIKitExampleEditor
swift run SwiftTUIKitExampleImage
```

## Environment Variables

- `PI_HARDWARE_CURSOR=1`: show and position the hardware cursor using `ANSI.cursorMarker`
- `PI_CLEAR_ON_SHRINK=1`: full redraw when line count shrinks
- `PI_TUI_WRITE_LOG=/path/to/log.txt`: append raw TUI writes to a file

## Known Limitations

- ANSI slicing/wrapping is best-effort (style-state tracking is intentionally minimal).
- Unicode width is heuristic (good enough for most usage, but not perfect for every grapheme).
- Rendering is "diff-ish" but not a byte-perfect match of the original TS renderer.

## Development

```sh
swift test
swift build
```
