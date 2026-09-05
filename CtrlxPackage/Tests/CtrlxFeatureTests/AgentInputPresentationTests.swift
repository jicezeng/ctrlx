import Testing
@testable import CtrlxFeature

@Suite("Agent input presentation")
struct AgentInputPresentationTests {
    @Test("Quick input follows its setting and keyboard mode")
    func quickInputVisibility() {
        #expect(!AgentInputPresentation.showsResponseForm(
            isBlocking: false,
            quickInputEnabled: false,
            keyboardActive: false
        ))
        #expect(AgentInputPresentation.showsResponseForm(
            isBlocking: false,
            quickInputEnabled: true,
            keyboardActive: false
        ))
        #expect(!AgentInputPresentation.showsResponseForm(
            isBlocking: false,
            quickInputEnabled: true,
            keyboardActive: true
        ))
    }

    @Test("Blocking forms remain visible in every input mode")
    func blockingFormVisibility() {
        #expect(AgentInputPresentation.showsResponseForm(
            isBlocking: true,
            quickInputEnabled: false,
            keyboardActive: true
        ))
        #expect(AgentInputPresentation.showsResponseForm(
            isBlocking: true,
            quickInputEnabled: true,
            keyboardActive: false
        ))
    }
}
