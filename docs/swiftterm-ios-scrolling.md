# SwiftTerm iOS Scrolling Architecture

This document details how SwiftTerm's `TerminalView` handles scrolling on iOS, the limitations discovered, and how Ctrlx works around them.

> **SwiftTerm Version**: 1.9.0 (from Package.swift dependency)

## Overview

SwiftTerm's iOS `TerminalView` is a `UIScrollView` subclass that handles terminal rendering and scrollback navigation. Ctrlx wraps it in an additional scroll view to support wide terminals (horizontal scrolling), creating a nested scroll view architecture.

## SwiftTerm Source Files

| File | Purpose |
|------|---------|
| `iOSTerminalView.swift` | iOS-specific TerminalView implementation |
| `AppleTerminalView.swift` | Shared rendering code (iOS + macOS) |

## Vertical Scrolling (Scrollback)

SwiftTerm fully supports vertical scrolling for terminal scrollback history.

### How It Works

1. **Content Size**: Set based on total buffer lines
   ```swift
   contentSize = CGSize(
       width: CGFloat(displayBuffer.cols) * cellDimension.width,
       height: CGFloat(displayBuffer.lines.count) * cellDimension.height
   )
   ```

2. **Scroll Position**: `contentOffset.y` determines which buffer lines are visible
   ```swift
   // In visibleRows calculation
   let topVisibleLine = contentOffset.y / cellDimension.height
   let bottomVisibleLine = topVisibleLine + frame.height / cellDimension.height - 1
   ```

3. **Rendering**: `drawTerminalContents()` uses `contentOffset.y` to determine which rows to render

### Scroll Methods

| Method | Description |
|--------|-------------|
| `scroll(toPosition: Double)` | Normalized position (0.0 = top, 1.0 = cursor position) |
| `scrollUp(lines: Int)` | Scroll up by N lines |
| `scrollDown(lines: Int)` | Scroll down by N lines |
| `scrollTo(row: Int)` | Jump to specific row |
| `pageUp()` / `pageDown()` | Scroll by one page |

### Important Note

`scroll(toPosition: 1)` scrolls to the **cursor position**, not necessarily the absolute bottom of content. The cursor is typically at the bottom, but this distinction matters.

## Horizontal Scrolling (NOT Supported)

**Critical Finding**: SwiftTerm does NOT support horizontal scrolling for wide terminals.

### Evidence

1. **contentOffset.x is hardcoded to 0** in `updateScroller()`:
   ```swift
   // iOSTerminalView.swift:992
   contentOffset = CGPoint(x: 0, y: CGFloat(displayBuffer.lines.count - displayBuffer.rows) * cellDimension.height)
   ```

2. **Rendering ignores contentOffset.x** - `lineOrigin.x` is always 0:
   ```swift
   // AppleTerminalView.swift:1209
   let lineOrigin = CGPoint(x: 0, y: frame.height - offset)
   ```

3. **No horizontal scroll gesture handling** - While `showsHorizontalScrollIndicator = true` is set, the terminal content won't pan horizontally.

### Impact

For wide terminals (more columns than fit on screen), the content is clipped on the right. There's no way to scroll horizontally to see clipped content using SwiftTerm alone.

## Ctrlx's Solution: Outer Scroll View + Content-Sized Terminal

Ctrlx wraps TerminalView in an outer UIScrollView. The terminal view is sized to match the terminal content exactly, and the outer scroll view handles both horizontal (wide terminals) and vertical (tall terminals) scrolling.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Outer UIScrollView (horizontal + vertical scrolling)        │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ InteractiveTerminalView (SwiftTerm subclass)            │ │
│ │ - Width: exact terminal width (cols × cellWidth)        │ │
│ │ - Height: exact terminal height (rows × cellHeight)     │ │
│ │ - Min height = screen height (short terminals fill it)  │ │
│ │ - SwiftTerm handles scrollback via internal scrolling   │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Why This Works

1. **TerminalView width = exact terminal width**: SwiftTerm renders all columns
2. **TerminalView height = exact terminal height**: SwiftTerm's `processSizeChange` sees a frame that matches the host terminal dimensions, so it never resizes the buffer
3. **Minimum height = screen height**: Short terminals fill the screen (no gap at bottom)
4. **Outer scroll view**: Handles horizontal scrolling for wide terminals AND vertical scrolling when the terminal is taller than the screen (e.g., a 65-row host on a ~53-row iPhone)
5. **SwiftTerm internal scroll**: Handles scrollback history navigation

