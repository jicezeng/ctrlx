# Stage 13 TODO：macOS Window 标签双击重命名

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 6/6 tasks
- **Dependencies**: Stage 1 ✅

## Tasks

- [x] 确认本地与远程 window 标签共用的现有重命名路径。
- [x] 让重命名输入框可由标签双击和右键菜单共同触发。
- [x] 保持单击、断线禁用、close/split/drag 行为不变。
- [x] 更新 Window Rename E2E 场景覆盖 host 与 viewer 双击。
- [x] 运行受影响测试与 macOS 构建验证。
- [x] 完成本机真实双击交互验收。

## Decisions

- 继续使用 `WindowRenamingModifier` 和 `TextEntryPresentation`，不复制 alert/sheet 状态。
- 双击只绑定 terminal window 标签的主按钮，不覆盖 close、split 或其他标签。
- modifier 在标签主按钮上使用 simultaneous double-tap gesture；单击选择仍由原 Button 处理。
- 不增加 relay 或 tmux 命令；保存仍走现有 `onRenameWindow`。

## Blockers

- None.

## Verification

- `swift build --target CtrlxE2ELib`：通过，包含本地/远程标签和双击 E2E 驱动编译。
- `xcodebuild` `CtrlxServer` Debug arm64：通过（Apple Development 签名）。
- `codesign --verify --deep --strict /Applications/Gallager.app`：通过。
- `/Applications/Gallager.app` 覆盖安装并正常启动。
- 本机真实交互：双击 window 标签弹出预填名称的重命名输入框，验证通过。
