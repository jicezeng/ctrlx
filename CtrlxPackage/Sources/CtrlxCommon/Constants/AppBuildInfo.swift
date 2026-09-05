import Foundation

/// Human-readable identity of the installed app build.
///
/// The timestamp and source revision are display metadata only. Protocol and
/// store compatibility continue to use `CFBundleShortVersionString`.
public struct AppBuildInfo: Equatable, Sendable {
    public static let buildStampKey = "CtrlXBuildStamp"
    public static let sourceRevisionKey = "CtrlXSourceRevision"

    public let version: String?
    public let buildNumber: String?
    public let buildStamp: String?
    public let sourceRevision: String?

    public init(infoDictionary: [String: Any]?) {
        self.version = Self.nonEmptyString(infoDictionary?["CFBundleShortVersionString"])
        self.buildNumber = Self.nonEmptyString(infoDictionary?["CFBundleVersion"])
        self.buildStamp = Self.nonEmptyString(infoDictionary?[Self.buildStampKey])
        self.sourceRevision = Self.nonEmptyString(infoDictionary?[Self.sourceRevisionKey])
    }

    public static var current: AppBuildInfo {
        AppBuildInfo(infoDictionary: Bundle.main.infoDictionary)
    }

    public var displayVersion: String {
        var components = [baseVersion]
        if let buildStamp {
            components.append(buildStamp)
        }
        if let sourceRevision {
            components.append(String(sourceRevision.prefix(12)))
        }
        return components.joined(separator: " · ")
    }

    public var correspondingSourceURL: URL {
        ProductIdentity.sourceURL(for: sourceRevision)
    }

    private var baseVersion: String {
        switch (version, buildNumber) {
        case let (.some(version), .some(buildNumber)):
            "\(version) (\(buildNumber))"
        case let (.some(version), .none):
            version
        case let (.none, .some(buildNumber)):
            "Build \(buildNumber)"
        case (.none, .none):
            "Unknown version"
        }
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
