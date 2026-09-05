# CtrlX 3.0.0 Stage 3 TODO：技术身份与本地数据隔离

## Stage Status

- **Status**：✅ Implementation Completed
- **Progress**：6/6 tasks
- **Dependencies**：Stage 2 ✅

## Tasks

- [x] 替换 macOS、iOS、通知扩展 Bundle ID、App Group、Keychain access group 与后台任务 ID。
- [x] 将用户状态、插件、缓存、临时文件和 socket 命名空间迁移到 CtrlX；明确不自动迁移旧数据。
- [x] 将 CLI 命令、shell completion、环境变量和 tmux user option 切换到 `ctrlx` 命名空间。
- [x] 替换通知 action/category、E2EE salt、日志 subsystem 和其他跨进程技术标识。
- [x] 默认 Relay 保持未配置，新增技术身份边界检查，禁止连接 Gallager 生产基础设施。
- [x] 更新相关单元/E2E fixtures，运行 Swift 测试、Xcode 构建和共存配置检查。

## Migration policy

CtrlX 3.0.0 使用全新的技术身份和本地数据目录，不自动读取或迁移 Gallager 的
UserDefaults、Keychain、App Group、`~/.gallager`、`~/.ctrlx`、CLI socket 或
tmux user options。用户需要重新配置 Relay 并重新配对设备。这样可以保证两个发行版
同时安装、同时运行时不共享密钥和运行状态。

## Acceptance

- [ ] CtrlX 与 Gallager 可同时安装，Bundle、数据、Keychain 和 socket 不冲突（配置审计通过；双应用真机验收留在 Stage 6）。
- [x] 新安装不会默认连接任何未由 CtrlX 维护者配置的公网 Relay。
- [x] 生产运行路径不存在 `GALLAGER_*`、`.gallager`、`.ctrlx` 或 `@gallager-*`。
- [x] 内部 Swift 模块/target 名允许暂时保留 `Ctrlx*`，不得泄漏为用户技术身份。
