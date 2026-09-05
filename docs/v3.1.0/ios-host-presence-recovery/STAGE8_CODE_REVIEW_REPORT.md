# CtrlX 3.1.0 Stage 8 Code Review Report

## Review Scope

- Relay WebSocket 路由所有权与替代连接关闭时序
- iOS 前台恢复时 Relay transport 与 Host presence 的校准
- 连接校验失败、消息处理和断开清理的 socket 身份边界

## Findings

- P1：无
- P2：无
- P3：无

## Resolved During Review

- 消息入口不再重复注册 socket；旧连接的迟到帧不能重新取得路由所有权。
- 每帧处理前检查当前 socket 身份；已被替换的连接直接丢弃，不转发数据。
- 断开与校验失败清理均使用 `unregisterIfCurrent`，旧异步任务不能删除更新连接。
- Relay 已连接但 Host presence 为 false 时，前台恢复只补发已有的
  `registerViewer`；不重建健康 WebSocket，不新增协议或状态机。
- Relay 与 Host 均在线时维持原有 no-op 行为。

## Verification

- 修复前新增的两个回归测试均稳定失败，分别复现旧 socket 抢回路由和
  已连接 transport 无法恢复 Host presence。
- Relay/Viewer liveness 定向测试：5 项通过。
- `CtrlxPackage` 完整测试：1759 项、255 个 suite 通过。
- iPhoneOS arm64 Debug 无签名构建：通过。
- `git diff --check`：通过。
- SwiftLint 未安装；Xcode 仅报告既有 SwiftLint 缺失提示。

## Residual Risk

- 现场的一天级网络切换时序无法在单元测试中按真实墙钟复现；测试通过连接替换、
  旧帧和旧连接关闭的确定性顺序覆盖同一状态转换。
- 修复需要更新 Relay 才能阻止错误离线事件源头；更新 iOS 后，即使仍连接旧 Relay，
  App 再次进入前台也可通过幂等注册恢复 presence。

## Decision

代码审查通过，没有剩余 P1、P2 或 P3 问题。实现只收紧既有 socket 所有权并复用
现有注册消息，符合 KISS/YAGNI，可进入真机与部署验收。
