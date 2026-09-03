# Stage 9 TODO

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 6/6 tasks
- **Dependencies**: v3.1.0 Stage 8 ✅

## Tasks

- [x] Document the minimal shared-layout contract and ownership rules.
- [x] Add the wire model, snapshot field and Viewer request command.
- [x] Add Host canonical storage, validation and revision assignment.
- [x] Reconcile Mac Host/Viewer UI and debounce outbound changes.
- [x] Make terminal resizing manual-only on both Host and Viewer.
- [x] Add unit/integration regression coverage and complete review.

## Verification

- `swift test --package-path ClaudeSpyPackage --skip-update`: 1,770 tests passed.
- macOS Xcode build: `ClaudeSpyServer` Debug build succeeded using an isolated
  DerivedData directory and the repository's existing local package cache.
- E2E scenarios cover Host-to-Viewer split, Viewer-to-Host collapse, multiple
  right-side terminals and dead-window pruning.

## Blockers

- None.
