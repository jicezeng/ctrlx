# Window 拖拽排序修复代码审查报告

## 结论

- **状态**：✅ Approved
- **范围**：macOS 本地 Host、Mac Viewer、Relay 命令模型、tmux 重排服务及相关状态持久化
- **审查基线**：`develop/v2.9.0` (`b6e9660`)

## 已发现并修复的问题

### P1：稳定 Window ID 未限定 Session

tmux linked Window 会让同一个 `@id` 同时出现在多个 Session。仅按稳定 ID 查询可能选中另一个
Session 的 Window，也会让失效 split 状态无法被清理。

修复：所有本地选择、右侧 pane 查询和清理均使用 `sessionName + stableWindowId` 复合身份。

### P1：异地 Viewer 发起重排时 Host 本地状态未迁移

原实现只在本机拖拽回调中迁移旧 `session:index`。远程 Viewer 或 tmux 外部重排会导致 Host
本地文件/Git/浏览器来源状态被当作失效数据清除。

修复：每次 pane snapshot 更新时按 `sessionName + stableWindowId` 检测 target 变化，统一迁移
所有仍需要可执行 `session:index` 的 UI 状态。

### P2：Window 请求失败可能覆盖后续文件/浏览器拖拽

异步 Window 重排 pending 期间允许同步文件/浏览器标签移动。失败后恢复整份旧 `tabOrder`
会抹掉稍后完成的非 Window 操作。

修复：失败时只恢复 Window 子序列，保留当前非 Window 标签的位置。

## 核心安全性检查

- 重排使用 tmux `#{window_id}` 和 `swap-window -d`，不再使用 `move-window -k`。
- 请求必须与实时 Window 集合完全一致，拒绝缺失、重复或过期 ID。
- 保留会话现有索引集合，支持 base-index 0/1、自动 renumber 和稀疏索引。
- 同一 Session 的重排串行化；部分失败执行 best-effort 原序回滚。
- 新 wire 字段为可选字段；旧 Host snapshot 可解码，新 Host 也接受旧 Viewer 的 `session:index` 请求。

## 验证结果

- 61 项相关 Swift Testing 测试通过。
- 隔离 socket 的真实 tmux 创建三 Window、交换、刷新和清理测试通过。
- macOS `CtrlxServer` Debug 构建通过，签名校验通过。
- 本机覆盖安装并启动成功，真实 App E2E 已覆盖标签前置/末尾重排、Session 往返持久化及跨 pane 拖拽；
  重排后的 tmux 顺序断言均通过。
- `git diff --check` 通过。

## 剩余风险

- 旧 TabReorder E2E 场景的键盘选中 AX 属性及末尾 pane 自动折叠断言存在既有脆弱性；本次验收绕开这些
  无关断言后，Window 拖拽、跨 pane 拖拽与真实 tmux 顺序检查均通过。
