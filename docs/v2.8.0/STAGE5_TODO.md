# Stage 5 TODO：Agent Pane 进程校准

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 10/10 tasks
- **Dependencies**: Stage 4 🟡（基于最新 host stream 生命周期提交开发）

## Tasks

- [x] 确认 session 行采用任意 pane 聚合、window 标签采用本 window 聚合。
- [x] 确认误判根因是进程检测仅在 host 启动时执行一次。
- [x] 区分进程扫描推断状态与插件 hook 权威状态。
- [x] 增加 10 秒 agent 进程校准任务。
- [x] 清理由扫描推断且进程已退出的 agent 状态。
- [x] 防止 session end 后旧进程在退出窗口期复活图标。
- [x] 仅在状态变化时推送 viewer 状态并更新防休眠。
- [x] 增加所有权、撤销、升级和退出竞态聚焦测试。
- [x] 运行受影响的 Swift package 测试和 macOS 构建。
- [x] 本机 tmux 多 window 真机验收图标行为。

## Decisions

- 保留现有 UI 聚合规则，不在 SwiftUI View 内增加进程检测或第二套显示状态。
- 进程扫描是 hook 缺失时的修复机制，不得覆盖插件上报的工作、等待或完成状态。
- agent 校准使用独立 10 秒周期；现有 5 秒 pane/session 校验保持不变。
- 扫描结果没有变化时不触发 viewer 广播。
- `tmux` 或 `ps` 无法生成可靠快照时跳过本轮校准，不把扫描失败误判为 agent
  全部退出。

## Verification

- `swift test --filter AgentProcessReconciliationTests`：5 tests passed。
- `swift test --filter PluginRuntimeStatusWiringTests`：14 tests passed。
- `swift test`：1549 tests / 213 suites passed。
- `CtrlxServer` Debug macOS build：通过（ad-hoc signing；SwiftLint 未安装警告）。
- 本机真实 tmux session 中保留一个 agent window 和一个普通 window，
  再用临时 window 验证：`codex` 进程启动后下一个 10 秒校准周期出现
  agent 图标，进程退出后下一周期恢复普通终端图标；session 与 window
  聚合层级均保持正确。

## Blockers

- 无。
