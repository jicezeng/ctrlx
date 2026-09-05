# Stage 16 TODO：远程终端首屏原子揭示

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 7/7 tasks
- **Dependencies**: Stage 14 ✅

## Tasks

- [x] 为 `PipePaneReader` 增加有序 flush 完成屏障。
- [x] 在 `TerminalStreamService` 排空 bootstrap batch 后再完成 start command。
- [x] 将 terminal stream 路由限制到实际 pane 订阅者。
- [x] 让 Mac viewer 合并 bootstrap 字节、锁定 Host 尺寸并在单次 feed 后揭示。
- [x] 增加顺序、多 Viewer、重连和持续输出聚焦测试。
- [x] 完成完整测试和 macOS Release 构建。
- [x] 完成相同远程场景的双 Mac 真机验收。

## Decisions

- 保持只有当前可见 pane 维持 Viewer 端实时流，不缓存所有 window 的终端 View。
- 保留约三屏 scrollback，不以牺牲复制和历史浏览换取首屏速度。
- 不增加网络协议消息，使用现有 start command success 作为 bootstrap ready。
- ready 由 FIFO 屏障产生，不使用静默检测或任意毫秒等待。
- 隐藏视图不能替代工作合并：bootstrap 期间不逐块 feed，按字节顺序缓存后一次 feed。
- Remote SwiftTerm 行列以 Host pane 为唯一真相，不接受 Viewer 布局反向改写。

## Blockers

- None.

## Verification

- 首版聚焦测试：29 tests / 7 suites passed；完整 Swift package：1601 tests /
  222 suites passed。
- 首轮异机验收失败：历史回刷仍可见，整体性能一般。待完成 bootstrap 单次 feed 与
  Remote 尺寸锁定后，重新执行相同远程 pane 的打开、切换、重连及持续高输出测试。
- 聚焦回归：18 tests / 5 suites 通过，覆盖 bootstrap 合并与顺序、stream ownership、
  固定节拍批处理，以及 Viewer 布局变化下的 Host 尺寸锁定。
- 完整测试：1605 tests / 224 suites 通过。
- macOS Release：`CtrlxServer` arm64 构建通过；产物为 `Gallager.app` 2.7 (40)，
  主程序与 `GallagerCLI` 均为 arm64，CLI `ping` 返回 `pong`。
- 签名与映像：Apple Development 深度签名、DMG CRC 及只读挂载校验均通过；
  `Gallager-2.7-zengjice.dmg` SHA-256 为
  `1bdd6997df3719347effe5bb62bc50632c7f85ab39704031d40ee379071f39cb`。
- 双 Mac 真机验收通过：远程 pane 打开、切换时不再显示历史内容回刷，性能符合预期。