### The Problem: SwiftTerm Auto-Resize Destroys Content

SwiftTerm's `layoutSubviews` calls `processSizeChange(newSize: bounds.size)`, which computes `newRows = height / cellHeight` and resizes the terminal buffer to match. When the host terminal has more rows than fit on the iOS screen (e.g., a 65-row macOS terminal on a ~53-row iPhone), SwiftTerm shrinks the buffer, destroying bottom rows including DECSTBM scroll region footers (see GitHub issue #244).

### The Fix: Content-Sized Terminal View

Instead of constraining the terminal view to the screen height and fighting SwiftTerm's auto-resize, the terminal view is constrained to match the terminal content height exactly:

```swift
// Height: at least screen height, prefers exact terminal height
terminalView.heightAnchor.constraint(
    greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor
)
let heightConstraint = terminalView.heightAnchor.constraint(
    equalToConstant: exactHeight
)
heightConstraint.priority = .defaultHigh
```

This ensures:
- **Short terminals** (rows fit on screen): `greaterThanOrEqualTo` fills the screen, SwiftTerm resizes to match — identical behavior to before
- **Tall terminals** (rows exceed screen): `equalToConstant` at `.defaultHigh` expands the view to fit all rows, SwiftTerm's `processSizeChange` sees the correct frame and preserves all rows including footers
- **No buffer corruption**: SwiftTerm never resizes the buffer to a smaller size, so no rows are destroyed
- **Natural scrolling**: The outer scroll view provides vertical scrolling to reach footer content, same as horizontal scrolling for wide terminals

### Previous Approach: Managed Terminal Size (Abandoned)

An earlier attempt used a `managedTerminalSize` property to restore terminal dimensions after SwiftTerm's `layoutSubviews` shrunk the buffer. This approach had fundamental issues:

1. **Buffer corruption**: The resize dance (65→53→65) during layout pushed rows to scrollback then pulled them back, corrupting buffer state
2. **Scroll position conflicts**: SwiftTerm's `updateScroller` and `scrolled(source:yDisp:)` callbacks reset `contentOffset` based on `displayBuffer.rows`, conflicting with our positioning
3. **cellHeight mismatches**: FontMetrics calculations differed slightly from SwiftTerm's internal `cellDimension`, making cursor-aware scroll positioning unreliable
4. **Complex workarounds**: Required overriding `sizeChanged`, `contentOffset`, `blockScrollChanges` flags, and async dispatch chains — all fragile and interdependent

The content-sized approach avoids all these issues by working WITH SwiftTerm's layout instead of against it.

## InteractiveTerminalView Subclass

Ctrlx extends SwiftTerm's `TerminalView` with `InteractiveTerminalView`:

### Features

1. **Keyboard Input Control**
   ```swift
   var inputEnabled = false
   override var canBecomeFirstResponder: Bool { inputEnabled }
   ```

2. **Scroll Preservation During Updates**
   ```swift
   var preserveUserScroll = false
   private var blockScrollChanges = false

   override var contentOffset: CGPoint {
       get { super.contentOffset }
       set {
           if blockScrollChanges { return }
           super.contentOffset = newValue
       }
   }
   ```

3. **Feed with Scroll Preservation**
   ```swift
   func feedPreservingScroll(_ bytes: ArraySlice<UInt8>) {
       if preserveUserScroll {
           let maxScrollY = max(0, contentSize.height - bounds.height)
           let isAtBottom = maxScrollY <= 0 || super.contentOffset.y >= maxScrollY - 5
           blockScrollChanges = !isAtBottom
       }
       feed(byteArray: bytes)
       blockScrollChanges = false
       setNeedsLayout()
   }
   ```

   This prevents new content from auto-scrolling when the user has scrolled up to read history.

## TerminalState Bridge

`TerminalState` is an `@Observable` class that bridges SwiftUI and UIKit:

| Property/Callback | Purpose |
|-------------------|---------|
| `onData` | Feed data to terminal |
| `onResize` | Handle dimension changes |
| `scrollToBottom` | Scroll terminal to bottom (callable from SwiftUI) |
| `makeTextSnapshot` | Capture retained local terminal text for the copy surface |
| `onInitialContentLoaded` | Called once after initial content is fed |

### Scroll-to-Bottom Implementation

Both the inner terminal (scrollback) and outer scroll view (tall terminal overflow) are scrolled:

