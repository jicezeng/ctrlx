#if os(iOS)
    import CtrlxNetworking
    @testable import SwiftTerm
    import Testing
    import UIKit
    import XCTest
    @testable import CtrlxFeature

    @MainActor
    @Suite("Terminal input-row selection routing", .serialized)
    struct TerminalSelectionRoutingTests {
        @Test("The whole current input row opts out, including blank cells and wide glyphs")
        func inputRow() throws {
            let (window, view) = makeView()
            defer { close(window, view) }
            view.feed(text: "正文\r\n> 中🙂 input")
            view.scroll(toPosition: 1)
            let terminal = view.getTerminal()
            let row = terminal.buffer.y + terminal.buffer.yDisp
            let proxy = try #require(window.rootViewController?.view.subviews
                .compactMap { $0 as? UIScrollView }.first?.subviews
                .compactMap { $0 as? TerminalInputProxyView }.first)
            #expect(proxy.isFirstResponder)

            var sentKeys = 0
            var sentBytes = 0
            view.onInput = { sentKeys += $0.count }
            view.onRawInput = { sentBytes += $0.count }
            for column in [0, 2, 3, terminal.buffer.x, terminal.cols - 1] {
                #expect(!view.shouldBeginSelection(at: Position(col: column, row: row)))
            }
            #expect(view.shouldBeginSelection(at: Position(col: 0, row: row - 1)))
            #expect(view.shouldBeginSelection(at: Position(col: 0, row: row + 1)))
            #expect(sentKeys == 0)
            #expect(sentBytes == 0)
            #expect(!view.selectionActive)
        }

        @Test("History, inactive input and mouse-mode TUIs retain selection")
        func selectionFallbacks() {
            let (window, view) = makeView()
            defer { close(window, view) }
            for line in 0..<100 {
                view.feed(text: "history \(line)\r\n")
            }
            view.scroll(toPosition: 1)
            let terminal = view.getTerminal()
            let input = Position(col: 0, row: terminal.buffer.y + terminal.buffer.yDisp)
            #expect(!view.shouldBeginSelection(at: input))

            view.updateInput(isEnabled: false, keyboardRequested: false)
            #expect(view.shouldBeginSelection(at: input))
            view.updateInput(isEnabled: true, keyboardRequested: false)

            view.feed(text: "\u{1b}[?1000h")
            #expect(view.shouldBeginSelection(at: input))
            view.feed(text: "\u{1b}[?1000l")
            #expect(!view.shouldBeginSelection(at: input))

            view.scroll(toPosition: 0)
            #expect(view.shouldBeginSelection(at: Position(col: 0, row: terminal.buffer.y + terminal.buffer.yDisp)))
        }

        @Test("Input multi-taps open the menu, and explicit Select/Copy act on the terminal", arguments: [2, 3])
        func inputMenuActions(tapCount: Int) async throws {
            let (window, view) = makeView()
            defer { close(window, view) }
            let proxy = try inputProxy(in: window)
            proxy.insertText("shadow editor only")
            let shadowText = proxy.text
            let shadowSelection = proxy.selectedRange
            view.feed(text: "body\r\n> hello world")
            view.scroll(toPosition: 1)
            let row = view.getTerminal().buffer.y + view.getTerminal().buffer.yDisp
            var sentKeys = 0
            var sentBytes = 0
            view.onInput = { sentKeys += $0.count }
            view.onRawInput = { sentBytes += $0.count }

            tap(view, count: tapCount, column: 3, row: row)
            await Task.yield()

            let menu = UIMenuController.shared
            #expect(view.lastLongSelect == Position(col: 3, row: row))
            #expect(!view.selectionActive)
            #expect(view.panSelectionGesture == nil)
            #expect(proxy.isFirstResponder)
            #expect(proxy.target(forAction: #selector(view.copy(_:)), withSender: menu) == nil)
            #expect(proxy.target(forAction: #selector(view.select(_:)), withSender: menu) as? UIResponder === view)
            #expect(proxy.target(forAction: #selector(view.selectAll(_:)), withSender: menu) as? UIResponder === view)
            #expect(proxy.target(forAction: #selector(view.paste(_:)), withSender: menu) as? UIResponder === view)

            try sendMenuAction(#selector(view.select(_:)), from: proxy)
            await Task.yield()
            #expect(view.selection.getSelectedText() == "hello")
            #expect(view.panSelectionGesture?.isEnabled == true)
            #expect(proxy.target(forAction: #selector(view.copy(_:)), withSender: menu) as? UIResponder === view)
            #expect(proxy.target(forAction: #selector(view.select(_:)), withSender: menu) == nil)

            try sendMenuAction(#selector(view.copy(_:)), from: proxy)
            #expect(!view.selectionActive)
            #expect(view.panSelectionGesture?.isEnabled == false)
            #expect(proxy.text == shadowText)
            #expect(proxy.selectedRange == shadowSelection)
            #expect(sentKeys == 0)
            #expect(sentBytes == 0)
        }

        @Test("Body double-tap Copy ignores the native shadow editor")
        func bodyCopyAction() throws {
            let (window, view) = makeView()
            defer { close(window, view) }
            let proxy = try inputProxy(in: window)
            proxy.insertText("not the visible text")
            view.feed(text: "hello world\r\n> prompt")

            tap(view, count: 2, column: 1, row: 0)

            #expect(view.selection.getSelectedText() == "hello")
            #expect(proxy.target(forAction: #selector(view.copy(_:)), withSender: UIMenuController.shared) as? UIResponder === view)
            try sendMenuAction(#selector(view.copy(_:)), from: proxy)
            #expect(!view.selectionActive)
        }

        @Test("Select All from an input menu selects the terminal, not the shadow document")
        func selectAllAction() throws {
            let (window, view) = makeView()
            defer { close(window, view) }
            let proxy = try inputProxy(in: window)
            proxy.insertText("shadow editor only")
            let shadowSelection = proxy.selectedRange
            view.feed(text: "body text\r\n> input")
            tap(view, count: 2, column: 25, row: 1)

            try sendMenuAction(#selector(view.selectAll(_:)), from: proxy)

            #expect(view.selectionActive)
            #expect(view.selection.getSelectedText().contains("body text"))
            #expect(view.selection.getSelectedText().contains("> input"))
            #expect(view.panSelectionGesture?.isEnabled == true)
            #expect(proxy.selectedRange == shadowSelection)
            #expect(proxy.isFirstResponder)
        }

        @Test("Typing and IME commits still use the shadow editor after opening an input menu")
        func typingAndIMEAfterMenu() throws {
            let (window, view) = makeView()
            defer { close(window, view) }
            let proxy = try inputProxy(in: window)
            view.feed(text: "> input")
            tap(view, count: 2, column: 25, row: 0)
            var inserted: [String] = []
            var deleted = 0
            proxy.onInsertText = { inserted.append($0) }
            proxy.onDeleteBackward = { deleted += 1 }

            proxy.insertText("hello")
            proxy.textViewDidChange(proxy)
            #expect(inserted == ["hello"])

            proxy.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0))
            proxy.textViewDidChange(proxy)
            #expect(inserted == ["hello"])
            proxy.setMarkedText("中", selectedRange: NSRange(location: 1, length: 0))
            proxy.unmarkText()
            proxy.textViewDidChange(proxy)

            #expect(inserted == ["hello", "中"])
            #expect(deleted == 0)
            #expect(proxy.isFirstResponder)
            #expect(!view.selectionActive)
        }

        private func inputProxy(in window: UIWindow) throws -> TerminalInputProxyView {
            try #require(window.rootViewController?.view.subviews
                .compactMap { $0 as? UIScrollView }.first?.subviews
                .compactMap { $0 as? TerminalInputProxyView }.first)
        }

        private func sendMenuAction(_ action: Selector, from proxy: TerminalInputProxyView) throws {
            let menu = UIMenuController.shared
            let target = try #require(proxy.target(forAction: action, withSender: menu) as? UIResponder)
            // Unhosted package tests have no UIApplication event dispatcher.
            // Resolve the same responder target and invoke its selector. The
            // hosted XCTest below verifies UIKit dispatch and clipboard data.
            #expect(target.responds(to: action))
            target.perform(action, with: menu)
        }

        fileprivate func close(_ window: UIWindow, _ view: InteractiveTerminalView) {
            UIMenuController.shared.hideMenu()
            view.updateInput(isEnabled: false, keyboardRequested: false)
            view.updateUiClosed()
            window.isHidden = true
        }

        fileprivate func tap(_ view: InteractiveTerminalView, count: Int, column: Int, row: Int) {
            let gesture = CompletedTerminalMenuTap()
            gesture.numberOfTapsRequired = count
            gesture.point = CGPoint(
                x: (CGFloat(column) + 0.5) * view.cellDimension.width,
                y: (CGFloat(row) + 0.5) * view.cellDimension.height
            )
            view.addGestureRecognizer(gesture)
            if count == 2 {
                view.doubleTap(gesture)
            } else {
                view.tripleTap(gesture)
            }
        }

        fileprivate func makeView() -> (UIWindow, InteractiveTerminalView) {
            let frame = CGRect(x: 0, y: 0, width: 400, height: 700)
            let window: UIWindow
            let application = UIApplication.perform(#selector(getter: UIApplication.shared))?.takeUnretainedValue() as? UIApplication
            if let scene = application?.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                window = UIWindow(windowScene: scene)
                window.frame = frame
            } else {
                window = UIWindow(frame: frame)
            }
            let controller = UIViewController()
            window.rootViewController = controller
            let viewport = UIScrollView(frame: window.bounds)
            controller.view.addSubview(viewport)
            let terminal = InteractiveTerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), font: nil)
            viewport.addSubview(terminal)
            terminal.attachInputProxy(to: viewport)
            window.makeKeyAndVisible()
            terminal.updateInput(isEnabled: true, keyboardRequested: false)
            controller.view.layoutIfNeeded()
            return (window, terminal)
        }
    }

    /// Run with an application test host and CTRLX_MENU_UI_TESTS=1 to verify
    /// the real UIKit popover and nil-target responder dispatch. Ordinary
    /// package tests exercise the same handlers without an application host.
    @MainActor
    final class TerminalMenuHostTests: XCTestCase {
        func testInputMenuPresentationAndActions() async throws {
            try XCTSkipUnless(ProcessInfo.processInfo.environment["CTRLX_MENU_UI_TESTS"] == "1")
            let fixture = TerminalSelectionRoutingTests()
            for tapCount in [2, 3] {
                let (window, view) = fixture.makeView()
                defer { fixture.close(window, view) }
                view.feed(text: "body\r\n> hello world")
                let proxy = try XCTUnwrap(window.rootViewController?.view.subviews
                    .compactMap { $0 as? UIScrollView }.first?.subviews
                    .compactMap { $0 as? TerminalInputProxyView }.first)
                proxy.insertText("not the visible text")
                let shadowText = proxy.text
                let shadowSelection = proxy.selectedRange
                var sentKeys: [TmuxKey] = []
                view.onInput = { sentKeys += $0 }
                fixture.tap(view, count: tapCount, column: 3, row: 1)
                try await Task.sleep(for: .milliseconds(300))

                let menu = UIMenuController.shared
                XCTAssertEqual(window.windowScene?.activationState, .foregroundActive)
                XCTAssertTrue(menu.isMenuVisible)
                XCTAssertFalse(view.selectionActive)
                XCTAssertNil(view.panSelectionGesture)
                XCTAssertTrue(proxy.isFirstResponder)
                XCTAssertNil(proxy.target(forAction: #selector(view.copy(_:)), withSender: menu))
                XCTAssertTrue(UIApplication.shared.sendAction(#selector(view.select(_:)), to: nil, from: menu, for: nil))
                try await Task.sleep(for: .milliseconds(100))
                XCTAssertEqual(view.selection.getSelectedText(), "hello")
                XCTAssertTrue(UIApplication.shared.sendAction(#selector(view.copy(_:)), to: nil, from: menu, for: nil))
                try await Task.sleep(for: .milliseconds(50))
                XCTAssertEqual(UIPasteboard.general.string, "hello")
                XCTAssertFalse(view.selectionActive)
                XCTAssertEqual(proxy.text, shadowText)
                XCTAssertEqual(proxy.selectedRange, shadowSelection)
                XCTAssertTrue(sentKeys.isEmpty)

                UIPasteboard.general.string = "paste once"
                try await Task.sleep(for: .milliseconds(50))
                fixture.tap(view, count: tapCount, column: 25, row: 1)
                try await Task.sleep(for: .milliseconds(300))
                XCTAssertTrue(menu.isMenuVisible)
                XCTAssertTrue(UIApplication.shared.sendAction(#selector(view.paste(_:)), to: nil, from: menu, for: nil))
                XCTAssertEqual(sentKeys, [.text("paste"), .space, .text("once")])
                XCTAssertTrue(proxy.isFirstResponder)
            }
        }
    }

    @MainActor
    private final class CompletedTerminalMenuTap: UITapGestureRecognizer {
        var point = CGPoint.zero

        override var state: UIGestureRecognizer.State {
            get { .ended }
            set {}
        }

        override func location(in view: UIView?) -> CGPoint { point }
    }
#endif
