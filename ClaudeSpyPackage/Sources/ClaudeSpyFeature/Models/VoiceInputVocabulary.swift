enum VoiceInputVocabulary {
    private static let ctrlXTerms = [
        "CtrlX",
        "host",
        "pane",
        "relay",
        "session",
        "terminal",
        "viewer",
        "Voice",
    ]

    private static let agentTerms = [
        "ChatGPT",
        "Claude",
        "Claude Code",
        "Codex",
        "GPT",
        "GPT-5",
        "OpenAI",
    ]

    private static let appleTerms = [
        "Apple",
        "Apple Intelligence",
        "iOS",
        "iPad",
        "iPhone",
        "iPhone Air",
        "Mac",
        "MacBook",
        "macOS",
    ]

    private static let developmentTerms = [
        "Docker",
        "Git",
        "GitHub",
        "Homebrew",
        "Nginx",
        "SSH",
        "Swift",
        "SwiftTerm",
        "SwiftUI",
        "tmux",
        "Vapor",
        "WebSocket",
        "Xcode",
        "xcodebuild",
    ]

    private static let infrastructureTerms = [
        "HK",
        "home",
        "office",
        "QCloud",
    ]

    static let terms = ctrlXTerms
        + agentTerms
        + appleTerms
        + developmentTerms
        + infrastructureTerms
}
