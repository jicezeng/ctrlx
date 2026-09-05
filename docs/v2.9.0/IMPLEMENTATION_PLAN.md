# Gallager 2.9.0 实施计划：终端交互体验

## 状态

- **状态**：🟡 Stage 4 已完成并合入，Stage 1–3 待实施
- **进度**：1/4 stages 已合入
- **开发分支**：`develop/v2.9.0`
- **前置依赖**：v2.8.0 Stage 21、22、31 ✅

## 1. 目标

在不增加 Relay 协议、不改变 Host tmux 输入语义的前提下，为 iOS 终端增加紧凑、可排序、
可显示/隐藏的快捷按钮栏。

同时修复 macOS 本地 tmux 镜像在高频终端输出下的输入延迟：无变化的 tmux 元数据不得触发
SwiftUI 全树更新，Viewer 快照不得反向扰动 Host UI，输入调度必须优先于可延后的终端装饰工作。

首轮覆盖高频终端按键，随后复用现有本地复制、系统粘贴和键盘控制，最后增加明确标识、
不会自动执行命令的可信文本宏。

完成后用户可以：

- 在终端底部快速发送 Esc、Tab、Ctrl-C 和方向键。
- 在 Settings 中调整按钮顺序、显示状态并恢复默认布局。
- 从快捷栏触发现有 Copy、Paste 和键盘显隐行为。
- 创建只插入文本、不自动追加 Enter 的本机可信宏。
- 在单 pane、多 pane、本地网络抖动和 window 切换后始终操作当前活跃 pane。

## 2. 当前基线

### 2.1 已有能力

- `TerminalKeyboardBar` 只负责键盘显隐，已经完成约 28pt 的紧凑高度和 Home Indicator
  空间回收。
- `TerminalKeyboardControlPosition` 支持 `Top Right` 与 `Bottom Bar`，属于已经真机验收的
  用户习惯。
- `TmuxKey` 已覆盖 Esc、Tab、Ctrl、方向键、Home、End、PageUp 和 PageDown，无需增加
  wire type。
- `LiveTerminalView.StreamCoordinator` 当前持有 `KeystrokeDebouncer`；普通键盘输入和 raw
  input 已经通过同一 FIFO 有序发送。
- `KeystrokeDebouncer` 使用固定 10ms 合批窗口和单一 send task，保证 typed key 与 raw
  input 的 WebSocket 写入顺序。
- `TerminalTextSnapshot`、`TerminalTextCopyView` 和顶部 Copy 按钮已经提供本地终端文本复制。
- `ClipboardClient` 已封装 iOS `UIPasteboard`，测试不需要直接访问系统剪贴板。
- SwiftTerm iOS `TerminalView.paste` 已根据当前 terminal mode 生成 bracketed-paste 起止序列。

### 2.2 当前缺口

- 底部栏只能显示一个宽键盘按钮，不能发送终端控制键。
- 快捷动作没有稳定 ID、布局模型、持久化配置和设置页面。
- 多 pane 的底栏由 `WindowLayoutView` 管理，真实输入 FIFO 位于各个 `LiveTerminalView` 内，
  父视图不能安全地向当前 pane 插入动作。
- 如果快捷按钮直接调用 `ViewerRelayClient.sendCommand`，会绕过当前 FIFO，使“键盘输入后立即
  点 Esc/Paste”的先后顺序不确定。

## 3. 非目标

本版本不实现：

- 新 Relay 消息、Host 特殊命令或第二套终端输入协议。
- CoTerm 的 Ctrl/Alt/Cmd/Shift 粘滞 modifier 状态机。
- Claude、Codex 等带危险参数的 Agent 启动器。
- 自动执行 Shell 命令、多步骤宏、条件宏、延时宏或脚本 DSL。
- 宏配置跨设备同步、Relay 存储或 Host 下发。
- 图片粘贴、文件上传或剪贴板后台监听。
- 将所有 Agent 操作直接暴露成快捷按钮。
- 改变 iOS terminal resize、scrollback、复制页面或 terminal stream 协议。
- 修改 macOS 快捷键、Mac terminal toolbar 或 Relay 部署；Stage 4 仅优化既有本地输入、
  状态发布和终端绘制链路，不增加任何 Mac UI 或 Relay 协议。

