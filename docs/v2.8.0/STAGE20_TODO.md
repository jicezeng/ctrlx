# Stage 20 TODO：终端传输背压与高吞吐恢复

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 8/8 tasks
- **Dependencies**: Stage 14 ✅, Stage 16 ✅, Stage 17 ✅

## Tasks

- [x] 记录传输指标、背压、重同步和 Relay 原始转发的实施边界。
- [x] 增加低开销传输指标及聚焦测试。
- [x] 修复 live dataChunk 切分和公平调度。
- [x] 实现高水位 snapshot resync。
- [x] 合并 Mac/iOS terminal feed 并记录耗时。
- [x] 实现 Relay 加密 frame 原始转发。
- [x] 修正本机 Relay 稳定源码目录。
- [x] 完成聚焦测试、完整测试和平台构建验证。

## Decisions

- 不在过载时任意丢弃 terminal bytes；高水位后的唯一降载方式是原子 snapshot resync。
- 不增加二进制协议或压缩；先消除现有 JSON/E2EE 路径中的重复 Relay 编解码。
- 不逐 frame 写日志；指标在内存中聚合并按低频窗口输出，避免观测本身成为瓶颈。
- SwiftTerm feed 保留 MainActor 隔离，只在 runloop 边界合并，不假定其 parser 可后台并发。
- 配置修复只涉及本机 `~/.config/gallager/server/.env.local`，不得提交密钥或机器域名。

## Blockers

- 无。

## Verification

- `swift test --quiet`：1639 tests / 232 suites 全部通过（45.638s）。
- 65,536-byte live output 聚焦测试确认拆为 8 个 8,192-byte `dataChunk`。
- macOS `CtrlxServer` Release（arm64、ad-hoc 签名）构建通过。
- iOS `Ctrlx` Debug generic-device 构建通过。
- Swift 6.3 Jammy/Linux Release Relay 构建通过；容器 `/health` 返回 `{"status":"ok"}`。
- Relay 原始 frame、非法密文、snapshot wire round-trip、队列高水位和 feed 合并测试通过。
- `~/.config/gallager/server/.env.local` 中 `GALLAGER_SOURCE_DIR` 已指向主仓库；文件权限保持 `600`。
- `git diff --check` 通过。
- 新 Relay 镜像已在本机重建，容器健康检查与内外网 `/health` 均通过。
- macOS Release 2.7 (40) 已深度签名并覆盖安装；CLI `wait-ready` 和 `ping`
  通过，现有 tmux session 保持可见。
- 自行签名的 iOS 2.7 (40) 已在物理真机原位升级并启动；新
  `resetState` 协议与持续大量输出场景验收通过。
- 固定名称 `dist/Gallager-2.7-zengjice.dmg` 已更新；映像 CRC、只读挂载、
  Applications 链接、包内 App 深度签名、2.7 (40) 版本、arm64 主程序
  与源产物哈希一致性均校验通过。DMG SHA-256 为
  `c9dcb208db07bf7084719d8902112c27632b2af15947673c739711dd63e4251e`。
