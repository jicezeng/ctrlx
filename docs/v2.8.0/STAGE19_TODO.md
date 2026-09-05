# Stage 19 TODO：macOS 终端选择与链接激活隔离

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 6/6 tasks
- **Dependencies**: Stage 18 ✅

## Tasks

- [x] 记录误触根因、修复边界和验收标准。
- [x] 为 Gallager 鼠标手势增加单击/拖动/多击判定。
- [x] 阻止远端 file URL 回退到本机系统打开器。
- [x] 修复 SwiftTerm fork 的底层链接误触和状态复位。
- [x] 增加并通过聚焦回归测试。
- [x] 完成完整测试、macOS Release 构建和本机验收安装。

## Decisions

- 链接激活的唯一合法手势是 `clickCount == 1` 且本次手势未发生拖动。
- 选择与复制是同一手势的后续行为，不通过关闭自动复制规避误触。
- 远端 Host 的文件路径没有本机打开语义；`file://` 必须在 Viewer 边界被消费。
- Gallager 与 SwiftTerm 两层使用相同判定，防止任一事件路径绕过上层保护。

## Blockers

- 无。

## Verification

- Gallager 与 SwiftTerm 的手势状态测试各 3 项通过；远端 URL 策略测试覆盖
  http/https/ftp、file URL、无 scheme 路径和自定义 scheme。
- `Terminal File Link Opens In New Tab` E2E 场景已增加拖选、双击、三击不激活链接，
  单击仍打开链接的回归步骤；E2E target 在完整 package 构建中编译通过。
- 完整 Swift package：1621 tests / 227 suites passed。
- SwiftTerm fork 修订 `99f2287e17f640beafdbc2b935ef1aac97f0fa7c` 已推送并同时锁定在
  package manifest、package lockfile 与 Xcode workspace lockfile。
- macOS Release：`CtrlxServer` arm64 构建通过，产物为 `Gallager.app` 2.7 (40)；
  Apple Development 深度重签及 `codesign --verify --deep --strict` 通过。
- Release 候选版已覆盖安装到 `/Applications/Gallager.app`；`wait-ready` 返回 `ready`，
  `ping` 返回 `pong`，并能读取现有 `coding` session。
- 本机交互验收通过：拖选、双击和三击选择均不再误触链接或弹出“应用程序无法打开”，
  单击链接与自动复制继续按预期工作。
- 固定名称 `dist/Gallager-2.7-zengjice.dmg` 已更新；映像 CRC、只读挂载、Applications
  链接、包内 App 深度签名、2.7 (40) 版本、arm64 主程序/CLI，以及源产物可执行文件
  哈希一致性均校验通过。DMG SHA-256 为
  `e0eb63e326b32b7d01105e7f24e069fb1df139ba04e66b59e4e2bbce66946444`。
