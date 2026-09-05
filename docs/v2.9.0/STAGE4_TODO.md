# Stage 4 TODO：macOS 本地终端输入延迟

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 9/9 tasks
- **Dependencies**: v2.8.0 Stage 18、26、31 ✅

## Tasks

- [x] 采样并定位 MainActor、Observation、tmux control 与 terminal feed 热点。
- [x] 抑制无变化的 tmux/pane 状态发布，并为发布语义增加聚焦测试。
- [x] 将 Viewer session-state 构造改为不扰动本地 UI 的纯快照路径。
- [x] 增加本地按键到回显/feed 的低开销端到端指标。
- [x] 为待处理本地输入增加公平的 terminal feed 调度。
- [x] 降低 URL 装饰、无限动画和重复扫描造成的主线程放大。
- [x] 完成聚焦测试和完整 macOS Debug App 构建。
- [x] 完成代码审查并更新 Stage 文档。
- [x] 完成本机签名 Release 覆盖安装，并按用户明确指令合入 `develop/v2.9.0`。

## Decisions

- 不改变 tmux 输入语义，不实现 speculative local echo。
- 保留单一有序按键 FIFO 与同一 runloop 内的 Meta 合并。
- 优先删除无效状态写入；不以缓存或新 ViewModel 掩盖 Observation fan-out。
- Viewer 快照允许显式读取 tmux，但不得顺带写入本地 UI model。
- 指标为进程内聚合；最多每 10 秒记录一次 debug 摘要，不逐键同步写日志。

## Baseline

- Agent TUI 可见时 Gallager 约 80%–105% CPU；普通 zsh 多数为 12%–26%。
- 3352 个主线程样本中，`NSRunLoop.flushObservers` 2089、
  `GraphHost.flushTransactions` 1496、`AG::Subgraph::update` 1364。
- 现有持久 tmux control-mode 200 次提交约 0.01 秒；该结果不包含 MainActor 排队和回显。
- 5 秒 pane validation、10 秒 discovery/reconciliation 和 Viewer snapshot 都会触发刷新。

## Blockers

- None。使用主仓库只读 SwiftPM 缓存完成离线解析，不依赖不稳定的 GitHub 补拉。

## Verification

- `swift test` 聚焦 5 个套件：41 tests passed，覆盖 Observation 发布语义、Viewer 纯快照、
  输入指标乱序/上限/取消、动态 feed 批大小、输入顺序和并发 agent 扫描复用。
- `xcodebuild -scheme CtrlxServer`：完整 macOS Debug 与签名 Release App 构建通过。
- SwiftFormat：本 Stage 新增/修改的小型文件通过；大型既有文件仅保留仓库原有格式告警，
  未对无关代码做机械重排。
- `git diff --check`：通过。
- Release `f42f066e6852`（build stamp `20260811-145950`）已覆盖安装到
  `/Applications/Gallager.app`；`wait-ready` 与 `ping` 分别返回 `ready`、`pong`，安装前后
  tmux pane 清单一致。
- 未补做受控的同场景前后 profiling；用户在签名 Release 覆盖安装后明确要求合入，本文保留
  该证据边界，不伪造运行时数据。
