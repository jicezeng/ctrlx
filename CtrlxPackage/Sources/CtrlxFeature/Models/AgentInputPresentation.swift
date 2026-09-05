enum AgentInputPresentation {
    static func showsResponseForm(
        isBlocking: Bool,
        quickInputEnabled: Bool,
        keyboardActive: Bool
    ) -> Bool {
        isBlocking || (quickInputEnabled && !keyboardActive)
    }
}
