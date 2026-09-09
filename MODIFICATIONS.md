# Modifications

- **Distribution**: CtrlX
- **Fork point**: `919c7772928531d4d0bb266bdf275691d361901e`
- **Fork date**: 2026-08-14
- **Maintainer**: ZengJice `<jicezeng@gmail.com>`
- **Upstream**: [gpambrozio/Gallager](https://github.com/gpambrozio/Gallager)
- **License**: GNU AGPL-3.0

## 3.0.26 — Focused agent skills and image review

- Reduce the two bundled skill entrypoints from 444 to 131 lines, with
  task-specific references for CLI workflows and sidecar contracts.
- Correct CLI targeting/JSON examples and sidecar permission encodings; ignore
  child-agent completion in the starter template. Add isolated protocol,
  resource-sync, and documentation-size regressions.
- Bump the bundled Claude plugin to 1.3.2 and Codex plugin to 1.1.1 so updated
  skills have distinct cache versions.
- Let iOS users open a pending image to review the compressed content, with
  pinch/double-tap zoom and a separate remove action.
- Publish a new Mac package; the existing 3.0.25 Relay remains compatible and
  does not require redeployment. Image review requires a separate iOS build.

## 3.0.25 — Ordered Relay forwarding

- Preserve wire order across text and binary WebSocket frames with one bounded
  inbound FIFO and one async forwarding worker per connection.
- Keep early frames behind pair/entitlement validation. Discard queued frames
  on close, replacement or overflow; recheck source ownership at the send boundary.
- Add lossless-loopback regressions for both directions, immediate upgrade
  traffic, chunked snapshots and the final SwiftTerm composer/status rows.
- Deploy the Relay first and reconnect viewers for a fresh snapshot. Existing
  3.0.24 Mac/iOS clients remain compatible and do not need rebuilding for this fix.

## 3.0.24 — Native terminal viewport synchronization

- Pin the SwiftTerm fork fix that synchronizes the iOS viewport after native
  size/inset changes, including repeated requests for the current bottom row.
- Present an iOS session's initial tail after its native view is attached and
  laid out, without waiting for another terminal output byte.
- Preserve manual history scrolling, selection, and gesture ownership. Add
  regression coverage for initial presentation and native viewport drift.
- Keep the 3.0.23 Host stream fixes unchanged. The iOS viewport correction
  requires an updated iOS build; installing this Mac package alone cannot
  activate it on an iPhone. No Relay deployment is needed for these changes.

## 3.0.23 — Host terminal stream consistency

- Keep snapshot capture and live output on one control connection per tmux
  session, including concurrent connections and pane reopen operations.
- Capture history, visible cells, and cursor in one tmux command transaction;
  drain late responses after timeouts without shifting subsequent requests.
- Add real-tmux regression coverage for duplicate output and inconsistent
  screen/cursor state. Update the Host Mac running the affected sessions;
  updating only a Viewer or Relay does not activate these fixes.

See [terminal rendering investigation](docs/terminal-rendering-investigation.md)
for reproduced causes and verification scope.

## Major changes

- Rebranded the macOS app, iOS app, CLI, Relay, and documentation as CtrlX.
- Isolated Apple bundle identifiers, App Group, Keychain, local state, sockets,
  environment variables, tmux metadata, update infrastructure, and telemetry
  from Gallager.
- Added explicit build-to-source metadata and Relay source-disclosure endpoints.
- Retained the pre-existing customized terminal, tmux, remote-control, Relay,
  notification, and performance work in the complete Git history.

Detailed implementation and acceptance status live in
[`docs/v3.0.0`](docs/v3.0.0/).

This file records distribution-level changes, not every individual commit.
Consult the Git history and release notes for detailed changes.
