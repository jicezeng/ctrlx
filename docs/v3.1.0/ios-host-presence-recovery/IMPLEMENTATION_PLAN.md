# CtrlX 3.1.0 Stage 8：iOS Host 在线状态恢复

## 问题

长连接重建后，Relay 中已被替换的旧 socket 仍可能送达一帧。当前消息入口会
无条件重新注册该 socket，使旧连接重新覆盖新连接；旧连接随后关闭时，Relay
便会错误地向 iOS 发送 `hostDisconnected`。

iOS 收到该事件后，Relay transport 仍可能保持连接。前台恢复当前只重连已经
断开的 transport，因此不会重新校准 Host presence，界面会一直显示 Host
offline，直到后续连接活动偶然触发新握手。

## 设计

1. WebSocket 只在升级流程中注册一次；消息入口不再改变连接所有权。
2. 每帧处理前确认发送它的 socket 仍是当前连接，旧 socket 的迟到帧直接丢弃。
3. iOS 请求立即重连时，如果 Relay 已连接但 Host 尚未通过握手确认在线，复用
   现有 `registerViewer` 消息进行一次幂等 presence 校准，不新增协议。
4. Relay 断开、Host 真离线和版本不兼容的既有语义保持不变。

## 验收标准

- 旧 Host socket 在替代连接建立后迟到发帧并关闭，不会覆盖或移除新连接，
  Viewer 不会收到错误的 `hostDisconnected`。
- iOS 的 Relay transport 已连接而 Host presence 为 false 时，前台恢复会重新
  注册并完成现有 E2EE/peerHello 握手。
- 正常在线连接不会重建 socket，也不会产生多余注册。
- Relay、Viewer liveness 定向测试和完整 Swift 测试通过。
