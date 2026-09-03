# Stage 9 Code Review Report

## Scope

Review the macOS Host/Viewer shared terminal-layout implementation, wire
compatibility, state ownership, stale-state handling and regression coverage.

## Result

Approved. No unresolved Critical, High, Medium or Low findings remain.

## Findings Resolved

### High

- Decoupled private file/browser hydration from shared terminal placement, so
  an early Host split cannot suppress or overwrite a saved private workbench.
- Blocked local auto-save until the first layout-store read completes, closing
  the race where terminal-only shared state could overwrite that record first.
- Reapplied the current Host canonical terminal layout after private hydration,
  preserving both state domains without making either one authoritative for
  the other.
- Prevented a Host snapshot from resetting a same-session window selection
  before the user's new layout request could be published.
- Replaced the lossy single right-window field with an ordered list plus the
  selected right-window ID, preserving sessions with several right-side tabs.
- Observed the complete right-side terminal set so moving a non-selected tab
  cannot bypass synchronization.
- Guarded local and remote selection transitions so switching modes cannot
  apply the wrong canonical layout.

### Medium

- Kept `selectedRight` coherent when a shared terminal collapses while a
  private browser/file tab remains on the right, avoiding an empty placeholder.
- Pruned dead sessions and window IDs on the Host and advanced the canonical
  revision, preventing stale split state from surviving a tmux window close.
- Preserved Viewer-local browser and file-tab state while replacing only
  terminal-window placement.
- Added a capability check so a new Viewer never sends the new command to an
  older Host.

## Architecture Assessment

- The Host is the only canonical state and revision owner.
- The Viewer sends one validated logical-layout request.
- The Relay remains a stateless E2EE frame forwarder.
- Pixel geometry, focus, scroll, keyboard and browser/file tabs remain local.
- Native tmux pane topology continues through the existing pane-state path.
- Geometry never mutates tmux automatically. A Host or Viewer may explicitly
  fit all visible terminal windows to its own viewport; Viewer requests require
  a user-action marker, so old automatic requests remain rejected.

This is the smallest protocol that fixes the observed defect without creating
a second general-purpose workspace synchronization system.

## Verification

- Full SwiftPM suite: 1,770 tests passed in 258 suites.
- macOS `ClaudeSpyServer` Debug Xcode build succeeded.
- Wire compatibility tests cover new and legacy snapshots.
- Host-store tests cover validation, ratio clamping, revision assignment,
  duplicate suppression and dead-window pruning.
- Mac E2E scenarios cover bidirectional convergence and reconnect-safe
  canonical snapshots.

## Residual Risk

Both participating Mac apps must contain this feature for synchronized layout.
Mixed versions remain functional, but deliberately fall back to client-local
layout because the optional capability field is absent.