Agent 动作必须等待统一 Action Catalog 落地后复用同一动作实现；本版本不能在移动端快捷栏
内创建第二份 Approve、Yolo、Reply 或 Cancel 业务逻辑。Ctrl-C 只作为标准终端按键处理。

## 4. 设计原则

### 4.1 单一输入链路

所有会到达 tmux 的快捷动作必须进入当前 pane 的现有 FIFO：

```text
系统键盘 ─────────────┐
                      │
快捷键 / 文本宏 ──────┼─> TerminalPaneInputEndpoint
                      │        -> KeystrokeDebouncer
SwiftTerm Paste ──────┘        -> SendKeystroke / SendRawInput
                               -> E2EE Relay -> Host -> tmux
```

Copy 和键盘显隐是 Viewer 本地 UI 动作，不发送 Relay 命令。Paste 必须先进入 SwiftTerm 原生
paste 路径，再回到同一个 endpoint；不能把剪贴板按行拆成多次 `SendKeystroke`。

### 4.2 配置与执行分离

- 持久化层只保存稳定 item ID、顺序、启用状态和可信宏定义。
- Catalog 将稳定 ID 映射为标题、SF Symbol、可用条件和动作类型。
- Executor 只执行已经解析的动作，不读取或修改设置。
- View 只负责布局、点击和无障碍展示，不包含 Relay 或 tmux 业务逻辑。

### 4.3 保持可恢复输入

键盘控制是结构性控件，不允许配置损坏或全部隐藏后让用户失去输入入口：

- `Keyboard Control = Top Right` 时继续显示现有顶部按钮。
- `Keyboard Control = Bottom Bar` 时固定显示在快捷栏末尾。
- 键盘控制不进入可隐藏集合，也不作为可信宏。
- 快捷栏配置为空且键盘位于 Top Right 时，不占用底部安全区。

这是对“所有按钮都可隐藏”的唯一有意例外。

### 4.4 不复制 CoTerm 的复杂度

- 不使用全局 singleton；继续通过根部唯一 `IOSSettings` 和环境注入更新 UI。
- 不复制 CoTerm v1/v2/v3 多代配置迁移。Gallager 从一个明确的 v1 envelope 开始。
- 不在快捷栏固定放置 Customize 按钮；设置入口位于现有 Settings → Terminal。
- 不为每类按键创建新 Swift Package。

## 5. 用户体验

### 5.1 默认布局

Stage 1 新安装默认启用并按以下顺序显示：

```text
Esc  Tab  ^C  ←  ↑  ↓  →
```

Stage 2 增加：

```text
Paste  Copy
```

- Paste 对 Stage 2 之后的新安装默认启用。
- Copy 默认关闭，因为现有顶部 Copy 按钮继续保留；用户可以自行加入底栏。
- 已自定义过 Stage 1 的用户升级到 Stage 2 时，新按钮追加到配置末尾并保持关闭，不能改写
  用户已有顺序。
- 键盘位置选择 Bottom Bar 时，键盘按钮固定在所有滚动快捷按钮之后。

### 5.2 快捷栏样式

- 继续使用 `.safeAreaInset(edge: .bottom)`，不改成 UIKit `inputAccessoryView`。
- 延续 Stage 21 的 `.mini` 控件、紧凑高度、`.bar` 背景、顶部分隔线和 Home Indicator 回收。
- 快捷按钮使用横向 `ScrollView` 与单行布局；高频按钮位于默认顺序前部。
- 文本按钮保持短标签；图标必须加入共享 `Symbols`，禁止直接使用 SF Symbol 字符串。
- 点击除 Keyboard 外的动作不得主动 become/resign first responder，也不得改变键盘显隐状态。
- Host 断开、stream 未就绪或没有活跃 pane 时，终端输入类按钮禁用。
- Copy 只在本地 terminal buffer 可用时执行；空内容沿用现有明确提示。
- Paste 只在用户点击后读取剪贴板，不能在 body/render 阶段探测 `UIPasteboard`。

