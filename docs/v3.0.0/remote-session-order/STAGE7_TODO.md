# Viewer 远程 Session 顺序 TODO

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 6/6 tasks
- **Dependencies**: CtrlX 3.0.0 distribution ✅

## Tasks

- [x] 明确 Viewer 本地顺序的数据归属和协议边界
- [x] 实现共享排序/移动算法及单元测试
- [x] 实现 macOS 持久化、拖拽和所有 Viewer 入口一致性
- [x] 实现 iOS 持久化与系统编辑模式重排
- [x] 验证 rename、unpair、新增 session 和重连行为
- [x] 完成双端构建、代码审查和验收记录

## Blockers

- 当前无阻塞项。

## Verification

- `RemoteSessionOrder` 与设置持久化测试：8/8 通过。
- macOS `CtrlxServer` App target 构建通过。
- iOS `Ctrlx` generic-device App target 构建通过。
- Stage 7 review 未发现 P1/P2/P3 问题。
- 真实 macOS/iOS 拖拽交互保留为安装后的人工验收项，不阻塞源码集成。
