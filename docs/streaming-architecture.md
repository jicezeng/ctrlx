# Terminal Streaming Architecture

This document describes how terminal data flows from a tmux session on the Mac to both the local Mac mirror view and remote iOS devices. The architecture achieves low-latency mirroring with proper UTF-8 handling, data batching, and end-to-end encryption.

## High-Level Overview

```mermaid
graph TB
    subgraph Mac["Mac (CtrlxServer)"]
        TMUX[tmux session]
        TCC[TmuxControlClient]
        PPR[PipePaneReader<br/>one per pane]
        PSM[PaneStreamManager<br/>delegate + multiplexer]
        TSS[TerminalStreamService]
        DCM[ConnectedViewerManager]
        MV[Mac Mirror View<br/>SwiftTerm]
    end

    subgraph Server["External Relay Server"]
        CH[ConnectionHub]
        RS[RelayService]
    end

    subgraph iOS["iOS (Ctrlx)"]
        RC[RelayClient]
        SC[StreamCoordinator]
        TS[TerminalState]
        IV[iOS Terminal View<br/>SwiftTerm]
    end

    TMUX -->|"control mode (-f no-output)"| TCC
    TCC -->|commands, events| PSM
    TMUX -->|"pipe-pane raw bytes"| PPR
    PPR -->|"PipePaneReaderDelegate (data + OSC)"| PSM
    PSM -->|subscriber| MV
    PSM -->|subscriber| TSS
    TSS -->|batched| DCM
    DCM -->|encrypted per device| CH
    CH <--> RS
    CH <-->|WebSocket per pairId| RC
    RC -->|onTerminalStream| SC
    SC --> TS
    TS --> IV
```

## Component Details

### 1. Tmux Data Capture (Mac)

The Mac app uses a **hybrid approach**: tmux control mode for commands and event notifications, and `pipe-pane` for raw PTY byte delivery.

```mermaid
sequenceDiagram
    participant T as tmux
    participant TCC as TmuxControlClient
    participant PPR as PipePaneReader
    participant PSM as PaneStreamManager

    TCC->>T: tmux -C attach -t session -f no-output,ignore-size
    T-->>TCC: (control mode ready)

    PSM->>PPR: setDelegate(self) + startPipePane()
    Note over PPR: starts in scan-only mode
    PPR->>T: pipe-pane -O "cat > /tmp/fifo"
    PPR->>PPR: Open FIFO for reading

    loop Raw PTY Bytes
        T->>PPR: raw bytes via FIFO
        PPR->>PPR: Filter tmux ESC k title sequences
        PPR->>PPR: Parse OSC notification/title/clipboard/progress
        PPR->>PSM: PipePaneReaderDelegate.didReceive*
    end

    T->>TCC: %layout-change
    TCC->>TCC: Update cached dimensions
    TCC->>PSM: Dimension change callback
```

**Key Files:**
- `CtrlxServerFeature/Services/PipePaneReader.swift`
- `CtrlxServerFeature/Services/TmuxControlClient.swift`
- `CtrlxServerFeature/Services/TmuxService.swift`

**PipePaneReader** is an actor that:
- Manages a per-pane FIFO (`/tmp/ctrlx-pipe-<id>.fifo`) for raw byte delivery. One reader instance per tmux pane lives for the pane's full lifetime — mirror toggling never restarts it
- Reads raw PTY bytes via `pipe-pane -O` piped through the FIFO
- Filters only tmux's `ESC k ... ESC \` title sequences and parses OSC 9/777/9;4/0/2/52 notification, title, clipboard, and progress events
- Uses AsyncStream + single consumer task for strict FIFO ordering of data chunks
- Forwards events through a single `PipePaneReaderDelegate` (`@MainActor`) — one method per event type so missing a wiring becomes a compile error
- Has three data-delivery modes:
  - **`scanOnly`** (default after `startPipePane`): parser doesn't build `filteredData`, data bytes are discarded. OSC events still flow.
  - **`buffering`** (`setBuffering(true)`): bytes queued instead of forwarded; used while a `capture-pane` snapshot is being taken so live bytes that arrive during the snapshot aren't dropped.
  - **`live`** (`flushBuffer`): drains the queue to the delegate in order, then forwards subsequent bytes directly.

**TmuxControlClient** is an actor that:
- Maintains a long-lived `tmux -C attach -f no-output,ignore-size` process
- Handles commands via `sendCommand()` (capture-pane, list-panes, pipe-pane, etc.)
- Parses event notifications (`%layout-change`, `%session-changed`, `%exit`)
- Does **not** handle `%output` events (suppressed by `-f no-output`)

