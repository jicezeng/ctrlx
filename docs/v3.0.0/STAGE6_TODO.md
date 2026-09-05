# CtrlX 3.0.0 Stage 6 TODO：边界审计与验收

## Stage Status

- **Status**：🟡 In Progress
- **Progress**：6/7 tasks
- **Dependencies**：Stages 1–5 implementation complete

## Tasks

- [x] 用户品牌边界检查覆盖 Mac/iOS/网站。
- [x] 技术身份边界检查覆盖客户端、Relay、插件、脚本与 E2E Runner。
- [x] Sidecar 插件 Python 测试通过。
- [x] plist、entitlements、shell、Swift parse、Docker Compose 与 Swift Package manifest 静态检查通过。
- [x] Swift 全量测试与 Xcode Mac/iOS 无签名构建通过。
- [x] Relay Linux 构建和 Relay 测试通过。
- [ ] 新旧应用同时安装、状态/Keychain/socket/tmux 隔离的真机验收完成。

## External blockers

- CtrlX GitHub 仓库尚未确认存在，不能切换 remote、推送或创建 release tag。
- CtrlX 域名、Apple signing/APNs、Sparkle EdDSA 和 Notary 配置未提供。
- TestFlight/App Store 需要单独的 AGPL/Apple 条款结论。

## Verification evidence

- Swift：1715 tests / 247 suites passed。
- Xcode：macOS `CtrlxServer` 与 iOS Simulator `Ctrlx` 无签名构建通过。
- Relay：Linux Docker release build 通过；容器 `/health`、`/ready`、`/version`、`/source` 实测通过。
- Sidecar：OpenCode、Pi、OMP 共 132 个 Python tests 通过。
- Web：Astro production build 通过。
