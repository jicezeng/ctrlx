# CtrlX 3.0.0：Viewer 远程 Host 顺序

## 问题

macOS 与 iOS Viewer 当前按 `pairedHosts` 的配对写入顺序展示远程 Host。已有 session 顺序
可以调整，但 Host section 本身不能拖拽，用户无法把高频机器固定在列表前面。

## 设计

1. 继续以 Viewer 本地持久化的 `pairedHosts` 数组作为唯一 Host 顺序来源，不增加第二份顺序配置。
2. 新配对追加到末尾；已有配对更新时原位替换，不得被移动到末尾。
3. 拖动 Host 到目标 Host 时，向上拖放到目标之前，向下拖放到目标之后，覆盖首尾位置。
4. macOS sidebar 的远程 Host header 提供拖拽手柄；iOS 在 Manage Hosts 的 `Edit` 模式下使用系统 List 重排。
5. iOS Sessions 页的 `Edit` 只负责 session 行重排；Host 与 session 的排序入口明确分离。
6. 顺序变化只影响当前 Viewer，不修改 Relay 协议、远端 tmux 或其他 Viewer。

## 实施范围

- 在 `CtrlxCommon` 增加小型纯函数，统一 Host ID 的拖放移动语义并覆盖边界测试。
- 在 macOS `AppSettings` 与 iOS `IOSSettings` 中原子更新并持久化 `pairedHosts`。
- macOS Host header 使用拖放载荷校验；iOS Manage Hosts 使用系统 `onMove` 坐标。
- 验证 sidebar、iOS Sessions、Manage Hosts、菜单栏与快捷键入口都读取同一顺序。

## 非目标

- 不跨 Viewer、Relay 或 iCloud 同步顺序。
- 不改变远端 Host 的 tmux session/window 顺序。
- 不允许 Host 与 session 混合或跨层级拖放。
- 不新增单独的排序设置页或排序模式。

## 验收标准

- macOS 与 iOS 均可把任意 Host 移到首位、中间或末位。
- iOS Host 拖拽与现有 session 拖拽互不冲突。
- App 重启、Host 断线重连、配对信息更新后顺序保持。
- 新 Host 稳定追加；删除 Host 不影响其余顺序。
- 共享算法测试、设置持久化测试及 macOS/iOS 构建通过。

## Stage 9：macOS Sidebar 拖放修复

### 问题

Stage 8 把 `draggable/dropDestination` 直接挂在 macOS `List` 的 `Section` header 上。手柄虽然
可见，但 Transferable 拖放没有在真实 App 中可靠形成内部移动事务，因此 Host 顺序不变。

### 修复设计

1. 保留 `pairedHosts` 作为唯一顺序来源，不修改数据模型、Relay 协议或 iOS 实现。
2. 将远程 Host 标题从 `List` 的 Section header 移到 Section 的第一个普通行；保留标题样式和
   无障碍 header 语义，但彻底绕开 Section header 的事件拦截。
3. 手柄使用高优先级的进程内 `DragGesture`；普通文本以及 session/window 拖放自然无法进入
   Host 排序链路。
4. `MainView` 只保存 Host 标题行的实时屏幕区域和当前目标；拖拽结束时按落点解析目标并调用
   既有 `moveHostPairing`，随后清理短生命周期拖拽状态。
5. 保留既有无障碍 Move Up/Move Down 操作与持久化路径，不新增第二套排序状态。
6. 手柄使用不小于 32×28pt 的命中区域；拖动源立即显示 accent 反馈，目标区域按可见标题的
   最近垂直距离解析并允许有限容差，避免必须精确落在标题像素范围内。

### 验收标准

- 从任意 Host 手柄拖到另一 Host header 时，列表立即按预期重排。
- 向上、向下、首位和末位移动均正确，重启后顺序保持。
- 普通文本以及 session/window 拖放不会改变 Host 顺序。
- Host session 点击、新建按钮、session 排序和 iOS Manage Hosts 排序不回归。
- 拖动开始和目标命中均有明确视觉反馈；在标题上下合理容差内松手仍能完成移动。
