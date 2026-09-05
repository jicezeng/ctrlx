# Stage 24 Code Review Report

## Summary

- **Scope**：Host Viewer 生命周期、terminal stream 所有权、发送代际、bootstrap 诊断与 iOS 首帧恢复。
- **Objective**：阻止离线 Viewer 持续消耗 Host 编码/加密/传输资源，并消除旧 Task 跨重连重放与 iOS 无限 Connecting。
- **Assessment**：✅ Approved。

## Findings

### Critical / High

- 无。

### Medium

- 不能只清空发送 chain head：旧 Task 可能在 E2EE 或 WebSocket 悬点后恢复并看到新 socket。已改为单调
  generation，每个悬点后在发送或执行命令前重新校验。
- Viewer presence 与 Host→Relay socket 是两个不同生命周期。Viewer 离线只推进输出代际并定向释放
  ownership，不断开仍健康的 Host Relay socket；旧 socket 的迟到错误以 task identity 拦截。
- WebSocket send 失败不能由 receive loop 日后偶然发现。已在 send catch 中立即清理当前 socket，并复用单一
  现有重连流程。

### Low

- bootstrap 追踪使用 1 秒固定阈值，仅慢路径记录一条聚合 warning；不增加配置项或逐帧日志。

## Verification

- Stage 24 聚焦测试：32 tests passed。
- 完整 Swift Package：1647 tests in 233 suites passed。
- macOS `CtrlxServer` Release 构建通过，iOS `Ctrlx` generic-device Debug 构建通过。
- `git diff --check` 通过，编译无新增 Sendable、actor isolation 或数据竞争诊断。

## Recommendation

- 可以合入 `develop/v2.8.0`。真机验收时重点观察慢 bootstrap warning 的 `captureMs` 与
  `oldestQueueWaitMs`；这两项可直接区分远端 tmux capture 慢与 Host→Relay 发送堵塞。