### 2. Local Stream Management (Mac)

**PaneStreamManager** owns one `PipePaneReader` per known pane and multiplexes its events to subscribers. It conforms to `PipePaneReaderDelegate` so all event wiring lives in exactly one place.

The reader's data-delivery mode is the state machine that used to belong to a separate `PaneStream`:

```mermaid
stateDiagram-v2
    [*] --> scanOnly: startPipePane (pane discovered)
    scanOnly --> buffering: subscribe → setBuffering(true)
    buffering --> live: capture-pane done → flushBuffer
    live --> scanOnly: last unsubscribe → setBuffering(false)
    scanOnly --> [*]: pane removed → stopPipePane
```

`subscribe(paneId:target:...)` follows the canonical sequence:

1. `setBuffering(true)` — start retaining live bytes.
2. `capture-pane` snapshot via control mode.
3. Add subscriber.
4. `flushBuffer()` — drain the queue through the delegate (this manager) → `forwardData` → subscriber's `onData`. Subsequent bytes flow live.

When the last subscriber leaves, the manager only calls `setBuffering(false)`. The reader stays attached to the FIFO, so OSC events (notifications, titles, progress, clipboard) keep flowing for desktop notifications and sidebar UI.

```mermaid
graph LR
    subgraph PaneStreamManager
        R1[PipePaneReader<br/>session:0.1]
        R2[PipePaneReader<br/>session:0.2]
    end

    R1 -->|delegate| PSM[PaneStreamManager]
    R2 -->|delegate| PSM

    PSM --> S1[Mirror Window]
    PSM --> S2[TerminalStreamService]
    PSM --> S3[Mirror Window 2]
    PSM --> S4[TerminalStreamService]
```

**Key Files:**
- `CtrlxServerFeature/Services/PaneStreamManager.swift`
- `CtrlxServerFeature/Services/PipePaneReader.swift`

Subscribers share a single reader. PaneStreamManager uses `TmuxControlClientManager` for commands (capture-pane, pipe-pane attach) and dimension tracking; per-pane state lives in a single `readers: [String: ReaderContext]` dictionary that records the reader, target, dimensions, subscriber set, and latest title.

### 3. Mac Mirror View

The local Mac mirror receives data through a PaneStreamManager subscription:

```mermaid
flowchart LR
    PSM[PaneStreamManager] -->|onData| ITV[InteractiveTerminalView]
    ITV --> ST[SwiftTerm]
    ITV -->|onInput| TS[TmuxService.sendKeys]
```

**Key File:** `CtrlxServerFeature/Views/InteractiveTerminalView.swift`

### 4. Remote Streaming (Mac → Server)

**TerminalStreamService** bridges local streams to the viewers that subscribed
to each pane via **ConnectedViewerManager**:

```mermaid
sequenceDiagram
    participant PSM as PaneStreamManager
    participant TSS as TerminalStreamService
    participant CVM as ConnectedViewerManager
    participant V1 as Subscribed Viewer A
    participant V2 as Unsubscribed Viewer B

    PSM->>TSS: onData (raw bytes)
    TSS->>TSS: Buffer data

    alt Batch ready (8KB or 16ms)
        TSS->>TSS: Create TerminalStreamMessage
        TSS->>CVM: sendTerminalStream(to: subscribers)
        CVM->>V1: sendTerminalStream() (E2EE)
        Note over CVM,V2: no terminal payload for unrelated viewers
    end
```

**Batching Strategy:**
- Maximum wait: 16ms fixed cadence (not trailing debounce)
- Maximum batch size: 8KB
- Prevents network saturation without starving a continuously updating TUI

**Multi-Viewer Ownership:**
- `TerminalStreamService` tracks an idempotent set of Viewer IDs per pane
- The first Viewer creates the PaneStreamManager subscription
- Additional Viewers reuse that stream and receive a private bootstrap snapshot
- Bootstrap data is drained before `StartTerminalStream` returns success
- Live chunks and terminal control events are sent only to ready subscribers; a joining Viewer cannot refresh others or receive pre-initial updates
- `stopStreaming()` removes one owner; the stream stops when the set becomes empty
- System-level cleanups (`stopAllStreams`, `stopStreamsForClosedPanes`) use `force: true`

**Message Types:**
```swift
enum StreamUpdateType {
    case initialState(InitialState)     // Full buffer on stream start
    case dataChunk(DataChunk)           // Incremental updates
    case dimensionChange(DimensionChange) // Terminal resized
    case streamEnd                       // Stream closed
}
```

