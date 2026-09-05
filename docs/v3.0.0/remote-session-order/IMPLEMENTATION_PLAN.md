# CtrlX 3.0.0：Viewer 远程 Session 顺序

## 问题

macOS 和 iOS 作为 Viewer 时，Remote Hosts 下的 session 始终按 Host 推送的
`sidebarSortMode` 排序。Viewer 无法按自己的工作优先级调整列表，且只在 View 内重排会被
下一次 Host 状态刷新立即覆盖。

## 设计

1. 每个 Viewer 按 Host `pairId` 持久化 session 名称顺序。
2. 未保存手动顺序时，完整保留 Host 的基础排序行为。
3. 已保存顺序中的 session 优先；新出现或未记录的 session 按 Host 基础排序追加。
4. 调整只影响 Viewer 展示，不修改远端 tmux，不新增 Relay 协议。
5. session rename 成功后迁移名称；解除 Host 配对时删除对应顺序。
6. macOS sidebar、菜单栏和会话切换快捷键使用同一顺序；iOS 使用系统编辑模式重排。

## 实施范围

- 在 `CtrlxCommon` 提供唯一的远程 session 顺序合并与移动算法。
- 在 macOS `AppSettings` 和 iOS `IOSSettings` 中分别持久化 Viewer 本地顺序。
- macOS Remote Host section 启用原生拖拽重排。
- iOS Sessions 页增加 `Edit` / `Done`，每个 Host section 内可拖拽重排。
- 补充纯算法、持久化、rename/unpair 和双端构建验证。

## 非目标

- 不调整 Remote Host 本身的顺序。
- 不调整 Host 机器上的 tmux session 顺序。
- 不跨 Viewer、Relay 或 iCloud 同步顺序。
- 不增加独立的“手动排序模式”或新的设置页面。

## 验收标准

- macOS 和 iOS 都能调整同一 Host 内的 session 顺序。
- 重连、状态刷新和 App 重启后顺序保持。
- 新 session 稳定追加；关闭或重命名 session 不破坏其余顺序。
- 不同 Host 的同名 session 互不影响。
- macOS 菜单栏和快捷键切换顺序与 sidebar 一致。
- 相关单元测试及 macOS/iOS 构建通过。
