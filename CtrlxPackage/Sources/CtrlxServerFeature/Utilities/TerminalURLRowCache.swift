#if os(macOS)
    import CtrlxCommon
    import SwiftTerm

    /// Caches URL detection for the visible terminal rows. Buffer lines mutate
    /// in place, so identity alone is insufficient; generation detects edits.
    struct TerminalURLRowCache {
        struct Entry {
            let line: BufferLine
            let generation: UInt64
            let absoluteRow: Int
            let cols: Int
            let urls: [TerminalURLDetector.DetectedURL]
        }

        private(set) var entries: [Int: Entry] = [:]

        var count: Int { entries.count }

        mutating func urls(
            forViewportRow row: Int,
            absoluteRow: Int,
            line: BufferLine,
            cols: Int,
            detect: () -> [TerminalURLDetector.DetectedURL]
        ) -> [TerminalURLDetector.DetectedURL] {
            if
                let entry = entries[row],
                entry.line === line,
                entry.generation == line.generation,
                entry.absoluteRow == absoluteRow,
                entry.cols == cols {
                return entry.urls
            }

            let urls = detect()
            entries[row] = Entry(
                line: line,
                generation: line.generation,
                absoluteRow: absoluteRow,
                cols: cols,
                urls: urls
            )
            return urls
        }

        mutating func retainViewportRows(in range: Range<Int>) {
            entries = entries.filter { range.contains($0.key) }
        }
    }
#endif