**Key Files:**
- `CtrlxServerFeature/Services/TerminalStreamService.swift`
- `CtrlxServerFeature/Services/ConnectedViewerManager.swift`
- `CtrlxServerFeature/Services/DeviceConnection.swift`

### 5. External Relay Server

The Vapor server routes messages between paired Mac and iOS devices. Each pairing (pairId) represents one Mac-iOS device pair. A Mac can have multiple pairings (one per iOS device), and each pairing has its own WebSocket connection.

```mermaid
flowchart TB
    subgraph WebSocket Connections
        MAC1[Mac Connection<br/>pairId=A]
        MAC2[Mac Connection<br/>pairId=B]
        IOS1[iOS Device A<br/>pairId=A]
        IOS2[iOS Device B<br/>pairId=B]
    end

    subgraph Server Logic
        WC[WebSocketController]
        RS[RelayService]
        CH[ConnectionHub]
    end

    MAC1 <-->|/api/ws?pairId=A&deviceType=mac| WC
    MAC2 <-->|/api/ws?pairId=B&deviceType=mac| WC
    IOS1 <-->|/api/ws?pairId=A&deviceType=ios| WC
    IOS2 <-->|/api/ws?pairId=B&deviceType=ios| WC
    WC <--> RS
    RS <--> CH
```

**ConnectionHub** maintains the connection registry:

```mermaid
graph TB
    subgraph "connections[pairId]"
        subgraph "pair-A (Mac ↔ iOS Device A)"
            M1[mac: Connection]
            I1[ios: Connection]
        end
        subgraph "pair-B (Mac ↔ iOS Device B)"
            M2[mac: Connection]
            I2[ios: Connection]
        end
    end
```

**Message Routing:**
1. Mac's `ConnectedViewerManager` sends encrypted terminal data per subscribed Viewer
2. Each `DeviceConnection` sends via its own WebSocket (unique pairId)
3. RelayService receives message, looks up iOS connection by pairId
4. ConnectionHub forwards to iOS (encrypted payload is pass-through)
5. Server cannot decrypt—true end-to-end encryption

**Key Files:**
- `CtrlxExternalServer/Routes/WebSocketController.swift`
- `CtrlxExternalServer/Services/RelayService.swift`
- `CtrlxExternalServer/Services/ConnectionHub.swift`

### 6. iOS Reception

**RelayClient** receives WebSocket messages and decrypts them:

```mermaid
sequenceDiagram
    participant WS as WebSocket
    participant RC as RelayClient
    participant E2E as E2EE
    participant SC as StreamCoordinator

    WS->>RC: Encrypted message
    RC->>E2E: Decrypt
    E2E-->>RC: TerminalStreamMessage
    RC->>SC: onTerminalStream(message)
```

**Key File:** `CtrlxFeature/Services/RelayClient.swift`

### 7. iOS Display

**StreamCoordinator** manages the streaming session state:

```mermaid
stateDiagram-v2
    [*] --> idle
    idle --> starting: startStreaming()
    starting --> streaming: initialState received
    streaming --> streaming: dataChunk/dimensionChange
    streaming --> ended: streamEnd
    ended --> idle: reset
```

**Data flow to terminal:**

```mermaid
flowchart LR
    SC[StreamCoordinator] --> TS[TerminalState]
    TS -->|onData| STV[SwiftTerm]
    TS -->|onResize| STV
```

**Key Files:**
- `CtrlxFeature/Views/LiveTerminalView.swift`
- `CtrlxFeature/Views/TerminalStreamContainerView.swift`

### 8. Connection Liveness & Reconnection

