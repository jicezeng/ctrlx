# Stage 18 TODO：macOS 本地终端输入延迟

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 6/6 tasks
- **Dependencies**: Stage 17 ✅

## Tasks

- [x] 固定本地输入场景并记录逐次 tmux 客户端调用基线。
- [x] 为持久连接命令编码、命中、回退和 FIFO 顺序增加聚焦测试。
- [x] 复用现有 control-mode 连接发送本地交互按键。
- [x] 保留且验证连接不存在、编码不支持或写入前断开时的进程回退。
- [x] 完成聚焦测试、完整测试和 macOS Release 构建。
- [x] 使用 Release 产物完成本机 local session 验收并记录结果。

## Decisions

- 第一阶段只消除本地交互输入的逐批次 tmux 子进程，不修改输出渲染链路。
- 不替换插件、remote host 或非交互命令使用的 `TmuxService` 进程路径。
- 持久路径必须安全编码 literal 文本，不接受未经编码的任意 control-mode 命令。
- 只有确定尚未写入 control client 时才允许回退；写入后的不确定失败不得重放。
- `KeystrokeCoalescer` 的普通按键快速路径是条件性第二阶段，没有测量证据不实施。

## Blockers

- 无。

## Verification

- `LocalKeystrokeInputTests`：12 tests passed；覆盖 literal/Unicode、命名键、
  Ctrl/Alt、无连接回退、重批次拒绝，以及隔离 tmux socket 的真实 control-mode
  输入执行。
- 相同隔离 tmux socket 上，200 次进程式发送约 1.00 秒；复用持久 control-mode 且逐次
  等待 `%end` 约 0.01 秒。该结果只衡量 tmux 命令提交，不代表端到端回显延迟。
- 完整 Swift package：1616 tests / 225 suites passed。
- macOS Release：`CtrlxServer` arm64 构建通过，产物为 `Gallager.app` 2.7 (40)；
  Apple Development 深度重签和 `codesign --verify --deep --strict` 通过。
- Release 候选版已覆盖安装到 `/Applications/Gallager.app`，`wait-ready` 返回 `ready`，
  `ping` 返回 `pong`，并能读取现有 `coding` session 和 windows。
- 本机 local session 与直接 `tmux attach` 对比验收通过；持续输入的响应较旧版明显
  改善，当前体验符合预期。第一阶段已达到目标，不实施缺少测量依据的第二阶段快速路径。
- 固定名称 `Gallager-2.7-zengjice.dmg` 已更新；映像 CRC、只读挂载、Applications
  链接、包内 App 深度签名、2.7 (40) 版本、arm64 主程序/CLI 及源产物可执行文件哈希
  均校验通过。DMG SHA-256 为
  `ae7d5718f3fe971db65c8006a40ffd979db2ca6a347b56f62a6f43bd94a64df9`。
