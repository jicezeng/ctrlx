# Stage 12 TODO：Agent 工作进度兜底

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 4/4 tasks
- **Dependencies**: Stage 5 ✅

## Tasks

- [x] 确认进度状态的数据所有权和三端读取路径。
- [x] 实现真实 terminal progress 优先、working agent 兜底的共享派生规则。
- [x] 切换 macOS 本机、Mac viewer、iOS 与 accessibility 读取点。
- [x] 补充聚焦测试并完成受影响构建验证。

## Decisions

- 不解析 Codex `OSC 2` terminal title spinner；该标题可配置且不是稳定活动协议。
- 不新增 relay 字段；viewer 已经同时收到 terminal progress 和 agent state。
- 不存储 synthetic progress，避免制造第二份状态和覆盖真实 terminal progress。
- Codex fallback 依赖安装到 `CODEX_HOME` 的 Gallager 插件；仅进程检测不会产生
  `.working`，安装后已运行的 Codex 会话也必须重启。

## Blockers

- 无。

## Verification

- `PaneProgressTests`：5/5 通过。
- `TerminalNotificationParserTests`：38/38 通过。
- Swift Package 完整编译通过。
- `CtrlxServer` Debug macOS 构建通过（ad-hoc signing；SwiftLint 未安装警告）。
- `Ctrlx` Debug arm64 iOS Simulator 构建通过（SwiftLint 未安装警告）。
- 尚未完成真实 Codex hook 的端到端验证；当前聚焦测试使用构造的 `.working` 状态。