A network switch (Wi-Fi↔Wi-Fi, Wi-Fi↔cellular, VPN toggle) leaves a
`URLSessionWebSocketTask` **half-open**: the old TCP connection is dead but
neither `send()` nor a blocked `receive()` errors promptly. Two mechanisms keep
this from turning into a stuck "green dot but nothing flows" state (issue #642):

**Client-side liveness watchdog** — `ViewerRelayClient` (viewer) and
`ConnectedViewer` (host) run a keep-alive ping loop that now *verifies* a reply.
Each cycle sets an `awaitingPong` flag before sending `.ping`; **any** inbound
frame (the `.pong`, terminal data, session state…) clears it. If the flag is
still set after the pong timeout, the socket is treated as half-open and
`cancel()`led, which makes `receiveMessages()` observe the failure and run the
normal disconnection → exponential-backoff reconnection path exactly once.
Without this, a half-open socket stays `.connected` indefinitely and only
`receive()` erroring (which a network switch does not reliably cause) or an app
restart would recover it.

**Server-side identity-aware unregister** — when a device reconnects it opens a
*new* socket that replaces the old entry in `ConnectionHub` (keyed by
`(pairId, deviceType)`). The old half-open socket's `onClose` can fire
seconds-to-minutes later. `ConnectionHub.unregisterIfCurrent(...)` only removes
the entry (and only then notifies the peer of a disconnect) when the closing
socket is *still the registered one*, so a stale close — or a `send` that fails
on a socket that was concurrently replaced — is a no-op. This prevents a late
close from evicting the live replacement and falsely flipping the peer's
`isViewerConnected`/`isHostConnected` to false. That flag gates
`pushSessionState()` (but not `sendTerminalStream()`), so the bug it caused was
specifically "live terminal keeps streaming, but new-session/new-tab/switch-window
updates never reach the viewer."

> **Server-initiated teardown must notify the peer itself.** `notifyConnection`
> for a disconnect only fires from `WebSocketController`'s `onClose` (which owns
> `RelayService`). A server-initiated teardown — the E2E `blockDevice` /
> `disconnectDevice` helpers, which close the socket *and* remove the
> `ConnectionHub` entry directly (so `isViewerConnected` / `isHostConnected` flip
> to false immediately) — makes that later `onClose` a deliberate no-op under
> `unregisterIfCurrent`, since the entry is already gone. So those helpers take
> the pair IDs returned by `disconnectAll(deviceType:)` and drive
> `notifyConnection(..., connected: false)` themselves; otherwise a viewer whose
> host was disconnected would never learn to clear its sessions (regression that
> surfaced in the *Host Disconnect Clears Sessions* E2E scenario).

## Complete Data Flow

```mermaid
sequenceDiagram
    participant TMUX as tmux
    participant PPR as PipePaneReader
    participant TCC as TmuxControlClient
    participant PSM as PaneStreamManager
    participant MV as Mac Mirror
    participant TSS as TerminalStreamService
    participant DCM as ConnectedViewerManager
    participant SRV as Relay Server
    participant RC as RelayClient
    participant SC as StreamCoordinator
    participant IV as iOS Terminal

    Note over TMUX,IV: Pane Discovery (once per pane)

    PSM->>PPR: setDelegate(self) + startPipePane()
    PPR->>TCC: sendCommand("pipe-pane -O ...")
    TCC->>TMUX: pipe-pane command
    Note over PPR: Reader runs in scan-only mode<br/>OSC events flow but bytes are discarded

    Note over TMUX,IV: First Subscriber on Pane

    RC->>SRV: StartTerminalStream command
    SRV->>DCM: Forward command
    DCM->>TSS: Start stream for pane
    TSS->>PSM: subscribe(paneId)
    PSM->>PPR: setBuffering(true)
    Note over PPR: bytes now queued, not discarded
    PSM->>TCC: sendCommand("capture-pane ...")
    TCC->>TMUX: capture-pane command
    TMUX-->>TCC: capture result
    TCC-->>PSM: initial content
    PSM->>PPR: flushBuffer()
    PPR->>PSM: didReceiveData (queued bytes, in order)
    Note over PPR,PSM: flush returns after delegate delivery barrier
    Note over PPR: subsequent bytes flow live to delegate
    PSM-->>TSS: subscriber callback (initial + buffered)
    TSS->>DCM: sendTerminalStream(initialState, to: requester)
    DCM->>SRV: Encrypted per device
    SRV->>RC: Forward to iOS
    RC->>SC: onTerminalStream(initialState)
    SC->>IV: feed(content) while hidden
    TSS->>DCM: drain pre-barrier data to requester
    DCM-->>RC: StartTerminalStream success (bootstrap ready)
    SC->>IV: reveal once

    Note over TMUX,IV: Second Device Subscribes

    RC->>SRV: StartTerminalStream (same pane)
    SRV->>DCM: Forward command
    DCM->>TSS: startStreaming() — stream exists
    TSS->>PSM: currentContent(for: paneId)
    PSM-->>TSS: current terminal content
    TSS->>TSS: Add Viewer ID in bootstrapping state
    TSS->>DCM: sendTerminalStream(initialState, to: requester)
    TSS->>DCM: drain private bootstrap data to requester
    DCM-->>RC: StartTerminalStream success

    Note over TMUX,IV: Live Updates (to ready subscribers only)

    loop Terminal Output
        TMUX->>PPR: raw PTY bytes via FIFO
        PPR->>PSM: didReceiveData(data)
        PSM-->>MV: subscriber callback (immediate)
        PSM-->>TSS: subscriber callback
        TSS->>TSS: Buffer (batch)
        TSS->>DCM: sendTerminalStream(dataChunk, to: ready subscribers)
        DCM->>SRV: Encrypted per device
        SRV->>RC: Forward
        RC->>SC: onTerminalStream(dataChunk)
        SC->>IV: feed(data)
    end

    Note over TMUX,IV: Last Subscriber Leaves

    DCM->>TSS: stopStreaming
    TSS->>PSM: unsubscribe
    PSM->>PPR: setBuffering(false)
    Note over PPR: returns to scan-only mode<br/>FIFO stays attached for OSC events
```