### 5.3 设置页面

在 Settings → Terminal 增加 `Terminal Shortcuts` NavigationLink，进入独立页面：

- 显示全部内置快捷动作和可信宏。
- 每行提供显示开关。
- Edit 模式拖动排序。
- 宏支持新增、编辑和删除。
- 提供 `Reset to Defaults`，只恢复内置按钮布局；不隐式删除用户宏。
- 页面 footer 说明快捷按钮操作当前活跃 pane，宏只保存在本机。

原有 `Keyboard Control` segmented picker 保留，不合并进快捷栏设置页面。

## 6. 数据模型

### 6.1 稳定标识

使用一个统一 ID 空间：

```swift
enum TerminalShortcutItemID: Hashable, Codable, Sendable {
    case builtIn(TerminalShortcutBuiltInID)
    case trustedMacro(UUID)
}
```

内置 ID 使用稳定字符串，不使用显示文本、数组下标或 enum 隐式整数 raw value。初始内置值：

- `escape`
- `tab`
- `controlC`
- `arrowLeft`
- `arrowUp`
- `arrowDown`
- `arrowRight`
- `paste`
- `copy`

Keyboard 不属于该 ID 集合，由现有 `TerminalKeyboardControlPosition` 决定固定位置。

### 6.2 持久化 envelope

`IOSSettings.Keys` 增加单一 `terminalShortcutConfiguration` Data 字段：

```swift
struct TerminalShortcutConfiguration: Codable, Equatable, Sendable {
    let schemaVersion: Int
    var order: [TerminalShortcutItemID]
    var enabled: [TerminalShortcutItemID]
    var trustedMacros: [TrustedTerminalTextMacro]
}
```

约束：

- `schemaVersion` 首版固定为 `1`。
- `order` 是完整、去重的已知 item 序列；隐藏项仍保留位置。
- `enabled` 使用数组而不是直接持久化 `Set`，保证编码稳定、diff 和测试可读。
- 初始化和每次修改均通过纯 `TerminalShortcutLayoutReducer` 规范化。
- 未保存配置使用对应 App 版本的默认布局。
- 解码失败回退默认布局，不崩溃、不清除其他 iOS 设置。
- 未知或重复 ID 被丢弃。
- Catalog 中新增而已有配置缺失的 ID 追加到末尾并默认关闭。
- 指向不存在宏的 ID 被删除；未进入 order 的有效宏追加到末尾并保持关闭。

`IOSSettings` 仍是唯一 live settings 实例。设置页每次操作都生成新的规范化 value 并整体
写回，避免嵌套数组原地修改绕过 `didSet`。

### 6.3 Catalog 与动作

内置 Catalog 从 ID 派生，不持久化：

```text
ID          Label  Action
escape      Esc    keys([.escape])
tab         Tab    keys([.tab])
controlC    ^C     keys([.ctrl("c")])
arrowLeft   ←      keys([.left])
arrowUp     ↑      keys([.up])
arrowDown   ↓      keys([.down])
arrowRight  →      keys([.right])
paste       Paste  localPaste
copy        Copy   localCopy
macro       用户名 trustedText(value)
```

持久化数据不得携带任意 `TmuxKey`、raw escape sequence、Relay command name 或可执行闭包。

## 7. 输入与 pane 生命周期

### 7.1 TerminalPaneInputEndpoint

从 `LiveTerminalView.StreamCoordinator` 抽出 pane 输入职责，新增 `@MainActor` reference type：

```text
TerminalPaneInputEndpoint
├── paneId / registration token
├── KeystrokeDebouncer
├── enqueue(keys:)
├── enqueueRawInput(data:)
├── requestPaste()
├── requestCopy()
├── requestKeyboardToggle()
└── cancelPendingInput()
```

- SwiftTerm `onInput`、`onRawInput` 和快捷栏的 terminal-bound 动作共享同一个 endpoint。
- endpoint 继续使用现有 `KeystrokeDebouncer`，不能新增第二个 queue 或 fire-and-forget send。
- `StreamCoordinator` 在断线、stream replacement、结束和 disappear 时调用 endpoint 的取消接口。
- endpoint 不拥有 terminal stream 状态，不负责重连、渲染或 session/window 选择。

