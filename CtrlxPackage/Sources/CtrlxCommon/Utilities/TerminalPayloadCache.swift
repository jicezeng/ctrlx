/// Tracks whether an input chunk can cause SwiftTerm to attach a new OSC 8
/// payload to a cell. Parser state survives pipe-read boundaries.
struct OSC8PayloadDetector {
    private enum State {
        case idle
        case escape
        case osc
        case command8
        case parameters
        case uri(hasContent: Bool)
        case uriEscape(hasContent: Bool)
    }

    private var state = State.idle
    private var hyperlinkActive = false

    mutating func mayContainNewPayload(in bytes: ArraySlice<UInt8>) -> Bool {
        var mayContainPayload = false

        for byte in bytes {
            // While an OSC 8 hyperlink is active, printable bytes can acquire
            // its payload. Counting the closing sequence is harmless and keeps
            // the detector conservative.
            if hyperlinkActive {
                mayContainPayload = true
            }

            switch state {
            case .idle:
                advanceFromIdle(byte)
            case .escape:
                if byte == 0x5D { // ]
                    state = .osc
                } else {
                    advanceFromIdle(byte)
                }
            case .osc:
                if byte == 0x38 { // 8
                    state = .command8
                } else {
                    advanceFromIdle(byte)
                }
            case .command8:
                if byte == 0x3B { // ;
                    state = .parameters
                } else {
                    advanceFromIdle(byte)
                }
            case .parameters:
                if byte == 0x3B { // ; before URI
                    state = .uri(hasContent: false)
                } else if byte == 0x07 || byte == 0x9C { // BEL or C1 ST
                    state = .idle
                }
            case let .uri(hasContent):
                if byte == 0x07 || byte == 0x9C { // BEL or C1 ST
                    finishURI(hasContent: hasContent)
                } else if byte == 0x1B {
                    state = .uriEscape(hasContent: hasContent)
                } else {
                    state = .uri(hasContent: true)
                }
            case let .uriEscape(hasContent):
                if byte == 0x5C { // ESC \
                    finishURI(hasContent: hasContent)
                } else {
                    // A non-terminating ESC is malformed inside an OSC string.
                    // Treat it as URI content and resume parsing conservatively.
                    state = .uri(hasContent: true)
                }
            }
        }

        return mayContainPayload
    }

    private mutating func advanceFromIdle(_ byte: UInt8) {
        switch byte {
        case 0x1B: // ESC
            state = .escape
        case 0x9D: // C1 OSC
            state = .osc
        default:
            state = .idle
        }
    }

    private mutating func finishURI(hasContent: Bool) {
        hyperlinkActive = hasContent
        state = .idle
    }
}

