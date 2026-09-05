# Stage 28 TODO：远程粘贴连字符参数完整性

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 7/7 tasks
- **Dependencies**: Stage 27 ✅

## Tasks

- [x] 复现 `sudo scutil --set HostName` 在 `--set` 前截断。
- [x] 定位 tmux literal 参数缺少选项终止符的根因。
- [x] 修复 Host 统一 literal 发送入口。
- [x] 增加进程参数与独立 tmux socket 回归测试。
- [x] 运行聚焦测试、完整测试和 macOS 构建。
- [x] 更新并安装本机 Mac App。
- [x] 真机验收，合入主仓库并清理 worktree。

## Root cause

iOS 粘贴文本经过 `TmuxKey` 解析后，空格会形成命名按键边界，因此
`sudo scutil --set HostName` 的 `--set` 成为新的 literal 批次。Host 进程路径当前生成：

```text
tmux send-keys -t <pane> -l --set
```

tmux 将 `--set` 继续解析为选项并返回 `command send-keys: invalid flag --`。前面的批次已
成功写入，最终 pane 看起来便只剩 `sudo scutil`。独立 socket 已稳定复现；加入 `--`
终止选项解析后，同一 tmux 版本可完整写入 `--set`。

## Blockers

- None.

## Verification

- `LocalKeystrokeInputTests`：14/14 通过。
- 完整 Swift package：1661/1661 通过（236 suites）。
- macOS `CtrlxServer` Debug 构建及严格签名校验通过。
- 本机 Mac App 已覆盖为 Stage 28 验证版；替换前后 tmux session 列表一致。
- `git diff --check` 通过。
- 独立 tmux socket 集成测试确认 `sudo scutil --set HostName -n` 完整进入 pane。
- iOS 真机粘贴 `sudo scutil --set HostName` 完整显示，验收通过。