### 7.2 单 pane

- `LiveTerminalView` 创建并持有稳定 endpoint。
- `TerminalShortcutBar` 直接执行该 endpoint 的动作。
- Copy、Paste、键盘显隐调用现有本地实现。

### 7.3 多 pane

- `WindowLayoutView` 持有轻量 `TerminalPaneEndpointRegistry`。
- 每个 `LiveTerminalView` 出现时按 `paneId` 注册 endpoint，消失时使用 registration token 注销。
- token 必须匹配才能删除注册，防止旧 SwiftUI view 的晚到 `onDisappear` 删除新 endpoint。
- 父视图只渲染一条全宽快捷栏，并以 `activePaneId` 解析 endpoint。
- pane/window 切换后，动作必须重新解析当前 endpoint，不能缓存上一次选中的闭包。
- active pane 已删除或尚未注册时按钮禁用，不能回退到任意第一个 pane。

## 8. Copy、Paste 与键盘语义

### 8.1 Paste

- 复用 `ClipboardClient.getString`；只在明确点击 Paste 时读取。
- endpoint 调用当前 `InteractiveTerminalView` 的 paste 入口，由 SwiftTerm 根据
  `bracketedPasteMode` 添加 `ESC[200~` / `ESC[201~`。
- SwiftTerm 生成的 bytes 继续通过 `TmuxKey.from(bytes:)` 和同一 endpoint FIFO 发送。
- 多行剪贴板必须保持一次 paste 操作，不能按换行拆成多次 Enter。
- 空剪贴板或非文本剪贴板显示轻量提示，不发送空命令。
- 图片粘贴不在本版本范围内。

### 8.2 Copy

- 复用 `TerminalState.makeTextSnapshot`、`TerminalTextCopyView` 和现有空内容提示。
- Copy 不增加 Host capture 或 Relay 请求。
- 复制页面继续禁止系统键盘弹出。
- Copy 完成和 sheet 关闭沿用现有输入恢复规则，不新增键盘显隐副作用。

### 8.3 Keyboard

- Top Right 和 Bottom Bar 两种位置语义保持不变。
- Bottom Bar 版本使用紧凑的固定尾部按钮，不进入横向配置列表。
- 除 Keyboard 按钮外，任何快捷动作都不得修改 `isInteractive`、`keyboardVisible` 或
  `isKeyboardActive`。

## 9. 可信文本宏

### 9.1 数据约束

```swift
struct TrustedTerminalTextMacro: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var text: String
}
```

- title 去除首尾空白后长度为 1...12 个字符。
- text 长度为 1...1024 个 Unicode scalar。
- 禁止 NUL、ESC、CR、LF 和其他 C0/C1 控制字符。
- 不自动追加 Enter，不提供“立即执行”开关。
- 点击宏只调用 `.text(value)`，通过当前 endpoint FIFO 插入文本。
- 宏按钮使用统一的可信文本宏视觉标识；不能伪装成 Esc、Paste 或系统动作。
- 设置编辑页必须显示完整文本预览和“不会自动执行”说明。

### 9.2 安全边界

- 宏保存在普通 iOS preferences，不是 Keychain；页面明确提示不得存储密码、Token 或私钥。
- 宏不进入配对数据、不通过 E2EE Relay 同步、不写入 Host。
- 不允许宏携带 raw bytes、ANSI escape、延时或结构化 Relay command。
- 未来如需“发送并回车”，必须单独设计显式危险动作和确认，不在本版本预留隐藏字段。

## 10. Stage 拆分

### Stage 1：内置快捷键、布局与统一输入 endpoint

#### 范围

1. 创建 v2.9.0 文档、Stage 1 TODO 和隔离 worktree。
2. 实现稳定 item ID、v1 configuration、纯 layout reducer 和 `IOSSettings` 持久化。
3. 实现 Settings 编辑页：显示/隐藏、排序和恢复默认。
4. 抽出 `TerminalPaneInputEndpoint`，将系统键盘和 raw input 迁入同一 endpoint。
5. 实现单 pane 与多 pane endpoint 注册/选择。
6. 将 `TerminalKeyboardBar` 扩展/替换为横向 `TerminalShortcutBar`，支持 Esc、Tab、Ctrl-C
   和四个方向键。
