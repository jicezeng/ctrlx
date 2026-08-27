/// Shared bounds for terminal history captured by the Host and retained by viewers.
public enum TerminalScrollbackPolicy {
    /// Default used by both macOS and iOS when no peer-specific value is available.
    public static let defaultLineLimit = 10_000

    /// Prevents an accidental settings value from allocating an unbounded terminal buffer.
    public static let maximumLineLimit = 50_000

    /// Returns a safe, deterministic line limit for capture and rendering.
    public static func normalizedLineLimit(_ requested: Int) -> Int {
        min(max(requested, 0), maximumLineLimit)
    }
}