## Key Architectural Decisions

| Decision | Rationale |
|----------|-----------|
| **Hybrid: control mode + pipe-pane** | Control mode for commands/events, pipe-pane for raw PTY bytes. Eliminates octal unescaping, UTF-8 reconstruction, and line-boundary splitting that caused rendering artifacts |
| **FIFO-based pipe-pane delivery** | Per-pane FIFO (`/tmp/ctrlx-pipe-<id>.fifo`) avoids spawning a persistent subprocess; tmux's `cat > fifo` blocks until reader connects |
| **AsyncStream ordering** | Single consumer task per data source (PipePaneReader, TmuxControlClient, TerminalStreamService) prevents reordering that occurs with unstructured `Task {}` per callback |
| **One persistent reader per pane** | PipePaneReader is created at pane discovery and lives until the pane is removed. Mirror toggling switches its delivery mode (`scanOnly`/`buffering`/`live`) instead of detaching/reattaching `pipe-pane`, eliminating the FIFO swap window where bytes could be lost. All event wiring lives on a single `PipePaneReaderDelegate` so missing a handler is a compile error |
| **Buffering during initial capture** | PipePaneReader queues raw bytes during the `capture-pane` snapshot, then `flushBuffer()` drains the queue to the delegate in order before switching to live mode — eliminates the gap between capture and live stream |
| **Stream manager decoupling** | Streaming works without mirror window open, only needs iOS connection |
| **Data batching (8KB/16ms)** | Bounds latency without saturating the relay |
| **Subscription model** | Multiple consumers (UI + remote) share one stream efficiently |
| **Multi-device ref counting** | Multiple iOS devices watch the same pane without interfering; iOS ignores duplicate `initialState` when already streaming |
| **Per-device E2EE** | Each DeviceConnection has its own E2EE session; server cannot decrypt |
| **Session ID validation** | Prevents stale callbacks from old sessions affecting new ones |
| **Fail-closed E2EE** | Refuses to send sensitive data if encryption session not established |
| **Ping/pong liveness watchdog** | Verifies keep-alive pongs so a half-open socket after a network switch is detected and reconnected within one ping cycle instead of staying `.connected` forever (§8) |
| **Identity-aware unregister** | The relay only unregisters a connection when the closing socket is still the registered one, so a stale socket's late close can't evict the reconnected replacement (§8) |

## Key Types Reference

| Type | Location | Purpose |
|------|----------|---------|
| `PipePaneReader` | ServerFeature | Per-pane FIFO reader for raw PTY bytes via pipe-pane. Three delivery modes (scanOnly/buffering/live), one per pane lifetime |
| `PipePaneReaderDelegate` | ServerFeature | `@MainActor` protocol for receiving data + OSC events from a reader |
| `TmuxControlClient` | ServerFeature | Control mode connection for commands and event notifications |
| `PaneStreamManager` | ServerFeature | Owns one reader per pane, conforms to `PipePaneReaderDelegate`, multiplexes events to subscribers |
| `TerminalStreamService` | ServerFeature | Batches and sends to remote, ref-counted per device |
| `ConnectedViewerManager` | ServerFeature | Multi-Viewer WebSocket coordinator |
| `DeviceConnection` | ServerFeature | Single iOS device WebSocket + E2EE |
| `ConnectionHub` | ExternalServer | Server-side routing |
| `RelayService` | ExternalServer | Message handling |
| `RelayClient` | Feature (iOS) | iOS WebSocket client |
| `StreamCoordinator` | Feature (iOS) | iOS streaming state |
| `TerminalState` | Feature (iOS) | Bridge to SwiftTerm |
| `TerminalStreamMessage` | Networking | Shared message model |