7. 保留现有 Keyboard Control 位置和紧凑安全区行为。

#### 验收标准

- 新安装默认显示 `Esc Tab ^C ← ↑ ↓ →`。
- 排序和隐藏在 App 重启后保持，Reset 恢复默认。
- 配置损坏、未知 ID 和重复 ID 都被规范化，不崩溃。
- 连续输入 `abc` 后立即点 Esc/Tab，Host 观察到严格的 `a b c Esc/Tab` 顺序。
- 单 pane 和多 pane 只操作当前 active pane；window 切换后不发送到旧 pane。
- 断线、stream replacement 和 view disappear 会取消待发送输入。
- 快捷按钮不改变键盘显示状态。
- iOS 聚焦测试、iPhoneOS arm64 构建和 iPhone 真机交互通过。
- macOS 受影响共享 target 构建通过；Relay 和协议 diff 为空。

### Stage 2：Copy 与 Paste

#### 范围

1. Catalog 增加 Copy/Paste，旧配置规范化时追加并保持关闭。
2. Paste 复用 `ClipboardClient` 和 SwiftTerm bracketed-paste 路径。
3. Copy 复用现有 terminal snapshot sheet。
4. 验证键盘显示/隐藏、copy sheet、单 pane 和多 pane 的焦点语义。
5. 顶部 Copy 按钮继续保留；本阶段不增加 Copy 位置设置。

#### 验收标准

- 单行和多行文本均作为一个 paste 操作进入当前 pane。
- bracketed paste 起止序列与内容保持 FIFO 顺序，不拆成 Agent 多次提交。
- 空/非文本剪贴板不发送输入，并显示明确反馈。
- Copy 与现有顶部按钮得到相同 snapshot 和空内容行为。
- Copy/Paste 不意外显示、关闭或抢占 terminal 键盘。
- 不读取剪贴板以决定 SwiftUI body，未点击时不触发 iOS paste privacy 提示。
- 聚焦测试、iPhoneOS build 和 iPhone 真机通过。

### Stage 3：可信文本宏

#### 范围

1. 实现 `TrustedTerminalTextMacro`、校验器和 configuration normalization。
2. 增加宏新增、编辑、删除和预览 UI。
3. 将宏加入同一排序/显示列表和快捷栏。
4. 宏动作以 `.text` 进入当前 pane endpoint，不追加 Enter。
5. 增加安全提示、无障碍标识和损坏/孤儿宏恢复测试。

#### 验收标准

- 合法宏可创建、排序、隐藏、编辑、删除并跨 App 重启保持。
- 空标题、超长文本、控制字符和换行被拒绝并显示原因。
- 点击宏只插入文本；Shell 和 Agent TUI 都不会因隐式 Enter 自动执行。
- 宏不能伪装成内置按钮，VoiceOver 能读出“Text Macro”和用户标题。
- 删除宏会清理 order/enabled 中的引用，不影响其他按钮。
- 宏不出现在 Relay frame、Host 配置或配对数据中。
- 聚焦测试、iPhoneOS build 和 iPhone 真机通过。

### Stage 4：macOS 本地终端输入延迟

#### 范围

1. 为 `TmuxService` 和 `MirrorWindowManager` 增加无变化抑制；后台刷新不得发布无意义的
   `isRefreshing`、错误、attached session 或 pane state 变更。
2. 将 Host→Viewer session-state 构造改成纯快照路径；远端读取不能为更新网络快照而修改本地
   SwiftUI 可观察状态。
3. 增加按键进入、合批、tmux control 写入/确认、pipe echo 和 SwiftTerm feed 的低开销指标。
4. 保持按键严格有序和 Meta 合并，在终端输出积压时优先执行已排队输入；feed 使用有界时间片，
   不能用 speculative local echo 掩盖真实延迟。
5. 将 URL 装饰限定到内容/viewport 变更，降低无限动画刷新频率，并合并重复的 pane/agent 扫描。

#### 验收标准

