# CtrlX 3.0.0 独立发行版实施计划

## 状态

- **状态**：🟡 源码实施完成，外部分发验收待资源就绪
- **进度**：5/6 stages completed；Stage 6 为 6/7
- **开发分支**：`feature/ctrlx-distribution`
- **基础提交**：`919c7772928531d4d0bb266bdf275691d361901e`
- **基础日期**：2026-08-14
- **上游项目**：[Gallager](https://github.com/gpambrozio/Gallager)

## 1. 目标

在保留完整 Git 历史、GNU AGPL-3.0 和第三方归属的前提下，将当前定制版 Gallager 建成
可与 Gallager 同机共存的独立发行版 **CtrlX**。本版本必须隔离用户可见品牌、Apple 技术
身份、本地数据、CLI、socket、Relay、更新通道和遥测命名，同时保留现有 tmux、Mac、iOS、
E2EE 与 Relay 行为。

内部 `Ctrlx*` 模块、源码目录和测试 target 首轮不重命名。它们不是用户身份，机械重命名
会制造大量无价值冲突并显著增加 upstream 同步风险。

## 2. 固定身份

| 项目 | CtrlX 3.0.0 |
| --- | --- |
| 产品名 | `CtrlX` |
| slug / CLI | `ctrlx` |
| macOS Bundle ID | `com.jicezeng.ctrlx.macos` |
| iOS Bundle ID | `com.jicezeng.ctrlx` |
| Notification Extension | `com.jicezeng.ctrlx.notification-service` |
| App Group | `group.com.jicezeng.ctrlx` |
| Keychain Group | `$(AppIdentifierPrefix)com.jicezeng.ctrlx.shared` |
| 本地状态目录 | `~/.ctrlx` |
| API socket | `$TMPDIR/ctrlx.sock` |
| 环境变量前缀 | `CTRLX_` |
| tmux 用户选项前缀 | `@ctrlx-` |
| 指标前缀 | `ctrlx_` |
| 目标源码地址 | `https://github.com/jicezeng/CtrlX` |

源码仓库、生产域名、Developer ID、APNs、Sparkle EdDSA 和 Notary 凭据属于外部资源。代码
只提供单一配置入口和安全的未配置状态；资源实际存在前不得继续连接 Gallager 的生产服务，
也不得提交占位密钥。

## 3. 设计原则

1. **共存优先**：CtrlX 不读取或覆盖 Gallager 的 bundle、UserDefaults、Keychain、App Group、
   `~/.gallager`、CLI、socket 或 tmux metadata。
2. **协议显式**：E2EE salt、通知 action ID 和 Relay identity 属于协议边界，必须成组修改并测试。
3. **配置唯一**：发行版身份集中定义；脚本只读取配置文件，不接受重复的命令行品牌覆盖。
4. **安全失效**：新 Relay、更新源或签名未配置时明确禁用对应功能，绝不回退 Gallager 服务。
5. **可同步**：不重命名无用户价值的内部模块；品牌边界用测试阻止 upstream 合并带回旧身份。
6. **对应源码**：构建产物嵌入 CtrlX version、build、commit 和不可变源码 URL。

## 4. 分阶段实施

### Stage 1：仓库与合规基线

- 新增 `NOTICE.md`、`MODIFICATIONS.md`。
- 更新 README 的来源、非官方关系、许可证和对应源码说明。
- 建立本实施计划、Stage TODO 和 Issues 文档。
- 记录基础提交、日期、维护者和待创建的新仓库地址。

验收：来源和修改关系清楚；LICENSE 与第三方声明未被削弱；无生产凭据。

### Stage 2：用户可见品牌与视觉隔离

- Mac/iOS 产品名、菜单、About、通知、错误、帮助和安装提示改为 CtrlX。
- 删除 “Why Gallager” 品牌故事，替换为客观来源与 AGPL 声明。
- 生成全新 CtrlX 图标和 Logo，不复用 Gallager 图形资产。
- 更新 README 与客户端源码链接。

验收：生产 UI 不再把 CtrlX 表述为 Gallager；About 保留清楚的来源归属。

### Stage 3：技术身份和本地状态隔离

- 更换 Bundle ID、App Group、Keychain group/service、BGTask ID 和 UTI。
- `~/.gallager`、`gallager.sock`、`GALLAGER_*`、CLI 与 tmux metadata 改用 CtrlX 命名。
- 更换通知 action/category ID、E2EE protocol salt、日志 subsystem 和 UserDefaults suite。
- 不迁移 Gallager 数据；首次启动按全新 CtrlX 安装处理。

验收：Gallager 与 CtrlX 可同时安装运行，两个应用的数据、socket 和 tmux metadata 不冲突。

### Stage 4：构建、签名与更新边界

- 版本提升为 3.0.0，产物命名为 `CtrlX-3.0.0.dmg` / `CtrlX-3.0.0.ipa`。
- 构建信息键和脚本变量改用 `CTRLX_*`。
- 新 Sparkle URL 和公钥未配置前禁用更新，禁止沿用 Gallager appcast/key。
- 生成 SHA-256、源码映射和发布清单。

验收：主 worktree 可构建签名的 CtrlX.app；产物不引用 Gallager 更新基础设施。

### Stage 5：CtrlX Relay 发行身份

- Relay service、Docker、配置、指标、APNs topic 和默认客户端 URL 使用 CtrlX 身份。
- 增加 `/version` 与 `/source`，返回 version、commit、protocol、source 和 license。
- `.env.example` 覆盖开发/测试/生产配置，真实凭据保持外置。
- 完成配对、重连、首帧、大量输出和 E2EE 回归。

验收：Relay 只转发密文；运行版本能免费获得准确对应源码；不连接 Gallager 生产服务。

### Stage 6：边界审计、构建与共存验收

- 新增品牌边界脚本，扫描生产源码、plist、entitlements 和发布脚本。
- 运行 Mac/iOS/Relay 单元测试、关键 E2E 和安装/升级/共存检查。
- 更新 `MODIFICATIONS.md`、发行说明和未完成的外部资源清单。

验收：测试与构建通过；旧品牌仅允许出现在来源声明、许可证、历史文档或内部模块名白名单中。

## 5. 非目标

- 不重写 Git 历史或压缩成新的首次提交。
- 不在本阶段加入支付、账号、订阅或闭源控制面。
- 不发布 TestFlight/App Store；Apple 条款与 AGPL 的法律结论需单独完成。
- 不自动迁移 Gallager 配对、Keychain、插件、配置或 tmux metadata。
- 不为了品牌重命名 `Ctrlx*` 内部 Swift module、target 和源码目录。
- 不伪造尚未创建的 GitHub repository、DNS、TLS、APNs 或 Sparkle 凭据。

## 6. 依赖与阻塞项

- 创建 `jicezeng/CtrlX` 后，才能将 `origin` 切换到新仓库并推送完整历史与 tags。
- 确定生产 Relay、更新和下载域名后，才能启用默认公网地址。
- 取得 CtrlX 专用 Developer ID、APNs、Provisioning Profile、Sparkle EdDSA 和 Notary 配置后，
  才能完成正式分发验收。
- iOS App Store/TestFlight 发布需要单独的 AGPL/Apple 条款法律结论。

这些外部项不阻止本地源码、身份隔离、测试和开发签名构建。

## 7. 当前验收结论

截至 2026-08-14，Stage 1–5 的源码实施已经完成；Stage 6 的静态检查、Swift 全量测试、
macOS/iOS 无签名构建、网站构建、Sidecar 测试与 Linux Relay 容器运行检查已经通过。
尚未完成的发布门禁仅包括：CtrlX 专用签名/Notary/APNs/Sparkle 资源、公开生产域名与
Gallager/CtrlX 双应用真机共存验收。未完成这些门禁前，本分支不应创建正式 release。
