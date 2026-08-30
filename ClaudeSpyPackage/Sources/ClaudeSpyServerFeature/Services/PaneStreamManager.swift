#if os(macOS)
    import ClaudeSpyCommon
    import ClaudeSpyNetworking
    import Foundation
    import Logging

    /// Coalesces concurrent attempts to start the same pane reader.
    ///
    /// Pane discovery and a newly-created terminal view can observe an unknown
    /// pane at the same time. Starting two readers would make both instances
    /// replace the same tmux `pipe-pane` and FIFO, leaving one retained reader
    /// permanently disconnected. MainActor isolation makes a task table enough;
    /// no lock or second actor is needed.
    @MainActor
    final class PaneReaderStartGate {
        private struct Flight {
            let token: UUID
            let task: Task<Bool, Never>
        }

        private var flights: [String: Flight] = [:]

        func run(
            paneId: String,
            operation: @escaping @MainActor () async -> Bool
        ) async -> Bool {
            if let flight = flights[paneId] {
                return await flight.task.value
            }

            let token = UUID()
            let task = Task { await operation() }
            flights[paneId] = Flight(token: token, task: task)

            let result = await task.value
            if flights[paneId]?.token == token {
                flights.removeValue(forKey: paneId)
            }
            return result
        }

        func cancelAll() async {
            let active = Array(flights.values)
            flights.removeAll()
            for flight in active {
                flight.task.cancel()
            }
            for flight in active {
                _ = await flight.task.value
            }
        }
    }

    /// Manages a single persistent `PipePaneReader` per tmux pane and routes its
    /// events to subscribers.
    ///
    /// One reader is created when a pane is discovered and torn down only when
    /// the pane disappears. Mirroring a pane never restarts the reader; it
    /// merely toggles the reader's data-delivery mode (`scanOnly` → `buffering`
    /// → `live`) and adds the caller to the subscriber set. This keeps OSC
    /// event handlers wired in exactly one place and removes the FIFO
    /// detach/reattach window that used to lose bytes on every mirror toggle.
    ///
    /// Usage:
    /// 1. Call `subscribe(paneId:target:...)` to get a subscription ID.
    /// 2. Data and dimension changes flow to your callbacks.
    /// 3. Call `unsubscribe(_:)` when done.
    /// 4. Reader returns to scan-only mode when the last subscriber leaves.
    @Observable
    @MainActor
    final public class PaneStreamManager: PipePaneReaderDelegate {
        // MARK: - Types

        /// A subscription to a pane stream
        private struct Subscription {
            let id: UUID
            let paneId: String
            let maximumSnapshotScrollbackLineLimit: Int?
            let onData: @MainActor (Data) -> Void
            let onDimensionChange: (@MainActor (Int, Int) -> Void)?
            let onTitleChange: (@MainActor (String) -> Void)?
            let onNotification: (@MainActor (TerminalStreamMessage.TerminalNotification) -> Void)?
            let onClipboard: (@MainActor (String) -> Void)?
            let onResync: (@MainActor (Result<SubscriptionResult, Error>) -> Void)?
        }

        /// Per-pane state owned by the manager.
        ///
        /// One context exists for every known pane regardless of subscriber
        /// count — `subscriberIds` is empty while the reader is in scan-only
        /// mode and non-empty while it's in live mode. Dimensions live here
        /// so they can be queried for a pane that doesn't (yet) have a
        /// subscriber.
        private struct ReaderContext {
            let reader: PipePaneReader
            var target: String
            var sessionName: String
            var width: Int
            var height: Int
            var subscriberIds: Set<UUID>
            /// Last terminal title detected via OSC 0/2 or seeded from tmux's
            /// `pane_title`. Cleared only when the reader is torn down.
            var terminalTitle: String?
            /// Whether `controlClientManager.registerPaneDimensions` has been
            /// called for this pane. Registered on first subscriber so the
            /// dimension-change callback is wired before any subscriber needs
            /// it; unregistered when the reader is torn down.
            var hasRegisteredDimensions: Bool
        }

        // MARK: - Properties

        private let logger = Logger(label: "com.jicezeng.ctrlx.panestreammanager")
        private let tmuxService: TmuxService
        private let controlClientManager: TmuxControlClientManager
        private let scrollbackLineLimitProvider: @MainActor () -> Int

        private var configuredScrollbackLineLimit: Int {
            TerminalScrollbackPolicy.normalizedLineLimit(scrollbackLineLimitProvider())
        }

        private func resolvedSnapshotScrollbackLineLimit(maximum: Int?) -> Int {
            TerminalScrollbackPolicy.snapshotLineLimit(
                configuredLineLimit: configuredScrollbackLineLimit,
                maximumSnapshotLineLimit: maximum
            )
        }

        /// Active per-pane state keyed by paneId. One entry per known pane.
        private var readers: [String: ReaderContext] = [:]

        /// All subscriptions keyed by subscription ID
        private var subscriptions: [UUID: Subscription] = [:]

        /// Task for periodic pane discovery (needed to detect new tmux sessions)
        private var paneRefreshTask: Task<Void, Never>?

        /// Per-pane single-flight for reader startup. Without this, an on-demand
        /// subscribe can race pane discovery and both replace the same FIFO.
        private let readerStartGate = PaneReaderStartGate()

        /// Overload recovery is coalesced per pane. While a snapshot is being
        /// captured, incremental callbacks are suppressed and the reader buffers
        /// the post-snapshot boundary for an ordered flush.
        private var pendingResyncSubscribers: [String: Set<UUID>] = [:]
        private var resyncTasks: [String: Task<Void, Never>] = [:]
        private var resyncingPaneIds: Set<String> = []

        /// `disconnectAll` is terminal for this manager. Keep late callbacks
        /// from restarting readers while shutdown drains in-flight work.
        private var isShuttingDown = false

        /// Global notification handler — called for any notification on any pane,
        /// regardless of which subscribers are active. Used by macOS to show desktop notifications.
        public var onNotification: (@MainActor (String, TerminalStreamMessage.TerminalNotification) -> Void)?

        /// Global title change handler — called whenever a title is detected on
        /// any pane. Parameters: (paneId, target, title).
        public var onTitleChange: (@MainActor (String, String, String) -> Void)?

        /// Global progress handler — called for any `OSC 9;4` progress update on any pane.
        /// `.removed` means progress is cleared. Used to drive the sidebar progress bar.
        public var onProgress: (@MainActor (String, TerminalProgressState) -> Void)?

        // MARK: - Public State

        /// Pane IDs that currently have at least one active subscriber (mirror or relay viewer).
        public var activeStreamPaneIds: [String] {
            readers.compactMap { $0.value.subscriberIds.isEmpty ? nil : $0.key }
        }

        /// Whether a pane has at least one active subscriber.
        public func hasActiveStream(paneId: String) -> Bool {
            guard let context = readers[paneId] else { return false }
            return !context.subscriberIds.isEmpty
        }

        /// Get current dimensions for a pane.
        public func dimensions(for paneId: String) -> (width: Int, height: Int)? {
            guard let context = readers[paneId] else { return nil }
            return (context.width, context.height)
        }

        /// Get current terminal title for a pane (if a title has been seen).
        public func terminalTitle(for paneId: String) -> String? {
            readers[paneId]?.terminalTitle
        }

        /// Sends local interactive input through the pane's existing control client.
        /// Returns `false` when the reader or connection is not ready so the caller
        /// can safely use the process-based tmux fallback.
        func sendKeystrokesIfConnected(
            paneId: String,
            keys: [TmuxKey],
            onFirstCommandWritten: (@Sendable () -> Void)? = nil
        ) async throws -> Bool {
            guard let context = readers[paneId] else { return false }
            return try await controlClientManager.sendKeystrokesIfConnected(
                paneId: paneId,
                sessionName: context.sessionName,
                keys: keys,
                onFirstCommandWritten: onFirstCommandWritten
            )
        }

        /// Known default pane titles to filter out when seeding from tmux state.
        /// Tmux initializes `pane_title` to the system hostname, which may appear
        /// in various forms depending on the system configuration.
        private let defaultPaneTitles: Set<String> = {
            var defaults = Set<String>()
            // Use only `gethostname()` here — a pure syscall. Do NOT call
            // `ProcessInfo.processInfo.hostName`: it resolves the machine's `.local`
            // name, which is a local-network DNS operation (Apple TN3179). On a
            // macOS 15+ machine that hasn't decided Local Network access, that
            // resolution BLOCKS the calling thread until the decision is made — and
            // this property is evaluated synchronously on the main thread during
            // `AppCoordinator.init`, so it would hang app startup (the main-queue
            // NWListener for the E2E test server never binds). `gethostname()` is
            // what tmux uses for the default `pane_title` anyway.
            var buffer = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN))
            if
                gethostname(&buffer, buffer.count) == 0,
                let hostname = String(validating: buffer.prefix(while: { $0 != 0 }), as: UTF8.self) {
                defaults.insert(hostname)
                if let dotIndex = hostname.firstIndex(of: ".") {
                    defaults.insert(String(hostname[..<dotIndex]))
                }
            }
            return defaults
        }()

        // MARK: - Initialization

        public init(
            tmuxService: TmuxService,
            controlClientManager: TmuxControlClientManager,
            scrollbackLineLimitProvider: @escaping @MainActor () -> Int = {
                TerminalScrollbackPolicy.defaultLineLimit
            }
        ) {
            self.tmuxService = tmuxService
            self.controlClientManager = controlClientManager
            self.scrollbackLineLimitProvider = scrollbackLineLimitProvider

            // Wire up dimension changes from control client
            controlClientManager.setOnDimensionChange { [weak self] paneId, width, height in
                self?.updateDimensions(paneId: paneId, width: width, height: height)
            }
        }

        /// Whether a pane title from tmux is a custom title (not a default hostname variant).
        private func isCustomPaneTitle(_ title: String) -> Bool {
            !title.isEmpty && !defaultPaneTitles.contains(title)
        }

        // MARK: - Public API

        /// Result of subscribing to a pane stream
        public struct SubscriptionResult {
            /// Subscription ID to use when unsubscribing
            public let subscriptionId: UUID
            /// Initial terminal content (scrollback + visible area)
            public let initialContent: Data
            /// Terminal width in columns
            public let width: Int
            /// Terminal height in rows
            public let height: Int
            /// Maximum history lines the subscriber should retain while streaming.
            /// The initial snapshot may contain fewer historical lines.
            public let scrollbackLineLimit: Int

            public init(
                subscriptionId: UUID,
                initialContent: Data,
                width: Int,
                height: Int,
                scrollbackLineLimit: Int = TerminalScrollbackPolicy.defaultLineLimit
            ) {
                self.subscriptionId = subscriptionId
                self.initialContent = initialContent
                self.width = width
                self.height = height
                self.scrollbackLineLimit = TerminalScrollbackPolicy.normalizedLineLimit(scrollbackLineLimit)
            }
        }

        /// Subscribe to a pane stream.
        ///
        /// On the first subscriber for a pane, the reader is switched into
        /// buffering mode, a `capture-pane` snapshot is taken, then the reader
        /// is flushed into live mode — so live bytes that arrive during the
        /// snapshot aren't dropped. On subsequent subscribers, the existing
        /// live reader is reused and only a fresh snapshot is captured.
        ///
        /// - Parameters:
        ///   - paneId: The pane ID (e.g., "%1")
        ///   - target: The pane target (e.g., "mysession:0.1")
        ///   - onData: Callback for incoming terminal data (live updates only, not initial content)
        ///   - onDimensionChange: Optional callback for dimension changes
        ///   - onTitleChange: Optional callback for terminal title changes
        ///   - onNotification: Optional callback for terminal notifications (OSC 9/777)
        /// - Returns: Subscription result containing ID, initial content, and dimensions
        /// - Throws: If the stream fails to connect
        public func subscribe(
            paneId: String,
            target: String,
            maximumSnapshotScrollbackLineLimit: Int? = nil,
            onData: @escaping @MainActor (Data) -> Void,
            onDimensionChange: (@MainActor (Int, Int) -> Void)? = nil,
            onTitleChange: (@MainActor (String) -> Void)? = nil,
            onNotification: (@MainActor (TerminalStreamMessage.TerminalNotification) -> Void)? = nil,
            onClipboard: (@MainActor (String) -> Void)? = nil,
            onResync: (@MainActor (Result<SubscriptionResult, Error>) -> Void)? = nil
        ) async throws -> SubscriptionResult {
            let subscriptionId = UUID()
            let viewerScrollbackLineLimit = configuredScrollbackLineLimit
            let snapshotScrollbackLineLimit = resolvedSnapshotScrollbackLineLimit(
                maximum: maximumSnapshotScrollbackLineLimit
            )
            let subscription = Subscription(
                id: subscriptionId,
                paneId: paneId,
                maximumSnapshotScrollbackLineLimit: maximumSnapshotScrollbackLineLimit,
                onData: onData,
                onDimensionChange: onDimensionChange,
                onTitleChange: onTitleChange,
                onNotification: onNotification,
                onClipboard: onClipboard,
                onResync: onResync
            )

            let sessionName = TmuxControlClientManager.extractSessionName(from: target)

            // Pane discovery normally creates the reader before any subscribe is
            // possible, but a subscribe can race in (e.g. a pane created seconds
            // before the next refresh). Start a reader on demand so the first
            // viewer doesn't have to wait for the periodic refresh tick.
            if readers[paneId] == nil {
                let dims = (try? await tmuxService.getPaneDimensions(target)) ?? (width: 80, height: 24)
                await ensureReader(
                    paneId: paneId,
                    sessionName: sessionName,
                    target: target,
                    initialWidth: dims.width,
                    initialHeight: dims.height,
                    seedTitle: nil
                )
            }

            guard var context = readers[paneId] else {
                throw TmuxError.invalidPane(target: target)
            }

            let isFirstSubscriber = context.subscriberIds.isEmpty
            let initialContent: Data
            let width: Int
            let height: Int

            if isFirstSubscriber {
                // Claim the slot synchronously before any await. Two concurrent
                // subscribes for the same fresh pane could otherwise both observe
                // `subscriberIds.isEmpty` here (the await chain below yields the
                // main actor) and both take the first-subscriber path — the
                // second's `setBuffering(true)` would clear the first's buffer.
                //
                // Safe to insert before `flushBuffer`: the reader transitions
                // scanOnly → buffering during this path, so no data bytes flow
                // to subscribers until the explicit `flushBuffer()` at the end.
                // OSC events (title/notification/clipboard/progress) bypass
                // `subscriberIds` for `forwardNotification`/global handlers, so
                // they're unaffected by an early insert.
                context.subscriberIds.insert(subscriptionId)
                readers[paneId] = context
                subscriptions[subscriptionId] = subscription

                // 1. Retain live bytes during the snapshot so we don't drop any
                //    between "buffering on" and "snapshot taken". Some bytes may
                //    also be represented by the captured screen state; terminal
                //    output is not generally idempotent, so remote viewers stage
                //    this bootstrap offscreen instead of presenting intermediate
                //    redraws. Exact scrollback de-duplication remains issue #476.
                await context.reader.setBuffering(true)

                // 2. Refresh dimensions from tmux. capture-pane uses these to
                //    size the visible region; if we trust a stale value the
                //    snapshot can clip or pad incorrectly.
                if let dims = try? await tmuxService.getPaneDimensions(target) {
                    context.width = dims.width
                    context.height = dims.height
                }

                // 3. Register dimension tracking once per reader so future
                //    layout-change events flow into `updateDimensions`.
                if !context.hasRegisteredDimensions {
                    do {
                        try await controlClientManager.registerPaneDimensions(
                            paneId: paneId,
                            sessionName: sessionName,
                            dimensions: (width: context.width, height: context.height)
                        )
                        context.hasRegisteredDimensions = true
                    } catch {
                        logger.warning("Failed to register pane dimensions", metadata: [
                            "paneId": "\(paneId)",
                            "error": "\(error)",
                        ])
                    }
                }

                // 4. Take the snapshot. capture-pane is the only source of
                //    historical content; pipe-pane only delivers future bytes.
                do {
                    initialContent = try await tmuxService.capturePaneViaControlMode(
                        paneId: paneId,
                        width: context.width,
                        height: context.height,
                        controlClientManager: controlClientManager,
                        sessionName: sessionName,
                        scrollbackLineLimit: snapshotScrollbackLineLimit
                    )
                } catch {
                    // Roll back our claim. The reader stays alive in scan-only
                    // mode so retries don't pay the start cost.
                    await context.reader.setBuffering(false)
                    if var rolled = readers[paneId] {
                        rolled.subscriberIds.remove(subscriptionId)
                        readers[paneId] = rolled
                    }
                    subscriptions.removeValue(forKey: subscriptionId)
                    throw error
                }

                readers[paneId] = context
                width = context.width
                height = context.height

                // 5. Drain the queue into live delivery. Flushed bytes flow
                //    through the delegate (this manager) → forwardData →
                //    subscriber's onData callback.
                await context.reader.flushBuffer()

                // Send the seeded title (if any) to the first subscriber.
                if let title = context.terminalTitle, let cb = onTitleChange {
                    cb(title)
                }

                logger.info("First subscriber on pane reader", metadata: [
                    "paneId": "\(paneId)",
                    "target": "\(target)",
                    "subscriptionId": "\(subscriptionId)",
                ])
            } else {
                // Existing live reader — capture a fresh snapshot for this new
                // viewer FIRST, then insert into `subscriberIds`. Inserting
                // before the snapshot would let `forwardData` deliver live
                // bytes to this subscriber's `onData` before the caller has
                // received `initialContent` and seeded its terminal, which
                // produces out-of-order rendering.
                do {
                    initialContent = try await tmuxService.capturePaneWithScrollbackForStreaming(
                        target,
                        scrollbackLineLimit: snapshotScrollbackLineLimit
                    )
                } catch {
                    logger.warning("Failed to capture initial content for new subscriber", metadata: [
                        "paneId": "\(paneId)",
                        "error": "\(error)",
                    ])
                    initialContent = Data()
                }

                // Re-fetch the context — a concurrent unsubscribe or pane
                // teardown could have mutated it during the await above.
                guard var refreshed = readers[paneId] else {
                    throw TmuxError.invalidPane(target: target)
                }

                width = refreshed.width
                height = refreshed.height

                refreshed.subscriberIds.insert(subscriptionId)
                readers[paneId] = refreshed
                subscriptions[subscriptionId] = subscription

                if let title = refreshed.terminalTitle, let cb = onTitleChange {
                    cb(title)
                }

                logger.info("Added subscriber to existing pane reader", metadata: [
                    "paneId": "\(paneId)",
                    "subscriptionId": "\(subscriptionId)",
                    "totalSubscribers": "\(refreshed.subscriberIds.count)",
                ])
            }

            return SubscriptionResult(
                subscriptionId: subscriptionId,
                initialContent: initialContent,
                width: width,
                height: height,
                scrollbackLineLimit: viewerScrollbackLineLimit
            )
        }

        /// Unsubscribe from a pane stream.
        ///
        /// If this is the last subscriber, the reader returns to scan-only
        /// mode (data discarded, OSC events still parsed) but stays attached
        /// to the FIFO. The reader is only torn down when the pane disappears.
        ///
        /// - Parameter subscriptionId: The subscription ID returned from subscribe()
        public func unsubscribe(_ subscriptionId: UUID) async {
            guard let subscription = subscriptions.removeValue(forKey: subscriptionId) else {
                logger.debug("Subscription not found: \(subscriptionId)")
                return
            }

            let paneId = subscription.paneId
            pendingResyncSubscribers[paneId]?.remove(subscriptionId)

            guard var context = readers[paneId] else {
                logger.warning("Reader not found for pane: \(paneId)")
                return
            }

            context.subscriberIds.remove(subscriptionId)
            readers[paneId] = context

            if context.subscriberIds.isEmpty {
                await context.reader.setBuffering(false)
                logger.info("Last subscriber gone, reader returned to scan-only mode", metadata: [
                    "paneId": "\(paneId)",
                ])
            } else {
                logger.info("Removed subscriber from reader", metadata: [
                    "paneId": "\(paneId)",
                    "subscriptionId": "\(subscriptionId)",
                    "remainingSubscribers": "\(context.subscriberIds.count)",
                ])
            }
        }

        /// Update dimensions for a pane (called when tmux refreshes pane info).
        ///
        /// Stored on the reader context and forwarded to all subscribers.
        public func updateDimensions(paneId: String, width: Int, height: Int) {
            guard var context = readers[paneId] else { return }
            guard width != context.width || height != context.height else { return }
            context.width = width
            context.height = height
            readers[paneId] = context
            forwardDimensionChange(paneId: paneId, width: width, height: height)
        }

        /// Report a terminal title change detected by a subscriber's SwiftTerm instance.
        ///
        /// SwiftTerm parses OSC 0/2 sequences from the data stream and calls its delegate.
        /// The subscriber (e.g., TerminalContainerView) reports the title back here so it can
        /// be forwarded to other subscribers (e.g., TerminalStreamService for iOS relay).
        ///
        /// - Parameters:
        ///   - paneId: The pane ID whose title changed
        ///   - title: The new terminal title
        ///   - fromSubscription: The subscription ID reporting the change (excluded from forwarding)
        public func reportTitleChange(paneId: String, title: String, fromSubscription: UUID) {
            guard var context = readers[paneId] else { return }
            guard !title.isEmpty, context.terminalTitle != title else { return }
            context.terminalTitle = title
            readers[paneId] = context

            // Notify global handler so MirrorWindowManager stays in sync
            // even when the pane is streamed without a local mirror window
            onTitleChange?(paneId, context.target, title)

            forwardTitleChange(paneId: paneId, title: title, excludingSubscription: fromSubscription)
        }

        /// Capture current content for a pane that is already streaming.
        ///
        /// This is used when a second viewer wants to view an already-streaming pane.
        /// Instead of creating a duplicate PaneStreamManager subscription (which would cause
        /// duplicate data forwarding), this captures the current terminal state.
        ///
        /// - Parameter paneId: The pane ID to capture content for
        /// - Returns: Current content, width, and height if the pane has subscribers; nil otherwise
        public func currentContent(
            for paneId: String,
            maximumSnapshotScrollbackLineLimit: Int? = nil
        ) async -> (content: Data, width: Int, height: Int, scrollbackLineLimit: Int)? {
            guard let context = readers[paneId], !context.subscriberIds.isEmpty else { return nil }
            let viewerScrollbackLineLimit = configuredScrollbackLineLimit
            let snapshotScrollbackLineLimit = resolvedSnapshotScrollbackLineLimit(
                maximum: maximumSnapshotScrollbackLineLimit
            )
            guard
                let content = try? await tmuxService.capturePaneWithScrollbackForStreaming(
                    context.target,
                    scrollbackLineLimit: snapshotScrollbackLineLimit
                )
            else {
                return nil
            }
            return (content, context.width, context.height, viewerScrollbackLineLimit)
        }

        /// Requests an authoritative snapshot for one subscription after its
        /// downstream queue crossed the high-water mark. Concurrent requests for
        /// the same pane share one capture and are notified before buffered live
        /// bytes are flushed.
        func requestResync(subscriptionId: UUID) {
            guard
                let subscription = subscriptions[subscriptionId],
                let context = readers[subscription.paneId]
            else { return }
            let paneId = subscription.paneId
            // Buffering and forward suppression are pane-wide. Every existing
            // subscriber therefore crosses the same snapshot boundary, even
            // when only one downstream queue reported overload.
            pendingResyncSubscribers[paneId, default: []].formUnion(context.subscriberIds)
            resyncingPaneIds.insert(paneId)
            guard resyncTasks[paneId] == nil else { return }

            resyncTasks[paneId] = Task { @MainActor [weak self] in
                await self?.runResyncLoop(paneId: paneId)
            }
        }

        /// Returns DEC private mode escape sequences to enable the pane's current mouse tracking mode.
        ///
        /// `capture-pane` only records text and SGR attributes, not terminal state like mouse
        /// tracking mode. Remote viewers need these sequences fed into SwiftTerm so their
        /// terminal reflects the host's mouse mode — otherwise mouse events are treated as local
        /// selection/scroll until the application redraws and re-emits the enable sequence.
        ///
        /// - Parameter paneId: The pane ID to query
        /// - Returns: Escape sequence bytes (empty if mouse mode is off or the pane is not known)
        public func mouseModeSequences(for paneId: String) async -> Data {
            guard let context = readers[paneId] else { return Data() }
            let mode: TmuxService.PaneMouseMode
            do {
                mode = try await tmuxService.getPaneMouseMode(context.target)
            } catch {
                logger.debug("Failed to query mouse mode, defaulting to off", metadata: [
                    "paneId": "\(paneId)",
                    "error": "\(error)",
                ])
                return Data()
            }

            var sequences = ""
            switch mode {
            case .standard:
                sequences += "\u{1b}[?1000h"
            case .button:
                sequences += "\u{1b}[?1002h"
            case .any:
                sequences += "\u{1b}[?1003h"
            case .off:
                return Data()
            }
            // SGR encoding is almost always paired with mouse tracking.
            sequences += "\u{1b}[?1006h"
            return Data(sequences.utf8)
        }

        /// Disconnect all readers (called on app shutdown).
        public func disconnectAll() async {
            isShuttingDown = true
            await readerStartGate.cancelAll()

            let paneIds = Array(readers.keys)
            for paneId in paneIds {
                await tearDownReader(paneId: paneId)
            }
            subscriptions.removeAll()
            pendingResyncSubscribers.removeAll()
            resyncingPaneIds.removeAll()
            paneRefreshTask?.cancel()
            paneRefreshTask = nil
            logger.info("Disconnected all pane readers")
        }

        // MARK: - Pane Lifecycle

        /// Start readers for all panes not already known. Called once on
        /// startup after initial pane discovery.
        public func startMonitoring(panes: [PaneInfo]) async {
            for pane in panes where readers[pane.paneId] == nil {
                let seedTitle = isCustomPaneTitle(pane.paneTitle) ? pane.paneTitle : nil
                await ensureReader(
                    paneId: pane.paneId,
                    sessionName: pane.sessionName,
                    target: pane.target,
                    initialWidth: pane.width,
                    initialHeight: pane.height,
                    seedTitle: seedTitle
                )
            }
        }

        /// Update readers based on the current pane list.
        ///
        /// Tears down readers for dead panes, starts readers for new panes,
        /// and seeds custom tmux pane titles that the OSC reader missed
        /// (e.g. set during async startup before pipe-pane attached).
        public func updateMonitoring(panes: [PaneInfo]) async {
            let currentPaneIds = Set(panes.map(\.paneId))
            let previousSessionPaneIds = Dictionary(grouping: readers, by: { $0.value.sessionName })
                .mapValues { Set($0.map(\.key)) }
            let currentSessionPaneIds = Dictionary(grouping: panes, by: \.sessionName)
                .mapValues { Set($0.map(\.paneId)) }

            // A moved pane also changes its textual target. Only rekey the
            // session-wide control client when the old session disappeared and
            // its complete pane-ID set reappeared under one new name.
            let renamedSessions = SessionRenameMapping.detectNames(
                from: previousSessionPaneIds,
                to: currentSessionPaneIds
            )
            for (oldName, newName) in renamedSessions {
                await controlClientManager.sessionRenamed(from: oldName, to: newName)
            }

            let staleIds = readers.keys.filter { !currentPaneIds.contains($0) }
            for paneId in staleIds {
                await tearDownReader(paneId: paneId)
            }

            for pane in panes where readers[pane.paneId] == nil {
                let seedTitle = isCustomPaneTitle(pane.paneTitle) ? pane.paneTitle : nil
                await ensureReader(
                    paneId: pane.paneId,
                    sessionName: pane.sessionName,
                    target: pane.target,
                    initialWidth: pane.width,
                    initialHeight: pane.height,
                    seedTitle: seedTitle
                )
            }

            // `rename-session` preserves pane IDs and live pipe-pane readers,
            // but every textual target changes. Update the reader context so
            // capture, mouse-mode and teardown commands stop using the old target.
            for pane in panes {
                guard var context = readers[pane.paneId] else { continue }
                guard context.target != pane.target || context.sessionName != pane.sessionName else { continue }
                context.target = pane.target
                context.sessionName = pane.sessionName
                readers[pane.paneId] = context
            }

            // Seed/update custom titles missed by the OSC reader (e.g. titles
            // tmux already had before pipe-pane attached).
            for pane in panes where isCustomPaneTitle(pane.paneTitle) {
                guard var context = readers[pane.paneId] else { continue }
                guard context.terminalTitle != pane.paneTitle else { continue }
                context.terminalTitle = pane.paneTitle
                readers[pane.paneId] = context
                onTitleChange?(pane.paneId, pane.target, pane.paneTitle)
            }
        }

        /// Start periodic pane discovery to detect new tmux sessions.
        ///
        /// Control clients only detect changes within their own session;
        /// new tmux sessions need periodic discovery.
        public func startPeriodicPaneRefresh(tmuxService: TmuxService) {
            paneRefreshTask?.cancel()
            paneRefreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled else { break }
                    let panes = await tmuxService.refreshPanes()
                    await self?.updateMonitoring(panes: panes)
                }
            }
        }

        // MARK: - Reader Lifecycle Helpers

        @discardableResult
        private func ensureReader(
            paneId: String,
            sessionName: String,
            target: String,
            initialWidth: Int,
            initialHeight: Int,
            seedTitle: String?
        ) async -> Bool {
            guard !isShuttingDown else { return false }
            if readers[paneId] != nil { return true }

            return await readerStartGate.run(paneId: paneId) { [weak self] in
                guard let self, !self.isShuttingDown else { return false }
                if self.readers[paneId] != nil { return true }
                return await self.startReader(
                    paneId: paneId,
                    sessionName: sessionName,
                    target: target,
                    initialWidth: initialWidth,
                    initialHeight: initialHeight,
                    seedTitle: seedTitle
                )
            }
        }

        private func startReader(
            paneId: String,
            sessionName: String,
            target: String,
            initialWidth: Int,
            initialHeight: Int,
            seedTitle: String?
        ) async -> Bool {
            let reader = PipePaneReader(paneId: paneId)
            await reader.setDelegate(self)

            do {
                try await reader.startPipePane(
                    controlClientManager: controlClientManager,
                    sessionName: sessionName
                )
                guard !Task.isCancelled, !isShuttingDown else {
                    await reader.stopPipePane(
                        controlClientManager: controlClientManager,
                        sessionName: sessionName
                    )
                    return false
                }
                readers[paneId] = ReaderContext(
                    reader: reader,
                    target: target,
                    sessionName: sessionName,
                    width: initialWidth,
                    height: initialHeight,
                    subscriberIds: [],
                    terminalTitle: seedTitle,
                    hasRegisteredDimensions: false
                )
                if let seedTitle {
                    onTitleChange?(paneId, target, seedTitle)
                }
                logger.debug("Started reader", metadata: ["paneId": "\(paneId)"])
                return true
            } catch {
                logger.debug("Failed to start reader", metadata: [
                    "paneId": "\(paneId)",
                    "error": "\(error)",
                ])
                return false
            }
        }

        private func tearDownReader(paneId: String) async {
            if let task = resyncTasks.removeValue(forKey: paneId) {
                task.cancel()
                _ = await task.value
            }
            pendingResyncSubscribers.removeValue(forKey: paneId)
            resyncingPaneIds.remove(paneId)

            guard let context = readers.removeValue(forKey: paneId) else { return }

            // Drop subscriptions belonging to this pane (caller likely already
            // unsubscribed, but this guards against shutdown ordering bugs).
            for subId in context.subscriberIds {
                subscriptions.removeValue(forKey: subId)
            }

            await context.reader.stopPipePane(
                controlClientManager: controlClientManager,
                sessionName: context.sessionName
            )

            if context.hasRegisteredDimensions {
                await controlClientManager.unregisterPane(
                    paneId: paneId,
                    sessionName: context.sessionName
                )
            }

            logger.debug("Tore down reader", metadata: ["paneId": "\(paneId)"])
        }

        // MARK: - PipePaneReaderDelegate

        public func pipePaneReader(_ paneId: String, didReceiveData data: Data) {
            TerminalTransportMetrics.shared.recordLocalOutput(paneId: paneId)
            forwardData(paneId: paneId, data: data)
        }

        public func pipePaneReaderDidOverflow(_ paneId: String) {
            guard let context = readers[paneId] else { return }
            for subscriptionId in context.subscriberIds {
                requestResync(subscriptionId: subscriptionId)
            }
        }

        public func pipePaneReader(
            _ paneId: String,
            didReceiveNotification notification: TerminalStreamMessage.TerminalNotification
        ) {
            forwardNotification(paneId: paneId, notification: notification)
        }

        public func pipePaneReader(_ paneId: String, didReceiveTitle title: String) {
            handleStreamTitleChange(paneId: paneId, title: title)
        }

        public func pipePaneReader(_ paneId: String, didReceiveClipboard content: String) {
            forwardClipboard(paneId: paneId, content: content)
        }

        public func pipePaneReader(_ paneId: String, didReceiveProgress progress: TerminalProgressState) {
            onProgress?(paneId, progress)
        }

        // MARK: - Private Forwarding

        private func forwardData(paneId: String, data: Data) {
            guard !resyncingPaneIds.contains(paneId) else { return }
            guard let context = readers[paneId] else { return }

            for subscriberId in context.subscriberIds {
                if let subscription = subscriptions[subscriberId] {
                    subscription.onData(data)
                }
            }
        }

        private func runResyncLoop(paneId: String) async {
            defer {
                resyncTasks[paneId] = nil
                resyncingPaneIds.remove(paneId)
            }

            while !Task.isCancelled {
                guard
                    pendingResyncSubscribers[paneId]?.isEmpty == false,
                    var context = readers[paneId]
                else { return }

                await context.reader.setBuffering(true)
                if let dimensions = try? await tmuxService.getPaneDimensions(context.target) {
                    context.width = dimensions.width
                    context.height = dimensions.height
                    readers[paneId] = context
                }

                let viewerScrollbackLineLimit = configuredScrollbackLineLimit
                let snapshotScrollbackLineLimit = context.subscriberIds
                    .compactMap { subscriptions[$0] }
                    .map {
                        resolvedSnapshotScrollbackLineLimit(
                            maximum: $0.maximumSnapshotScrollbackLineLimit
                        )
                    }
                    .max() ?? viewerScrollbackLineLimit
                let captured: Data
                do {
                    captured = try await tmuxService.capturePaneViaControlMode(
                        paneId: paneId,
                        width: context.width,
                        height: context.height,
                        controlClientManager: controlClientManager,
                        sessionName: context.sessionName,
                        scrollbackLineLimit: snapshotScrollbackLineLimit
                    )
                } catch {
                    let targets = pendingResyncSubscribers.removeValue(forKey: paneId) ?? []
                    await context.reader.setBuffering(false)
                    for subscriptionId in targets {
                        subscriptions[subscriptionId]?.onResync?(.failure(error))
                    }
                    logger.error("Failed to resynchronize pane stream", metadata: [
                        "paneId": "\(paneId)",
                        "error": "\(error)",
                    ])
                    return
                }

                guard !Task.isCancelled else {
                    await context.reader.setBuffering(false)
                    return
                }

                // Include requests that arrived while capture-pane was suspended.
                let targets = pendingResyncSubscribers.removeValue(forKey: paneId) ?? []
                TerminalTransportMetrics.shared.recordResync()
                for subscriptionId in targets {
                    guard let subscription = subscriptions[subscriptionId] else { continue }
                    subscription.onResync?(.success(SubscriptionResult(
                        subscriptionId: subscriptionId,
                        initialContent: captured,
                        width: context.width,
                        height: context.height,
                        scrollbackLineLimit: viewerScrollbackLineLimit
                    )))
                }

                // Reset callbacks are synchronous MainActor work. Once they all
                // ran, allow the reader's buffered post-snapshot bytes through.
                resyncingPaneIds.remove(paneId)
                await context.reader.flushBuffer()

                guard pendingResyncSubscribers[paneId]?.isEmpty == false else { return }
                resyncingPaneIds.insert(paneId)
            }
        }

        private func forwardDimensionChange(paneId: String, width: Int, height: Int) {
            guard let context = readers[paneId] else { return }

            for subscriberId in context.subscriberIds {
                if
                    let subscription = subscriptions[subscriberId],
                    let callback = subscription.onDimensionChange {
                    callback(width, height)
                }
            }
        }

        private func forwardTitleChange(paneId: String, title: String, excludingSubscription: UUID?) {
            guard let context = readers[paneId] else { return }

            for subscriberId in context.subscriberIds where subscriberId != excludingSubscription {
                if
                    let subscription = subscriptions[subscriberId],
                    let callback = subscription.onTitleChange {
                    callback(title)
                }
            }
        }

        /// Handle title change detected by the per-pane reader (from raw pipe-pane data).
        /// Updates the reader context and forwards to all subscribers and the global handler.
        private func handleStreamTitleChange(paneId: String, title: String) {
            guard var context = readers[paneId] else { return }
            guard !title.isEmpty, context.terminalTitle != title else { return }
            context.terminalTitle = title
            readers[paneId] = context

            // Notify global handler (MirrorWindowManager)
            onTitleChange?(paneId, context.target, title)

            // Forward to all subscribers
            forwardTitleChange(paneId: paneId, title: title, excludingSubscription: nil)
        }

        private func forwardClipboard(paneId: String, content: String) {
            guard let context = readers[paneId] else { return }
            for subscriberId in context.subscriberIds {
                if
                    let subscription = subscriptions[subscriberId],
                    let callback = subscription.onClipboard {
                    callback(content)
                }
            }
        }

        private func forwardNotification(
            paneId: String,
            notification: TerminalStreamMessage.TerminalNotification
        ) {
            // Call global handler unconditionally — desktop notifications fire
            // even for panes that aren't being mirrored.
            onNotification?(paneId, notification)

            // Forward to per-subscriber handlers (only if a stream has subscribers)
            guard let context = readers[paneId] else { return }
            for subscriberId in context.subscriberIds {
                if
                    let subscription = subscriptions[subscriberId],
                    let callback = subscription.onNotification {
                    callback(notification)
                }
            }
        }
    }

#endif
