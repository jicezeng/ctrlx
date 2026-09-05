# Stage 1 TODO

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 6/6 tasks
- **Dependencies**: Gallager Relay ✅

## Tasks

- [x] 确认 TestFlight 2.7 首次配对会误用官方 Relay 的根因。
- [x] 提取可测试的 Relay URL 规范化/验证逻辑。
- [x] 在 `PairingView` 增加持久化 Server URL 输入。
- [x] 运行 `CtrlxFeatureTests` 和 iOS 编译。
- [x] 使用本机 Development Team 签名并安装到 iPhone。
- [x] 完成自托管配对和普通 tmux 双向输入验收。

## Decisions

- 不硬编码 `zengjice.com`，保持上游通用性。
- 不增加新配置模型，`IOSSettings.externalServerURL` 仍是唯一事实来源。
- 免费 Personal Team 不支持 APNs；本 Stage 只验收前台 Relay/终端链路。

## Verification

- `RelayServerURLTests`：5/5 通过。
- iOS `Ctrlx` scheme：Debug 真机构建与签名通过。
- 本地 bundle `com.zengjice.gallager.local` 已安装到真机。
- Mac 显示 `Connected - viewer online`，真机自托管配对和终端操作验收通过。
