import Testing
@testable import ClaudeSpyFeature

@Suite("Terminal input presentation")
struct TerminalInputPresentationTests {
    @Test("An active terminal keeps shortcuts available without the keyboard")
    func activeTerminalWithoutKeyboard() {
        #expect(TerminalInputPresentation.resolve(
            keyboardRequested: false,
            isActive: true,
            isCopyPresented: false
        ) == TerminalInputPresentation.State(
            inputEnabled: true,
            keyboardRequested: false
        ))
    }

    @Test("Requesting the keyboard keeps both keyboard and shortcuts available")
    func activeTerminalWithKeyboard() {
        #expect(TerminalInputPresentation.resolve(
            keyboardRequested: true,
            isActive: true,
            isCopyPresented: false
        ) == TerminalInputPresentation.State(
            inputEnabled: true,
            keyboardRequested: true
        ))
    }

    @Test("The copy sheet suppresses all terminal input")
    func copySheetSuppressesInput() {
        #expect(TerminalInputPresentation.resolve(
            keyboardRequested: false,
            isActive: true,
            isCopyPresented: true
        ) == TerminalInputPresentation.State(
            inputEnabled: false,
            keyboardRequested: false
        ))
    }

    @Test("Inactive terminals never accept input")
    func inactiveTerminal() {
        #expect(TerminalInputPresentation.resolve(
            keyboardRequested: true,
            isActive: false,
            isCopyPresented: false
        ) == TerminalInputPresentation.State(
            inputEnabled: false,
            keyboardRequested: false
        ))
    }
}
