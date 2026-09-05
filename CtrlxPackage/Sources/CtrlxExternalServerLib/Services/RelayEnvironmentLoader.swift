import Foundation

public enum RelayEnvironmentLoader {
    public static let filePriority = [
        ".env.local",
        ".env.production",
        ".env.development",
        ".env.test",
    ]

    public struct Result: Sendable {
        public let values: [String: String]
        public let source: URL?
    }

    /// Loads the first environment file in priority order. Values from that file
    /// override the inherited process environment; lower-priority files are not
    /// merged, so the effective deployment configuration remains auditable.
    public static func load(
        from directory: URL,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Result {
        let fileManager = FileManager.default
        for filename in filePriority {
            let url = directory.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let contents = try String(contentsOf: url, encoding: .utf8)
            let parsed = try parse(contents, source: url)
            return Result(values: processEnvironment.merging(parsed) { _, fileValue in fileValue }, source: url)
        }
        return Result(values: processEnvironment, source: nil)
    }

    static func parse(_ contents: String, source: URL) throws -> [String: String] {
        var values: [String: String] = [:]
        for (index, rawLine) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") {
                line.removeFirst("export ".count)
            }
            guard let separator = line.firstIndex(of: "=") else {
                throw RelayEnvironmentError.invalidLine(source: source, line: index + 1)
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard isValidKey(key) else {
                throw RelayEnvironmentError.invalidKey(String(key), source: source, line: index + 1)
            }
            if value.count >= 2,
               let first = value.first,
               let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value.removeFirst()
                value.removeLast()
            }
            values[String(key)] = String(value)
        }
        return values
    }

    private static func isValidKey(_ key: String) -> Bool {
        guard let first = key.first, first == "_" || first.isLetter else { return false }
        return key.dropFirst().allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
    }
}

public enum RelayEnvironmentError: Error, CustomStringConvertible {
    case invalidLine(source: URL, line: Int)
    case invalidKey(String, source: URL, line: Int)

    public var description: String {
        switch self {
        case let .invalidLine(source, line):
            "Invalid environment entry at \(source.path):\(line)"
        case let .invalidKey(key, source, line):
            "Invalid environment key '\(key)' at \(source.path):\(line)"
        }
    }
}
