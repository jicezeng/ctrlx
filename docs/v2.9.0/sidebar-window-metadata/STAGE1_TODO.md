# Stage 1 TODO：Sidebar 活跃 Window 元数据

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 8/8 tasks
- **Dependencies**: `develop/v2.9.0` @ `8c7120f` ✅

## Tasks

- [x] 记录现状、字段语义、目标与非目标。
- [x] 新增可配置 `Tmux Window Name` 字段，不修改已有默认布局。
- [x] 本地 Sidebar 展示统一读取 active window/active pane。
- [x] 远端 Sidebar 展示统一读取 active window/active pane。
- [x] 本地与远端排序统一读取相同 active window/active pane 元数据。
- [x] 增加多 window 与字段解析聚焦测试。
- [x] 运行聚焦测试、macOS Debug 构建与格式检查。
- [x] 完成代码审查并记录验收结果。

## Decisions

- Sidebar 维持 session 级粒度。
- `Terminal Title` 明确表示 OSC 0/2 title；`Tmux Window Name` 表示 tmux `window_name`。
- 不聚合所有 window 名称，避免重复顶部 tabs 并扩大 Sidebar 行高。
- 不迁移用户设置，新字段默认关闭。

## Blockers

- None。

## Verification

- `SessionSortDataForLocalSessionTests` 与 `SidebarAppearanceSettingsTests`：12/12 通过。
- macOS `CtrlxServer` Debug 构建通过（arm64，使用本机开发签名）。
- `git diff --check` 通过。
- 构建环境未安装 SwiftLint；Xcode 构建脚本仅报告该已知 warning，不影响构建。
