#if os(macOS)
    import SwiftTerm
    import Testing
    @testable import CtrlxServerFeature

    struct TerminalURLRowCacheTests {
        @Test func reusesUnchangedLine() {
            var cache = TerminalURLRowCache()
            let line = BufferLine(cols: 4)
            var detections = 0

            for _ in 0..<2 {
                _ = cache.urls(forViewportRow: 1, absoluteRow: 7, line: line, cols: 4) {
                    detections += 1
                    return []
                }
            }

            #expect(detections == 1)
        }

        @Test func detectsMutatedLineAgain() {
            var cache = TerminalURLRowCache()
            let line = BufferLine(cols: 4)
            var detections = 0

            _ = cache.urls(forViewportRow: 1, absoluteRow: 7, line: line, cols: 4) {
                detections += 1
                return []
            }
            line.copyFrom(line: BufferLine(cols: 4))
            _ = cache.urls(forViewportRow: 1, absoluteRow: 7, line: line, cols: 4) {
                detections += 1
                return []
            }

            #expect(detections == 2)
        }

        @Test func detectsReplacementLineAgain() {
            var cache = TerminalURLRowCache()
            var detections = 0

            for line in [BufferLine(cols: 4), BufferLine(cols: 4)] {
                _ = cache.urls(forViewportRow: 1, absoluteRow: 7, line: line, cols: 4) {
                    detections += 1
                    return []
                }
            }

            #expect(detections == 2)
        }

        @Test func detectsPositionOrColumnChangeAgain() {
            var cache = TerminalURLRowCache()
            let line = BufferLine(cols: 4)
            var detections = 0

            for request in [(7, 4), (8, 4), (8, 5)] {
                _ = cache.urls(
                    forViewportRow: 1,
                    absoluteRow: request.0,
                    line: line,
                    cols: request.1
                ) {
                    detections += 1
                    return []
                }
            }

            #expect(detections == 3)
        }

        @Test func retainsOnlyVisibleRows() {
            var cache = TerminalURLRowCache()
            for row in 0..<10 {
                _ = cache.urls(
                    forViewportRow: row,
                    absoluteRow: row,
                    line: BufferLine(cols: 4),
                    cols: 4
                ) { [] }
            }

            cache.retainViewportRows(in: 3..<7)

            #expect(cache.count == 4)
            #expect(cache.entries.keys.sorted() == [3, 4, 5, 6])
        }
    }
#endif
