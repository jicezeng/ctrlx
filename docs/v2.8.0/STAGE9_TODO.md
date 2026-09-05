# Stage 9 TODO：iOS Terminal 本地文本复制

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 7/7 tasks
- **Dependencies**: Stage 2 ✅，Stage 4 ✅

## Tasks

- [x] 记录现有 viewport、selection 与 resize 的技术边界。
- [x] 实现 SwiftTerm 本地 buffer 的静态文本快照。
- [x] 增加 iOS 原生跨屏文本选择界面。
- [x] 从 terminal 工具栏接入复制入口与空内容反馈。
- [x] 增加快照格式与状态流转聚焦测试。
- [x] 运行 iOS Simulator 构建与受影响测试。
- [x] 完成 iPhone 真机跨屏复制验收。

## Decisions

- iOS 不成为 tmux window 的尺寸所有者。现有 resize 命令最终执行
  `tmux resize-window`，会改变 Mac 和其他 viewer 共享的真实 window。
- 不做“只缩放本地 SwiftTerm”的伪 resize。全屏 TUI 的控制序列仍按 host 行列数
  生成，本地重排会使光标、滚动区和画面状态不一致。
- 第一阶段使用打开时生成的本地静态快照。它没有 relay 往返，也不会因实时输出
  改变正在操作的系统选区。
- 保留现有 terminal 内短文本选择；外层 viewport 驱动选区自动滚动属于后续增强，
  不为第一阶段扩大 SwiftTerm fork API。

## Blockers

- None.

## Verification

- `swift test --skip-update --filter TerminalTextSnapshotTests`：5/5 通过。
- `xcodebuild -scheme CtrlxFeature -destination 'generic/platform=iOS Simulator' ... build`：
  通过。
- 完整 `swift test --skip-update`：1569/1569 通过。
- `git diff --check`：通过。
- iPhone 真机覆盖安装并验证跨屏文本复制：通过。
