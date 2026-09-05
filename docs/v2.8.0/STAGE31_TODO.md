# Stage 31 TODO：iOS Terminal Stream 租约与抗抖恢复

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 7/7 tasks
- **Dependencies**: Stage 30 ✅

## Tasks

- [x] 审计 `Terminal Stream Ended`、Viewer 重连和 Host stream ownership 的完整链路。
- [x] 为 Viewer Relay 生命周期补齐 connection generation、精确 socket 失效和发送失败重连。
- [x] 增加 terminal stream lease 与向后兼容的 Host ownership 语义。
- [x] 增加 iOS handler registration ownership 和有界稳定恢复策略。
- [x] 调整多 Host keepalive 抗抖并增加异常 stop reason 诊断。
- [x] 完成聚焦验证与 macOS/iOS 构建，并记录完整 Swift package 的外部依赖失败。
- [x] 完成代码审查、双端安装验收并合入 `develop/v2.8.0`。

## Decisions

- lease 是每次 Start 的客户端 UUID，不是引用计数。Host 只接受当前 lease 的 Stop。
- 协议字段保持 optional；旧 Viewer/Host 按原有无 lease 语义工作，避免静默破坏异地旧版本。
- recovery 使用短时间失败上限与稳定期复位，不使用无限重试或永久的一次性额度。
- keepalive 保留现有应用层 ping/pong，只把单次漏报改为连续两轮确认，不引入第二套网络栈。

## Blockers

- None.

## Known verification gap

- 完整 Swift package 测试的依赖解析被 GitHub 连接多次 `early EOF` 中断，未产生测试结果；
  目标级构建、测试源码 typecheck 和核心策略运行时断言均已完成。用户在知悉该缺口后要求
  合入收尾，后续依赖可用时应补跑全量测试。

## Verification

- `ConnectionGenerationTests`、`TerminalStreamHandlerRegistryTests`、
  `TerminalStreamRecoveryPolicyTests`、`TerminalStreamLeaseCommandTests` 和
  `TerminalStreamOwnershipTests` 测试源码以 Swift 6 typecheck 通过。
- 使用正式 `ConnectionGeneration`、`TerminalStreamRecoveryPolicy` 和
  `TerminalStreamOwnership` 源文件编译运行核心生命周期断言，exit 0。
- iOS `CtrlxFeature` Debug generic device build 通过。
- 完整 iOS `Ctrlx` Debug generic device build 通过；仅有既有 SwiftLint 未安装警告。
- macOS `CtrlxServerFeature` Debug arm64 build 通过。
- 完整 macOS App 已完成源码编译；禁用签名时停在既有 CLI copy/sign build phase，启用签名时
  本机缺少项目默认 Team `XG2WG7U93U` 的 Mac Development 证书，均非 Swift 编译错误。
- `git diff --check` 通过。
- 完整 Swift package 测试未产生结果：HTTP/2 与 HTTP/1.1 两次依赖拉取均因 GitHub
  `RPC failed` / `early EOF` 失败，已停止重复下载。
- macOS Release 使用 Apple Development 签名构建并覆盖安装；运行 revision 为
  `1fdf353f698f`，CLI `wait-ready` / `ping` 通过，安装前后 tmux session/window/pane/PID
  指纹一致。
- iOS Debug device App 使用本地 provisioning profile 分层签名，覆盖安装并启动到
  `ZengJice iPhone`；bundle ID 为 `com.zengjice.gallager.local`，运行 revision 为
  `1fdf353f698f`。
- 用户完成双端更新后要求合入主仓并收尾。
