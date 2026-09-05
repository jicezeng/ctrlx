# Stage 1 TODO

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 6/6 tasks
- **Dependencies**: None

## Tasks

- [x] 增加 session 名验证和 tmux `rename-session` 服务。
- [x] 增加 relay 命令并在 host 端刷新、推送状态。
- [x] 修复 pane stream/control client 在 session 改名后的旧名称引用。
- [x] 增加 macOS/iOS 菜单重命名及 macOS 双击输入交互。
- [x] 迁移本地与远程 viewer 的选择及 session-scoped UI 状态。
- [x] 完成单元测试、macOS/iOS 构建和交互验收。

## Decisions

- Description 保持独立元数据，不作为 session rename 的替代品。
- 不引入新的持久化 session UUID；本阶段在现有 tmux session-name 身份模型上做
  原子迁移，避免无必要的协议和存储重构。
- 双击仅用于 macOS；iOS 保持单击导航、长按菜单编辑，避免双击与
  `NavigationLink` 的首击导航冲突。

## Validation

- `swift test --package-path CtrlxPackage --disable-automatic-resolution --filter SessionRename`
  通过：11 tests / 2 suites。
- macOS `CtrlxServer` Debug 构建、签名和 `codesign --verify --deep --strict`
  通过。
- iOS Simulator `Ctrlx` Debug 构建通过。
- macOS 实际交互通过：右键菜单显示 `Rename Session`；双击会话行弹出预填当前
  名称的输入框；提交后旧 session 消失、新 session 保留原 pane ID。
- 名称冲突、非法名称、部分 window 移动和歧义 linked-session 映射均有回归测试。
- `git diff --check` 通过。
