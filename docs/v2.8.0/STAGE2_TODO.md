# Stage 2 TODO

## Stage Status

- **Status**: 🟡 In Progress
- **Progress**: 6/8 tasks
- **Dependencies**: Stage 1 ✅

## Tasks

- [x] 让 iOS terminal stream 生命周期跟随 host 连接状态。
- [x] 重连时安全替换旧订阅并刷新完整 initial state。
- [x] 增加一次自动重试和持续失败后的手动 Retry。
- [x] 增加 stream recovery 状态决策的聚焦测试。
- [x] 让 Mac remote terminal stream 跟随 host 连接状态恢复。
- [x] Mac start 瞬时失败自动重试，持续失败提供手动 Retry。
- [ ] 完成 package 测试、iOS/macOS 构建和两端断线恢复验收。

## Decisions

- 不修改 relay 协议；复用现有 `StopTerminalStream` / `StartTerminalStream`。
- 首次订阅不发送 stop。只有当前 view 已经请求过 stream 时才使用 stop/start，
  避免误减同一 pane 上其他 viewer 的订阅计数。
- 不引入无限重试循环。WebSocket 自身负责持续重连；stream start 在连接稳定时只
  自动重试一次，之后保留明确错误和人工 Retry。
- Mac 与 iOS 共用 `TerminalStreamRecoveryPolicy`，不复制订阅计数判断。

## Validation

- `swift test --filter TerminalStream`：5 tests 通过。
- iOS Simulator `Ctrlx` Debug 构建通过。
- iPhone Debug 真机构建、签名、安装和启动通过。
- macOS `CtrlxServer` Debug 构建和本地签名通过。
- 待在 iPhone 和 Mac viewer 的真实 terminal 页面制造 relay / 网络短断，验收
  页面内自动恢复与输入顺序。
