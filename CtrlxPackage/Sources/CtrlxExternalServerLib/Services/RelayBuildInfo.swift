import Foundation

struct RelayBuildInfo: Sendable, Equatable {
    static let productName = "CtrlX Relay"
    static let defaultVersion = "3.0.0"
    static let defaultProtocolVersion = "3.0"
    static let defaultRepository = "https://github.com/jicezeng/CtrlX"

    let version: String
    let commit: String
    let protocolVersion: String
    let repository: String

    static func fromEnvironment(_ env: [String: String]) -> Self {
        Self(
            version: nonEmpty(env["CTRLX_VERSION"]) ?? defaultVersion,
            commit: nonEmpty(env["CTRLX_SOURCE_REVISION"]) ?? "development",
            protocolVersion: nonEmpty(env["CTRLX_PROTOCOL_VERSION"]) ?? defaultProtocolVersion,
            repository: nonEmpty(env["CTRLX_SOURCE_REPOSITORY"]) ?? defaultRepository
        )
    }

    var hasExactSource: Bool {
        (commit.count == 40 || commit.count == 64) && commit.allSatisfy(\.isHexDigit)
    }

    var sourceURL: String {
        guard hasExactSource else { return repository }
        return "\(repository)/tree/\(commit)"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
