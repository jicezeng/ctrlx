# Stage 9: Shared Terminal Layout

## Goal

Keep the terminal-window split for a tmux session consistent across CtrlX Mac
clients. A Host split such as `win1 | win2` must render as the same two-window
workspace on a Mac Viewer instead of leaking only the resized tmux dimensions.

## Ownership

- The Host owns the canonical layout and revision.
- A Viewer may request a layout change; the Host validates and republishes it.
- tmux dimensions change only after a user clicks “fit to this Mac” on a Host
  or Viewer; the last explicit action wins.
- The Relay only forwards the existing E2EE messages and stores no layout.
- tmux pane topology remains independent and continues to use `windowLayout`.

## Shared State

One optional snapshot per tmux session:

- left tmux window stable ID
- ordered stable IDs assigned to the right side
- selected right-side tmux window stable ID
- left-side split ratio
- Host-assigned monotonic revision

File tabs, browser tabs, their focus/selection, scroll position, keyboard state
and pixel dimensions are intentionally excluded.

## Implementation

1. Add the shared layout model to `ClaudeSpyNetworking` and carry it in the
   existing encrypted `SessionStateMessage`.
2. Store canonical layouts in `MirrorWindowManager`; prune dead sessions and
   reject missing/duplicate Window IDs.
3. Add one Viewer-to-Host command containing only the requested logical
   layout. The Host assigns the revision and broadcasts a fresh session state.
4. Reconcile the selected local/remote `SessionFileTabsState` with the shared
   terminal layout while preserving local browser/file-tab state.
5. Debounce divider changes and skip equal snapshots to avoid echo traffic.
6. Remove automatic resize triggers. One toolbar action fits every visible tmux
   window to the current Mac. Viewer requests carry an optional
   `userInitiated` marker; the Host accepts only `true`, so legacy automatic
   requests remain harmless.

## Compatibility

The new session-state field is optional. Older peers ignore it; newer Viewers
fall back to their existing local layout when an older Host omits it.

## Acceptance

- Host `win1 | win2` appears as `win1 | win2` on a Mac Viewer.
- Collapsing or changing the ratio propagates once and survives reconnect.
- Viewer changes are accepted by the Host and reflected back to other Viewers.
- Browser/file tabs remain local and are not erased by terminal reconciliation.
- Activating, selecting, resizing, changing fonts or changing a split never
  changes tmux dimensions by itself.
- The Host and Viewer toolbar actions each fit all currently visible terminal
  windows, including two different windows shown side by side.
- Native tmux pane splits continue to render unchanged.
