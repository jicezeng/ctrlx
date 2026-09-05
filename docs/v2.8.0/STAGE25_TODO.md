# Stage 25 TODO：macOS 零中断更新与 control client 收敛

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 7/7 tasks
- **Dependencies**: Stage 20 ✅, Stage 24 ✅

## Tasks

- [x] 审计 App 退出、tmux control client、安装脚本与 launchd 进程现场。
- [x] 增加 control client 确定性退出和进程身份竞态测试。
- [x] 实现 actor 所有权内的 stdin close、TERM、bounded wait 与精确 PID KILL。
- [x] 强化零参数安装脚本，保持 LaunchServices 启动和 tmux 非破坏边界。
- [x] 完成隔离 tmux socket 的 session/pane/agent 身份不变集成测试。
- [x] 完成完整测试、macOS Release 构建、签名和本机更新验收。
- [x] 合入 `develop/v2.8.0`，更新固定名称 DMG 与公网安装文件。

## Decisions

- tmux server/session/window/pane 及 pane 内 agent 不属于 App 子进程，任何退出与安装路径都
  不得终止它们；只处理当前 `TmuxControlClient` actor 持有的精确 `Process`。
- 不增加全局 `pkill tmux`、进程名扫尾、后台守护器或新配置项。进程终止以对象身份和有界
  等待解决，避免 PID/连接代际竞态。
- 退出期间 Viewer 可短暂断开；tmux 任务保持运行，新 App 通过既有发现与 capture 机制恢复。

## Blockers

- None.

## Verification

- control client process lifecycle 聚焦测试：1 test passed；两次 control PID 均在断开返回前退出，
  隔离 tmux socket 上的 pane 保持存在并可 capture。
- control client、pipe reader 与 App shutdown 聚焦测试：41 tests passed。
- 完整 Swift package：1648 tests / 234 suites passed。
- 隔离 tmux 身份验收通过：session `$0`、pane `%0`、pane PID `18971`、pane 子进程 PID
  `19049` 在 control client 退出前后完全一致。
- macOS `CtrlxServer` Release arm64 构建通过；Apple Development 深度签名及
  `codesign --verify --deep --strict` 通过，版本 2.7 (40)。
- 固定名称 `dist/Gallager-2.7-zengjice.dmg` CRC、只读挂载、Applications 链接、包内签名、
  metadata 和源产物哈希一致性通过；SHA-256 为
  `3afe6da3e8da6afb18daa66a7bafa571a8770193ab0b0c61cde2246decc5994e`。
- 公网脚本与 DMG 流式下载哈希均和部署文件一致，Relay `/health` 返回 `{"status":"ok"}`。
- 通过公网零参数脚本完成本机覆盖升级；更新前后三个 session/pane/pane PID 完全一致，
  运行中的 Codex PID `62130` 未变化，CLI readiness 与 ping 通过。
- 新 App 主进程 PPID 为 1，stdin/stdout/stderr 均为 `/dev/null`；安装后不存在 PPID 1 的
  遗留 control client，已安装主程序哈希与 Release/DMG 产物一致。
