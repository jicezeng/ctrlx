enum TerminalInputPresentation {
    struct State: Equatable {
        let inputEnabled: Bool
        let keyboardRequested: Bool
    }

    static func resolve(
        keyboardRequested: Bool,
        isActive: Bool,
        isCopyPresented: Bool
    ) -> State {
        guard isActive, !isCopyPresented else {
            return State(inputEnabled: false, keyboardRequested: false)
        }
        return State(inputEnabled: true, keyboardRequested: keyboardRequested)
    }
}
