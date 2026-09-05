# Stage 11 TODO：iOS Agent 输入模式

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 8/8 tasks
- **Dependencies**: Stage 9 ✅，Stage 10 ✅

## Tasks

- [x] 增加默认关闭且可持久化的 Agent 快捷输入设置。
- [x] 提取并测试普通快捷输入与阻塞表单的展示策略。
- [x] 默认进入 Agent pane 时保持只读，不自动弹出 terminal 键盘。
- [x] 保证用户手动切换键盘后不被状态刷新覆盖。
- [x] 阻塞表单到达时退出 terminal 键盘模式并保持表单可见。
- [x] 将 Agent pane 的键盘按钮移出 Commands 菜单。
- [x] 运行聚焦测试和受影响的 Swift package 测试。
- [x] 完成 iOS device 构建、真机安装与验收。

## Decisions

- 设置只控制非阻塞的 prompt/reply composer。permission、question 和 plan approval
  是完成 Agent 工作流所必需的交互，不能被偏好设置隐藏。
- terminal 键盘只由用户操作导航栏按钮启用；进入 pane 和实时 Agent 状态更新都不是
  自动弹出键盘的信号。
- 不增加新的 host/relay 配置或协议字段，偏好完全属于 iOS viewer。

## Blockers

- None.

## Verification

- 手动键盘方案：`CtrlxFeatureTests` 44 tests / 5 suites passed。
- iOS device 无签名构建：Passed。
- 使用本机 Apple Development 证书签名、校验并安装到 ZengJice iPhone：Passed。
- 默认不弹键盘、设置切换和直接键盘按钮真机交互：Passed。
