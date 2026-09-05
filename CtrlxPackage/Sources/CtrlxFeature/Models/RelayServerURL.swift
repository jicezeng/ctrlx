import Foundation

/// Validation and normalization for user-configured relay server URLs.
enum RelayServerURL {
    static func normalized(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            var components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(),
            scheme == "ws" || scheme == "wss",
            let host = components.host,
            !host.isEmpty,
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil
        else {
            return nil
        }

        components.scheme = scheme

        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        components.path = path

        return components.string
    }
}
