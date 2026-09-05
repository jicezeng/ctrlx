public enum TerminalKeyboardControlPosition: String, CaseIterable, Sendable {
    case topRight
    case bottomBar

    init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .topRight
    }

    var displayName: String {
        switch self {
        case .topRight:
            "Top Right"
        case .bottomBar:
            "Bottom Bar"
        }
    }
}
