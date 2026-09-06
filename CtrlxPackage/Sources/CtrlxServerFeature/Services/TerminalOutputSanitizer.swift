#if os(macOS)
    import CtrlxCommon
    import Foundation

    /// Incrementally strips tmux's legacy title wrapper from terminal bytes.
    struct TmuxTitleSequenceFilter: Sendable {
        private var buffer = Data()

        var hasBufferedSequence: Bool {
            !buffer.isEmpty
        }

        mutating func reset() {
            buffer = Data()
        }

        mutating func filter(_ data: Data) -> Data {
            var result = Data()
            var dataToProcess = data
            if !buffer.isEmpty {
                dataToProcess = buffer + data
                buffer = Data()
            }

            var index = dataToProcess.startIndex
            while index < dataToProcess.endIndex {
                guard dataToProcess[index] == 0x1B else {
                    result.append(dataToProcess[index])
                    index = dataToProcess.index(after: index)
                    continue
                }

                guard index + 1 < dataToProcess.endIndex else {
                    buffer = Data(dataToProcess[index...])
                    break
                }

                guard dataToProcess[index + 1] == 0x6B else { // "k"
                    result.append(dataToProcess[index])
                    index = dataToProcess.index(after: index)
                    continue
                }

                var end = dataToProcess.index(index, offsetBy: 2)
                var foundTerminator = false
                while end < dataToProcess.endIndex {
                    if dataToProcess[end] == 0x1B {
                        guard end + 1 < dataToProcess.endIndex else {
                            buffer = Data(dataToProcess[index...])
                            return result
                        }
                        if dataToProcess[end + 1] == 0x5C { // "\\"
                            end = dataToProcess.index(end, offsetBy: 2)
                            foundTerminator = true
                            break
                        }
                    }
                    end = dataToProcess.index(after: end)
                }

                guard foundTerminator else {
                    buffer = Data(dataToProcess[index...])
                    break
                }
                index = end
            }

            return result
        }
    }

    /// Applies the same terminal-feed filtering to decoded control-mode output
    /// that the notification-only pipe reader applies to raw PTY bytes.
    struct TerminalOutputSanitizer: Sendable {
        private var titleFilter = TmuxTitleSequenceFilter()
        private var notificationParser = TerminalNotificationParser()

        mutating func sanitize(_ data: Data) -> Data {
            guard !data.isEmpty else { return Data() }
            if canUsePlainDataPath(data) { return data }

            let tmuxFiltered = titleFilter.filter(data)
            guard !tmuxFiltered.isEmpty else { return Data() }
            let daFiltered = TerminalResponseFilter.stripDAQueries(tmuxFiltered)
            guard !daFiltered.isEmpty else { return Data() }
            let dsrFiltered = TerminalResponseFilter.stripDSRQueries(daFiltered)
            guard !dsrFiltered.isEmpty else { return Data() }
            let decrqmFiltered = TerminalResponseFilter.stripDECRQMQueries(dsrFiltered)
            guard !decrqmFiltered.isEmpty else { return Data() }
            let kittyFiltered = TerminalResponseFilter.stripKittyKeyboardProtocol(decrqmFiltered)
            guard !kittyFiltered.isEmpty else { return Data() }
            let oscFiltered = TerminalResponseFilter.stripOSCColorQueries(kittyFiltered)
            guard !oscFiltered.isEmpty else { return Data() }
            return notificationParser.parse(oscFiltered).filteredData
        }

        private func canUsePlainDataPath(_ data: Data) -> Bool {
            !titleFilter.hasBufferedSequence
                && !notificationParser.hasBufferedSequence
                && !data.contains(0x1B)
                && !data.contains(0x9B)
                && !data.contains(0x9D)
        }
    }
#endif
