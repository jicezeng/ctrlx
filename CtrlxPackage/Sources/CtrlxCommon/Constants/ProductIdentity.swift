import Foundation

/// User-visible identity and immutable provenance for the CtrlX distribution.
///
/// Runtime endpoints and signing material do not belong here. They are supplied
/// by build or environment configuration so a development build cannot silently
/// connect to production infrastructure.
public enum ProductIdentity {
    public static let name = "CtrlX"
    public static let sourceURL = URL(string: "https://github.com/jicezeng/CtrlX")!
    public static let upstreamURL = URL(string: "https://github.com/gpambrozio/Gallager")!
    public static let licenseURL = sourceURL.appending(path: "blob/main/LICENSE")
    public static let forkCommit = "919c7772928531d4d0bb266bdf275691d361901e"
    public static let forkDate = "2026-08-14"

    public static func sourceURL(for revision: String?) -> URL {
        guard
            let revision,
            revision.count == 40 || revision.count == 64,
            revision.allSatisfy(\.isHexDigit)
        else {
            return sourceURL
        }
        return sourceURL.appending(path: "tree/\(revision)")
    }
}
