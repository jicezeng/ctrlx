# Viewer 远程 Host 顺序 TODO

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 6/6 tasks
- **Dependencies**: Stage 7 远程 session 顺序 ✅

## Tasks

- [x] 明确 Host 顺序的数据归属、拖放语义和协议边界
- [x] 实现共享 Host 移动算法及边界测试
- [x] 实现 macOS 持久化与 sidebar Host 拖拽
- [x] 实现 iOS 持久化与 Edit 模式 Host 拖拽
- [x] 验证配对更新、删除、重启和双端构建
- [x] 完成 Stage 8 真机交互复验与验收记录

## Blockers

- 当前无阻塞项。

## Verification

- `RemoteHostOrder` 与设置持久化测试：4/4 通过。
- macOS `CtrlxServer` App target 构建通过。
- iOS `Ctrlx` generic-device App target 构建通过。
- `git diff --check` 通过。
- 首版 iOS Section header 自定义拖放真机验收失败，已改为 Manage Hosts 原生 List 重排。
- 修复版 iOS Manage Hosts 原生拖拽已通过真机验收。
- macOS 实现完成专项代码审查、签名 Release 构建与本机覆盖安装；用户已授权合入。
