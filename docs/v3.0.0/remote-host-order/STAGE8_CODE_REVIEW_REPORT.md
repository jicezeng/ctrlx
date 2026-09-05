# Stage 8 Code Review Report

## Review Scope

- Range: `83f8cd9..dfaaf12`
- Shared remote Host move semantics and persistence
- macOS Viewer sidebar Host drag-and-drop
- iOS Viewer Edit-mode Host drag-and-drop
- Pairing update, append, delete and reload lifecycle

## Findings

- **P2 / Resolved**：首版把拖放源和目标放在 iOS `List` 的 Section header。
  真机 Edit 模式下系统不把 Section header 作为可重排行，手柄可见但拖放不生效。
- 修复移除该假入口，改在 Manage Hosts 的平面 `ForEach` 上使用系统 `onMove`；
  Sessions 页的 Edit 继续只管理 session，两个排序层级不再争用手势。

## Verification

- `RemoteHostOrder` and settings tests: 5/5 passed.
- macOS `CtrlxServer` App target build: passed.
- iOS `Ctrlx` generic-device App target build: passed.
- `git diff --check`: passed.
- SwiftLint was unavailable locally; both App builds reported the existing install hint only.

## Design Review

- `pairedHosts` remains the only order source; no parallel preference can drift from it.
- Existing pairings update in place, new pairings append, and deletion preserves the remaining order.
- Host drag payloads are accepted only when they match a paired Host ID, avoiding accidental cross-layer drops.
- Relay protocol, Host tmux state and other Viewers are unchanged; ordering stays local to each Viewer.
- Sidebar, menu, keyboard traversal and settings continue reading the same `pairedHosts` array.

## Acceptance

- Corrected iOS Manage Hosts native List reordering passed physical-device acceptance.
- macOS implementation passed focused review, signed Release build, signature verification and local installation.
- The user explicitly authorized integration and package publication after the installed-App review.

## Assessment

Approved for integration into `develop/v3.0.0` and package publication.
