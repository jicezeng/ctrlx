# Stage 30 TODO：macOS tmux window 快捷导航

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 5/5 tasks
- **Dependencies**: Stage 29 ✅

## Tasks

- [x] 核对现有 tab/session 菜单命令、window 选择和分屏状态模型。
- [x] 增加纯 window 导航决策与聚焦测试。
- [x] 接入 scene-scoped macOS 菜单快捷键及本地/远程选择。
- [x] 完成完整测试、构建与代码审查。
- [x] 合入 `develop/v2.8.0` 并清理 worktree。

## Decisions

- 保留现有 `⌘⇧[` / `⌘⇧]` 全 tab 导航；新命令只处理 tmux window。
- 分屏只导航左侧主区域，右侧内容保持固定，避免在没有 side-focus 单一真相时猜测用户焦点。
- 第一版使用固定的 macOS 惯用快捷键，不引入快捷键录制、冲突解析或持久化配置。

## Blockers

- None.

## Verification

- `TerminalWindowNavigationTests`：7/7 通过。
- 完整 Swift package 测试：1668 tests / 237 suites 通过。
- macOS `CtrlxServer` Debug 构建通过，产物 `codesign --verify --deep --strict` 通过。
- `git diff --check` 通过。
- 全量测试曾触发一次既有 `SidecarSupervisorTests.crashLoopDisables` 并发时序抖动；该用例
  独立连续运行 3 次均通过，随后完整测试通过，且与本阶段修改文件无依赖关系。