```swift
terminalState.scrollToBottom = { [weak terminalView, weak scrollView] in
    guard let terminalView else { return }
    // Inner: scroll SwiftTerm's scrollback to bottom
    terminalView.scrollToBottom()
    // Outer: scroll to show the bottom of a tall terminal
    if let scrollView {
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        scrollView.contentOffset.y = maxY
    }
}
```

Called on:
- Initial content load (after 100ms delay for layout)
- Keyboard show (after 350ms delay for animation)

## Key Constraints and Limitations

### Text Selection Across the Outer Viewport

SwiftTerm owns its selection gesture and only auto-scrolls when the drag leaves the
`TerminalView` bounds. Gallager's `TerminalView` bounds cover the complete host-sized
terminal, while the iPhone shows only a smaller rectangle through the outer scroll view.
Reaching the phone edge therefore does not leave the terminal bounds, so SwiftTerm never
scrolls and the selection cannot extend into content outside the outer viewport. The same
ownership mismatch affects horizontal selection.

Resizing is not an appropriate copy workaround:

- Sending `ResizeTmuxPane` ultimately runs `tmux resize-window`, changing the shared tmux
  window for the Mac and every viewer.
- Resizing only the local SwiftTerm buffer makes it disagree with control sequences emitted
  for the host dimensions and reintroduces the buffer corruption described above.
- Multiple viewers would compete for the shared window size and require fragile restoration
  when a viewer disconnects.

The first-stage copy solution therefore keeps the terminal dimensions unchanged and creates
a static text snapshot from the local SwiftTerm buffer only when requested. A native read-only
text view owns selection in that snapshot, so iOS provides normal cross-screen selection,
copy, and Select All without a relay request. The live terminal remains the source of truth;
closing and reopening the copy view refreshes the snapshot.

The snapshot walks SwiftTerm's active scroll-invariant lines, including retained scrollback,
and removes only terminal cell padding on the right. It explicitly skips the null cells that
follow wide characters; SwiftTerm's generic buffer export does not do that and would put an
invisible NUL after Chinese or other double-width glyphs. Alternate-screen applications are
read from the active alternate buffer rather than stale normal-buffer history.

Only the selected pane contributes the toolbar action in a multi-pane layout. This avoids
duplicated toolbar items and makes the copied buffer unambiguous. The sheet receives an
immutable value: new terminal output continues normally but cannot move or invalidate the
user's current selection.

A later enhancement may teach the SwiftTerm fork about the outer visible rectangle and make
selection-handle drags scroll the outer view. That is a direct-manipulation improvement, not a
reason to change tmux sizing.

### SwiftTerm Limitations

| Limitation | Impact | Workaround |
|------------|--------|------------|
| No horizontal scrolling | Wide terminals clipped | Outer scroll view wrapper |
| contentOffset.x always 0 | Can't pan horizontally in terminal | Outer scroll view |
| Frame = terminal size expected | Can't make terminal smaller than buffer | Accept full-size frame |
| updateScroller() not overridable | Can't customize scroll behavior | Content-sized view avoids the need |

### Ctrlx Constraints

| Constraint | Reason |
|------------|--------|
| Terminal dimensions from Mac | Must display exact same content |
| Need horizontal scroll | Mac terminals often wider than phone |
| Need scroll preservation | Don't lose place when content updates |
| Single-scroll UX | Users expect one scroll gesture |

## Future Improvements

### Option: Contribute to SwiftTerm

To enable native horizontal scrolling:

1. Modify `updateScroller()` to preserve `contentOffset.x`
2. Modify `drawTerminalContents()` to offset rendering by `contentOffset.x`
3. Add configuration for horizontal scroll behavior

This would allow eliminating the outer scroll view entirely.

### Current Status

The content-sized terminal view approach works correctly for both short and tall terminals. SwiftTerm handles its own buffer sizing naturally, and the outer scroll view provides horizontal and vertical scrolling as needed. The complexity is minimal — just Auto Layout constraints in `TerminalStreamContainerView`.

## References

### SwiftTerm Source (from .build/checkouts/)

- `SwiftTerm/Sources/SwiftTerm/iOS/iOSTerminalView.swift`
- `SwiftTerm/Sources/SwiftTerm/Apple/AppleTerminalView.swift`

### Ctrlx Source

- `CtrlxPackage/Sources/CtrlxFeature/Views/LiveTerminalView.swift` - Main terminal view
- `CtrlxPackage/Sources/CtrlxFeature/Views/InteractiveTerminalView.swift` - SwiftTerm subclass