- 相同 pane snapshot 的后台刷新不发布任何 `panes` 或 `paneStates` Observation 变更。
- Viewer session-state 请求不修改 Host 的 `TmuxService` / `MirrorWindowManager` 可观察状态。
- 本地输入指标可以串联同一批按键的 enqueue、flush、tmux ack、pipe echo 和 terminal feed。
- 普通 zsh 与持续输出的 Agent TUI 中，按键顺序、Option/Meta、raw mouse input 均无回归。
- 持续输出时输入不会被 32KB feed 批次或 URL 全屏扫描长期饿死。
- 5 秒/10 秒后台扫描不再制造无变化的 SwiftUI 刷新尖峰。
- macOS 聚焦测试、完整 Debug/Release-like 构建和本机运行时采样通过。

## 11. 预计文件范围

### 新增

- `CtrlxPackage/Sources/CtrlxFeature/Models/TerminalShortcutItemID.swift`
- `CtrlxPackage/Sources/CtrlxFeature/Models/TerminalShortcutConfiguration.swift`
- `CtrlxPackage/Sources/CtrlxFeature/Models/TrustedTerminalTextMacro.swift`
- `CtrlxPackage/Sources/CtrlxFeature/Services/TerminalPaneInputEndpoint.swift`
- `CtrlxPackage/Sources/CtrlxFeature/Views/TerminalShortcutBar.swift`
- `CtrlxPackage/Sources/CtrlxFeature/Views/TerminalShortcutsSettingsView.swift`
- `CtrlxPackage/Sources/CtrlxFeature/Views/TrustedTerminalTextMacroEditor.swift`
- 对应 `CtrlxFeatureTests` 聚焦测试。

### 修改

- `CtrlxPackage/Sources/CtrlxFeature/Models/IOSSettings.swift`
- `CtrlxPackage/Sources/CtrlxFeature/ContentView.swift`
- `CtrlxPackage/Sources/CtrlxFeature/Views/LiveTerminalView.swift`
- `CtrlxPackage/Sources/CtrlxFeature/Views/WindowLayoutView.swift`
- `CtrlxPackage/Sources/CtrlxFeature/Views/InteractiveTerminalView.swift`
- `CtrlxPackage/Sources/CtrlxFeature/Views/TerminalKeyboardBar.swift`
- `CtrlxPackage/Sources/CtrlxCommon/UI/Symbols.swift`（仅新增实际使用的 symbol）。
- `CtrlxPackage/Sources/CtrlxServerFeature/Services/TmuxService.swift`
- `CtrlxPackage/Sources/CtrlxServerFeature/Managers/MirrorWindowManager.swift`
- `CtrlxPackage/Sources/CtrlxServerFeature/Views/TerminalContainerView.swift`
- `CtrlxPackage/Sources/CtrlxServerFeature/Views/InteractiveTerminalView.swift`
- `CtrlxPackage/Sources/CtrlxCommon/Services/TerminalFeedCoalescer.swift`
- `CtrlxPackage/Sources/CtrlxCommon/Services/TerminalTransportMetrics.swift`

### Stage 1–3 原则上不修改

- `CtrlxNetworking` command/wire model。
- `CtrlxExternalServer` 和 Relay Docker 部署。
- macOS Host `TmuxService`、`PaneStreamManager` 和 tmux 配置。
- Push notification、Agent plugin 和 Action Catalog 尚未实现的部分。

如果实施中发现必须修改上述边界，应暂停当前 Stage，在 TODO 中记录 blocker 并重新审查设计，
不能以“快捷按钮”为由扩大协议。

## 12. 测试矩阵

### 12.1 纯状态测试

- Fresh defaults。
- Reorder、hide/show、reset。
- Duplicate、unknown、missing 和 corrupt data normalization。
- Catalog 新增 item 后，已有配置顺序不变且新 item 默认关闭。
- 删除宏后的 orphan ID 清理。
- title/text 长度、控制字符和换行校验。

### 12.2 输入顺序测试

