# Window 拖拽排序修复 TODO

## Stage Status

- **Status**：✅ Completed
- **Progress**：7/7 tasks
- **Dependencies**：`develop/v2.9.0` ✅

## Tasks

- [x] 复现并确认落点、可变 ID、base-index 和并发问题
- [x] 贯通 tmux 稳定 Window ID
- [x] 使用无损 swap 算法重排 tmux Window
- [x] 统一本地/远程拖拽语义并实现 pending/回滚
- [x] 迁移异地触发的旧 target 状态并兼容 linked Window
- [x] 增加模型、算法和隔离 tmux 回归测试
- [x] 完成代码审查、macOS 构建和签名校验
- [x] 覆盖安装后完成本地/远程鼠标拖拽验收

## Blockers

- 当前无阻塞。

## Verification

- 相关测试：61 项通过，覆盖稳定身份、协议兼容、落点、回滚、linked Window、布局映射与真实 tmux 重排。
- 真实 tmux 测试使用独立 socket，确认重排后 Window/Panes 无丢失且索引槽位保持不变。
- macOS `CtrlxServer` Debug 工程构建通过。
- 构建产物 `codesign --verify --deep --strict` 通过。
- 已覆盖安装到 `/Applications/Gallager.app`，安装产物与验收构建的可执行文件 SHA-256 一致。
- 真实 App E2E 已验证指定标签落点、末尾落点、Session 往返持久化、跨 pane Terminal 和 Files 拖拽；
  每次 Window 重排后的真实 tmux 顺序断言均通过，现有用户 tmux Session 未受影响。
- 完整旧场景末尾仍受既有 pane 自动折叠断言阻塞，该断言不在本次 Window 排序修改路径内。
- `git diff --check` 通过。
- SwiftFormat 全文件 lint 仍命中仓库既有格式债务；未做无关的大范围机械改写。
