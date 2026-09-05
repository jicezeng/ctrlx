import Testing
@testable import CtrlxFeature

@Suite("Terminal keyboard control position")
struct TerminalKeyboardControlPositionTests {
    @Test("Missing and invalid stored values preserve the top-right default")
    func defaultPosition() {
        #expect(TerminalKeyboardControlPosition(storedValue: nil) == .topRight)
        #expect(TerminalKeyboardControlPosition(storedValue: "invalid") == .topRight)
    }

    @Test("Known stored values round-trip")
    func storedValues() {
        for position in TerminalKeyboardControlPosition.allCases {
            #expect(TerminalKeyboardControlPosition(storedValue: position.rawValue) == position)
        }
    }
}
