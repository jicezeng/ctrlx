# Stage 7 TODO

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 5/5 tasks
- **Dependencies**: Stage 6 ✅

## Tasks

- [x] 对照 Coterm 源码确认终端与工作区表面色阶。
- [x] 建立共享工作区表面调色板，保留终端调色板不变。
- [x] 接入窗口、侧栏、标签栏、状态栏及中性选中样式。
- [x] 增加颜色映射回归测试并完成 Xcode 构建。
- [x] 安装本机版本并完成真机视觉验收。

## Decisions

- 不修改 Anysphere Dark 的终端背景、前景或 ANSI 16 色。
- 不为本地与远端分别维护颜色常量。
- 不修改 pane 焦点、键盘路由或 tmux 同步逻辑。

## Validation

- Xcode `CtrlxServer` Debug arm64 构建通过。
- SwiftPM 已编译新增测试及相关测试源码；整包测试在链接无关 E2E 可执行文件时
  因磁盘空间不足失败，当前 Xcode scheme 未包含该单元测试 target，未伪报为测试通过。
- 本机验证版已签名、安装并通过代码签名校验；真机视觉验收通过。