#if canImport(SwiftTerm)
    import SwiftTerm

    /// Owns the OSC 8 hyperlink payload cache for a single SwiftTerm terminal view.
    ///
    /// SwiftTerm sets each cell's `payload` (an OSC 8 hyperlink URL) when it
    /// processes the matching `OSC 8 ;` close sequence. SwiftTerm renders dashed
    /// underlines for those cells when the user hovers with a modifier — but
    /// Ctrlx draws its own highlights, so the per-cell payload is cleared
    /// after extraction to suppress double rendering, and the URL is mirrored
    /// here so URL detection still resolves clicks and hover.
    ///
    /// Each cached entry snapshots the cell's `getCharacter()` + `attribute` at
    /// cache time. On subsequent extraction passes, a cell whose current
    /// character or attribute no longer matches the snapshot is treated as
    /// overwritten and its cache entry is dropped — otherwise a click on a
    /// cell whose visible content has changed would still open the original
    /// link.
    ///
    /// The cache is keyed by **absolute** buffer row (`scroll-invariant`), so
    /// lookups remain correct as the terminal scrolls. Callers translate
    /// viewport rows to absolute rows by adding `terminal.buffer.yDisp` before
    /// calling `cellPayload(col:absoluteRow:)`.
    final public class TerminalPayloadCache {
        /// One entry per cached cell.
        public struct CachedPayload: Equatable {
            public let payload: String
            public let character: Character
            public let attribute: Attribute

            public init(payload: String, character: Character, attribute: Attribute) {
                self.payload = payload
                self.character = character
                self.attribute = attribute
            }
        }

        private var entries: [Int: [Int: CachedPayload]] = [:]
        private var payloadDetector = OSC8PayloadDetector()

        public init() { }

        /// Payload at the given absolute buffer row and column, or `nil` if
        /// the cell has no cached OSC 8 entry.
        public func cellPayload(col: Int, absoluteRow: Int) -> String? {
            entries[absoluteRow]?[col]?.payload
        }

        /// Updates the cache after SwiftTerm has consumed one input chunk.
        ///
        /// Most terminal traffic is ordinary text or cursor animation and
        /// cannot create a new cell payload. That path only validates cells
        /// which already have cached links. A full buffer scan is reserved for
        /// chunks that contain text while an OSC 8 hyperlink is active.
        public func update(from terminal: Terminal, afterFeeding bytes: ArraySlice<UInt8>) {
            if payloadDetector.mayContainNewPayload(in: bytes) {
                extractAndClear(from: terminal)
            } else {
                validateCachedEntries(in: terminal)
            }
        }

        /// Scans every visible buffer line, mirrors any live OSC 8 payloads
        /// into the cache (along with a character + attribute snapshot of the
        /// cell), and clears SwiftTerm's payload to suppress its own
        /// rendering. Cache entries whose snapshot no longer matches the
        /// current cell are dropped — that's how stale links from overwritten
        /// cells get invalidated.
        ///
        /// Call after every `feed(byteArray:)` on the terminal view so the
        /// cache reflects the latest buffer state.
        public func extractAndClear(from terminal: Terminal) {
            // TinyAtom.empty is internal, but TinyAtom is a single UInt16 struct —
            // empty has code 0 which makes CharData.hasPayload return false.
            assert(
                MemoryLayout<TinyAtom>.size == MemoryLayout<UInt16>.size,
                "TinyAtom layout changed — unsafeBitCast assumption is invalid"
            )
            let emptyAtom = unsafeBitCast(UInt16(0), to: TinyAtom.self)
            let cols = terminal.cols
            let totalLines = terminal.buffer.yDisp + terminal.rows

            for absoluteRow in 0..<totalLines {
                guard let line = terminal.getScrollInvariantLine(row: absoluteRow) else { continue }
                // Hoist the per-row dictionary out of the inner loop so each
                // cell costs at most one local-variable read instead of two
                // dictionary lookups, and so rows with no cached entries skip
                // the invalidation branch entirely (the common case once a
                // pane is mostly free of stale links). Reassigned in place
                // through the loop, then written back once at the end.
                var rowEntries = entries[absoluteRow]
                for col in 0..<cols {
                    var cd = line[col]
                    if cd.hasPayload {
                        if let payload = cd.getPayload() as? String, !payload.isEmpty {
                            if rowEntries == nil {
                                rowEntries = [:]
                            }
                            rowEntries?[col] = CachedPayload(
                                payload: payload,
                                character: cd.getCharacter(),
                                attribute: cd.attribute
                            )
                        }
                        cd.setPayload(atom: emptyAtom)
                        line[col] = cd
                    } else if
                        rowEntries != nil,
                        let cached = rowEntries?[col],
                        cached.character != cd.getCharacter() || cached.attribute != cd.attribute {
                        // Cell has no live payload and its character or
                        // attribute has changed since we cached — content was
                        // overwritten, so the cached link no longer describes
                        // what's on screen at this position.
                        //
                        // Note: the snapshot check is intentionally loose. A
                        // redraw that happens to leave the cell with the same
                        // `(character, attribute)` pair (e.g. an OSC 8 link
                        // on `file.txt` followed by a non-OSC-8 redraw of
                        // `file.bak` — the leading `file.` cells match) will
                        // not invalidate. Tightening this would require
                        // remembering more cell state (e.g. the payload
                        // itself in the live cell, or a write-generation
                        // counter), which costs memory on every cell. The
                        // failure mode is a stale click on an unusually
                        // similar redraw, which we accept.
                        rowEntries?[col] = nil
                    }
                }
                if let rowEntries, !rowEntries.isEmpty {
                    entries[absoluteRow] = rowEntries
                } else {
                    entries.removeValue(forKey: absoluteRow)
                }
            }

            // Prune entries for lines that have been trimmed from the
            // circular buffer entirely (scrollback overflow).
            let minRow = entries.keys.min() ?? 0
            if minRow < totalLines {
                for row in minRow..<totalLines where entries[row] != nil {
                    if terminal.getScrollInvariantLine(row: row) == nil {
                        entries.removeValue(forKey: row)
                    } else {
                        // Lines are contiguous — once we find a valid one, the rest are valid.
                        break
                    }
                }
            }
        }

        /// Invalidates stale links in time proportional to the number of cached
        /// link cells, rather than the size of the terminal scrollback.
        private func validateCachedEntries(in terminal: Terminal) {
            guard !entries.isEmpty else { return }

            let cols = terminal.cols
            for absoluteRow in Array(entries.keys) {
                guard let rowEntries = entries[absoluteRow] else { continue }
                guard let line = terminal.getScrollInvariantLine(row: absoluteRow) else {
                    entries.removeValue(forKey: absoluteRow)
                    continue
                }

                var retained: [Int: CachedPayload] = [:]
                retained.reserveCapacity(rowEntries.count)

                for (col, cached) in rowEntries where col >= 0 && col < cols {
                    let cell = line[col]

                    // Defensive fallback: a live payload without a detected
                    // opener means the upstream parser retained state in a way
                    // our byte detector did not observe. Preserve correctness.
                    if cell.hasPayload {
                        extractAndClear(from: terminal)
                        return
                    }

                    if
                        cached.character == cell.getCharacter(),
                        cached.attribute == cell.attribute {
                        retained[col] = cached
                    }
                }

                if retained.isEmpty {
                    entries.removeValue(forKey: absoluteRow)
                } else {
                    entries[absoluteRow] = retained
                }
            }
        }
    }
#endif