- typed keys → shortcut key。
- shortcut key → typed keys。
- typed keys → raw input → shortcut key。
- typed keys → multiline paste → shortcut key。
- pending input 在断线、stream replacement 和 endpoint 注销时取消。
- 同一 pane 只有一个 `KeystrokeDebouncer` 和一个 send loop。

### 12.3 pane 路由测试

- 单 pane endpoint。
- 多 pane active selection。
- active pane 切换。
- window 切换和旧 endpoint 晚到注销。
- pane 删除后没有 fallback mis-send。
- Host disconnected / stream connecting / stream ended 时禁用。

### 12.4 UI 与真机测试

- iPhone 竖屏、横屏及有 Home Indicator 设备。
- 键盘显示和隐藏时快捷栏高度与安全区。
- 横向滚动、按钮点击、VoiceOver label 和 Dynamic Type 可辨识性。
- Copy sheet 不弹键盘，关闭后沿用现有输入恢复规则。
- Paste permission 只在明确点击时出现。
- 单 pane、多 pane、不同 window 和远程 Host。
- 终端高吞吐期间点击按键仍及时发送且 UI 不重连。

### 12.5 macOS 本地输入性能

- 相同/变化 pane snapshot 的 Observation 发布次数。
- Viewer snapshot 生成前后本地可观察状态一致性。
- typed key、Meta、raw input 的 FIFO 与取消语义。
- 终端 feed 有/无待处理输入时的公平调度。
- URL 装饰只在内容、scroll 或 geometry 实际变化时更新。
- 普通 zsh、Agent idle、Agent 高频输出三个现场的 CPU、主线程样本和 input-to-echo 延迟。

不要求为本功能重新引入 Simulator 人工验收；聚焦逻辑测试、无签名 iPhoneOS 构建和已连接
iPhone 真机是最终证据。

## 13. 性能与兼容性

- 快捷栏状态完全在 iOS 本地，不增加轮询、WebSocket frame 或 terminal stream 字节。
- 按钮使用已有 10ms input batching，不为每次点击创建独立长生命周期 Task。
- endpoint registry 只保留当前页面可见 pane，注销后释放，不按历史 session 无界增长。
- 横向按钮使用单行惰性布局；设置变更才重建 resolved item 列表。
- v2.8.x Mac Host 和 Relay 与 v2.9.0 iOS 保持兼容，因为 wire model 不变。
- v2.9.0 iOS 连接旧 Host 时，按键语义仍由现有 `SendKeystroke` 执行。
- 配置只属于 iOS Viewer，降级 App 无法理解时必须忽略该独立 key，不影响配对和其他设置。
- Stage 4 不改变 wire model、tmux session、pane FIFO 或 E2EE；新旧 Viewer 与 Relay 保持兼容。
- Stage 4 指标只做内存聚合和阈值日志，不为每个字节或按键同步写日志。

## 14. 回滚边界

每个 Stage 必须可独立回滚：

- Stage 1 回滚后恢复原 Keyboard-only bar；新增 preference key 可安全留存但不读取。
- Stage 2 回滚只移除 Copy/Paste Catalog 项，不改变 typed input endpoint。
- Stage 3 回滚只停止解析和展示宏；宏配置留在独立 envelope，不发送到任何外部系统。
- Stage 4 可整体回滚到旧状态发布/调度路径；不迁移 tmux、配置或 Relay 数据。
- 任一 Stage 不得要求 Relay 数据迁移、Host 降级或 tmux session 重建。

## 15. 完成定义

- 四个 Stage 分别有 `STAGE{N}_TODO.md`、聚焦测试、构建和对应设备证据。
- 所有 terminal-bound 动作都通过当前 pane 的唯一 FIFO。
- 没有新增 Relay 协议或 Host 特例。
- 设置损坏不会导致崩溃或失去键盘入口。
- 单 pane、多 pane、window 切换和断线恢复不会误发输入。
- Paste 不拆分多行，Copy 和其他快捷动作不制造键盘副作用。
- 文本宏本机保存、明确标识、不包含控制字符且不会自动执行。
- v2.8.0 已有 terminal stream、复制、键盘位置和紧凑底栏行为无回归。
- Mac 本地 terminal 在 Agent 高频输出期间仍保持有序、可测且及时的按键回显。
