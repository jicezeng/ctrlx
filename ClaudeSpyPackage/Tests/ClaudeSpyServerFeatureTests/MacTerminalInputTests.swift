#if os(macOS)
    import AppKit
    import ClaudeSpyNetworking
    import Testing
    @testable import ClaudeSpyServerFeature

    @MainActor
    struct MacTerminalInputTests {
        @Test("SwiftTerm receives terminal focus")
        func swiftTermReceivesTerminalFocus() {
            let (window, view) = makeTerminalWindow()

            #expect(view.focusTerminal())
            #expect(window.firstResponder === view.terminalView)
        }

        @Test("IME composition commits terminal text")
        func imeCompositionCommitsTerminalText() {
            let (_, view) = makeTerminalWindow()
            var input: [TmuxKey] = []
            view.onInput = { input.append(contentsOf: $0) }

            view.terminalView.setMarkedText(
                "zhong",
                selectedRange: NSRange(location: 5, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            #expect(view.terminalView.hasMarkedText())
            #expect(input.isEmpty)

            view.terminalView.insertText(
                "中",
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            #expect(!view.terminalView.hasMarkedText())
            #expect(input == [.text("中")])
        }

        @Test("Ctrl+T bypasses AppKit text commands")
        func controlTIsRoutedDirectly() throws {
            let (window, view) = makeTerminalWindow()
            var input: [TmuxKey] = []
            view.onInput = { input.append(contentsOf: $0) }
            #expect(view.focusTerminal())

            let event = try #require(makeKeyEvent(
                window: window,
                characters: "\u{14}",
                charactersIgnoringModifiers: "\u{14}",
                modifierFlags: .control,
                keyCode: 17
            ))

            #expect(view.interceptTerminalKeyDown(event))
            #expect(input == [.ctrl("t")])
        }

        @Test("Control shortcuts fall back to the ANSI key code for input methods")
        func controlShortcutUsesKeyCodeFallback() throws {
            let (window, view) = makeTerminalWindow()
            var input: [TmuxKey] = []
            view.onInput = { input.append(contentsOf: $0) }
            #expect(view.focusTerminal())

            let event = try #require(makeKeyEvent(
                window: window,
                characters: "",
                charactersIgnoringModifiers: "",
                modifierFlags: .control,
                keyCode: 17
            ))

            #expect(view.interceptTerminalKeyDown(event))
            #expect(input == [.ctrl("t")])
        }

        @Test("Control shortcuts require terminal focus")
        func controlShortcutRequiresTerminalFocus() throws {
            let (window, view) = makeTerminalWindow()
            let textField = NSTextField(frame: .zero)
            window.contentView?.addSubview(textField)
            #expect(window.makeFirstResponder(textField))

            var input: [TmuxKey] = []
            view.onInput = { input.append(contentsOf: $0) }
            let event = try #require(makeKeyEvent(
                window: window,
                characters: "\u{14}",
                charactersIgnoringModifiers: "t",
                modifierFlags: .control,
                keyCode: 17
            ))

            #expect(!view.interceptTerminalKeyDown(event))
            #expect(input.isEmpty)
        }

        @Test("Modified Control shortcuts remain available to SwiftTerm")
        func modifiedControlShortcutIsNotIntercepted() throws {
            let (window, view) = makeTerminalWindow()
            var input: [TmuxKey] = []
            view.onInput = { input.append(contentsOf: $0) }
            #expect(view.focusTerminal())

            let event = try #require(makeKeyEvent(
                window: window,
                characters: "\u{14}",
                charactersIgnoringModifiers: "t",
                modifierFlags: [.control, .shift],
                keyCode: 17
            ))

            #expect(!view.interceptTerminalKeyDown(event))
            #expect(input.isEmpty)
        }

        @Test("Shift+Enter keeps its direct terminal route")
        func shiftEnterRemainsDirect() throws {
            let (window, view) = makeTerminalWindow()
            var input: [TmuxKey] = []
            view.onInput = { input.append(contentsOf: $0) }
            #expect(view.focusTerminal())

            let event = try #require(makeKeyEvent(
                window: window,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                modifierFlags: .shift,
                keyCode: 36
            ))

            #expect(view.interceptTerminalKeyDown(event))
            #expect(input == [.shiftEnter])
        }

        private func makeTerminalWindow() -> (NSWindow, InteractiveTerminalView) {
            let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
            let window = NSWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            let view = InteractiveTerminalView(frame: frame)
            window.contentView = view
            return (window, view)
        }

        private func makeKeyEvent(
            window: NSWindow,
            characters: String,
            charactersIgnoringModifiers: String,
            modifierFlags: NSEvent.ModifierFlags,
            keyCode: UInt16
        ) -> NSEvent? {
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: charactersIgnoringModifiers,
                isARepeat: false,
                keyCode: keyCode
            )
        }
    }
#endif
