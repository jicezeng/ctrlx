# Gallager 2.8.0 实施计划

## 状态

- **状态**：✅ 已完成
- **进度**：31/31 stages

## Stage 1：Tmux Session 重命名

### 目标

为本地和远程 tmux session 提供真正的重命名能力。重命名必须修改 tmux
`session_name`，不能继续用 `@gallager-description` 充当显示别名。

### 实施范围

1. 在 `TmuxService` 增加 `rename-session` 封装，使用精确 target，拒绝空名称、
   当前已存在的名称以及 tmux 不支持的 `:`/`.` 字符。
2. 在共享命令协议增加 `RenameTmuxSession`，由 host 执行并将刷新后的 session
   状态推送给所有 viewer。
3. session 名变化时同步更新 pane stream target 和 control client 索引，避免继续
   使用旧名称捕获终端或管理尺寸。
4. macOS 本地会话和远程会话右键菜单增加 `Rename Session`；macOS 双击会话行
   直接打开相同的名称输入框，单击选择行为保持不变。
5. iOS 会话长按菜单增加 `Rename Session`，复用同一共享编辑 UI 和 relay 命令。
6. 本地重命名后迁移以 session 名为键的选择、文件/浏览器标签、Git 工作区和
   布局保存状态，不把同一 session 当成删除后新建。

### 验收标准

- 本地重命名后，`tmux list-sessions` 只显示新名称，现有 pane 和运行中的进程不变。
- 远程 Mac/iOS viewer 可通过 relay 重命名 host 上的 session，并收到新状态。
- 空名称、非法名称和名称冲突返回明确错误，原 session 保持不变。
- macOS 双击本地或远程会话行弹出预填当前名称的输入框；单击仍只选择会话。
- macOS 和 iOS 右键/长按菜单均包含 `Rename Session`。
- 当前选中的本地会话重命名后仍保持选中，文件、浏览器、Git 和分屏状态不丢失。
- 现有 Description、Emoji、Color、State、Rename Window 和终端输入行为不回归。
- 聚焦单元测试、受影响的 Swift package 测试以及 macOS/iOS 构建通过。

## Stage 2：远程 Terminal Stream 自动恢复

### 目标

当 iPhone 或 Mac viewer 网络切换、App 前后台切换或 relay WebSocket 短暂重连时，
当前终端页自动恢复，不再因为一次瞬时失败永久停留在错误或断开状态。

### 实施范围

1. 让 `LiveTerminalView` 的 stream task 跟随 host 连接状态，而不是只在 view 首次
   出现时执行一次。
2. 连接断开时进入等待恢复状态并取消未发送的输入；连接恢复后重新订阅 terminal
   stream。
3. 对已经请求过的 stream 先发送 `StopTerminalStream` 再重新 `StartTerminalStream`，
   平衡 host 端订阅计数并强制获取完整初始画面；首次订阅不得先 stop，避免影响
   正在观看同一 pane 的其他 viewer。
4. 已连接状态下的瞬时 start 失败自动做一次清理重试；仍失败时显示错误和手动
   `Retry` 操作。
5. 保持多 pane、键盘输入、剪贴板和 terminal stream 消息路由行为不变。
6. Mac viewer 的 `NSViewRepresentable` 在 host 连接状态变化时同步 stream 生命周期；
   `updateNSView` 不重复 start，只有连接边沿或人工 Retry 才触发恢复。
7. iOS 与 Mac 共用同一个 stream recovery 决策模型，不维护两套订阅计数规则。

### 验收标准

- iOS terminal 页面打开后，host 短暂断开再恢复，无需退出页面即可重新显示终端。
- 断线期间不发送键盘输入，恢复后输入顺序正常。
- 首次连接只发送 start；重连和手动重试使用 stop/start，不泄漏 host 订阅计数。
- 同一连接上的一次瞬时 start 失败可自动恢复；持续失败时用户可手动重试。
- 恢复后的 initial state 替换断线前的旧画面，不混入断线期间缺失的数据块。
- 聚焦单元测试、iOS Simulator 构建及 iPhone 真机验证通过。
- Mac viewer 的 host 短断和 start 瞬时失败可在原页面恢复；替换订阅期间旧 stream
  的 `streamEnd` 不得终止新连接。持续失败时保留明确错误和人工 Retry。
- `CtrlxServer` macOS 构建通过，并在本机 viewer 验证远程 terminal 输入无回归。

## Stage 3：Terminal Payload 缓存性能

### 目标

降低 Codex 等高频刷新 TUI 在 Mac viewer 中的持续 CPU 占用，同时保持 OSC 8
超链接识别、普通 URL 检测和终端渲染行为不变。

### 实施范围

1. 让共享 payload 缓存识别输入数据中真正的 OSC 8 起始序列，并正确处理序列跨
   数据块拆分的情况。
2. 只有出现新 OSC 8 序列时才扫描终端缓冲区并提取 payload；普通终端输出仅校验
   已缓存的链接单元格，不再遍历所有行列。
3. macOS 与 iOS 共用同一优化路径，不增加平台分支或 relay 协议字段。
4. 增加序列检测聚焦测试，并用持续刷新的真实 Codex pane 对比修复前后 CPU。

### 验收标准

- 完整及跨数据块拆分的 `ESC ] 8 ;`、C1 OSC 8 序列都能触发 payload 提取。
- 普通文本、CSI 动画和其他 OSC 序列不触发全缓冲区扫描。
- 已缓存链接被普通文本覆盖或被 scrollback 淘汰后仍会失效。
- OSC 8 链接点击、普通 URL 检测和终端显示不回归。
- 聚焦单元测试、macOS 构建通过；同一高频刷新 pane 的空闲观察 CPU 明显下降。

## Stage 4：Host Terminal Stream 生命周期

### 目标

修复 Mac host 在高吞吐输出及 iOS/Mac viewer 重连或重试时出现的 terminal stream
初始化失败和订阅泄漏。同一 viewer 对同一 pane 的重复 Start 必须幂等，首个实时
增量不得早于完整 initial state，失效的 tmux subscription 必须能被清理并重新创建。

### 实施范围

1. 保留命令来源 viewer 的 pairId，并将其传入 host terminal stream 生命周期。
2. 将按次数增减的订阅计数改为按 viewer ID 管理的集合；重复 Start/Stop 不改变
   其他 viewer 的所有权。
3. 复用已有 stream 时若无法读取当前 pane 内容，立即清理失效 subscription，允许
   viewer 的下一次有限重试创建新 stream。
4. 在订阅前建立有序增量缓冲，但只在 initial state 发送完成后启动消费，确保高吞吐
   输出不会抢占初始化消息或拖延 Start command response。
5. 不修改 relay 协议，不增加轮询或无限重试。
6. 增加订阅所有权聚焦测试，并验证 macOS host 构建及 loffice 真机链路。

### 验收标准

- 同一 viewer 连续 Start 同一 pane 只保留一个订阅所有权。
- 一个 viewer Stop 不会终止其他 viewer 正在使用的 stream。
- 最后一个 viewer Stop 后释放 `PaneStreamManager` subscription 并发送 streamEnd。
- 旧 stream 无法捕获 pane 内容时会被清理，后续 Start 可重新订阅。
- pane 在持续高吞吐输出时，iOS 仍先收到 initial state，再按序收到订阅期间缓存的
  增量，Start 命令不因实时输出占满发送链而超时。
- iOS 连接 loffice 后可打开并输入 terminal，高吞吐任务期间不再出现 `Stream Error`。
- 聚焦测试、Swift package 测试与 macOS 构建通过。

## Stage 5：Agent Pane 进程校准

### 目标

修复 tmux pane 的普通终端与 coding agent 图标偶尔分类不准的问题。插件 hook 继续
提供实时、权威的 agent 生命周期；host 每 10 秒扫描一次 pane 进程树，只校准 hook
缺失或进程异常退出造成的遗漏和残留。

### 实施范围

1. 保持现有显示语义：session 行在任意 window/pane 存在 agent 时显示 agent 状态，
   window 标签只反映自身 panes。
2. 在 `MirrorWindowManager` 单独维护进程扫描推断的 pane 所有权，不让扫描结果覆盖
   或删除插件 hook 已确认的会话。
3. 每 10 秒调用现有 `TmuxService.detectAgentPanes`；新增 agent 时补标，已退出的扫描
   推断 agent 及时撤销。
4. 插件报告 session end 后，在旧进程仍处于退出阶段时抑制扫描复活；进程消失后
   自动解除抑制。
5. 仅当分类实际变化时更新防休眠状态并向 viewer 推送 session state。
6. 周期任务随 host 生命周期启动和取消，不改变现有 5 秒 pane/session 校验间隔。

### 验收标准

- 在已有普通 shell pane 中启动 Codex/Claude 后，最迟 10 秒出现正确 agent 图标。
- 没有 hook 的 agent 进程退出后，最迟 10 秒恢复普通终端图标。
- hook 已确认的 agent 不会因某次进程扫描漏报而被清除。
- hook 报告结束后，仍在退出中的旧进程不会把 agent 图标重新标回。
- 同一 session 的左侧状态与每个 window 标签继续使用原有聚合层级。
- 无分类变化时不推送重复 session state；聚焦单元测试与 macOS 构建通过。

## Stage 6：Session 名称展示优先级

### 目标

让 rename session 后的真实 tmux `session_name` 在 Mac 和 iOS 的默认会话界面
立即可见。Description 继续作为独立元数据，但不再遮住 session 身份。

### 实施范围

1. Mac 的 agent 和普通终端默认 Sidebar Fields 均将 `sessionName` 放在首位。
2. 仅对完全等于旧默认数组的已保存配置执行一次性迁移；不改写用户自定义顺序。
3. iOS agent/普通终端行以 `sessionName` 为主标题，Description 和项目/目录信息作为副标题。
4. iOS 会话详情页标题固定使用 `sessionName`，window/terminal 标题继续在标签内展示。
5. Mac 菜单栏的 agent 和 terminal-only 行使用真实 `sessionName`，不再以 Description 取代。
6. 增加默认值、旧配置迁移和共享展示规则的聚焦测试，并验证 macOS/iOS 构建。

### 验收标准

- 存在 Description 时，Mac 和 iOS 默认会话行仍以新 `sessionName` 为主标题。
- Description 仍可编辑、清空并显示为副信息，不与 rename 互相改写。
- 旧默认 Mac 配置自动升级；非默认的自定义 Sidebar Fields 保持原样。
- iOS 会话列表和详情页、Mac 本地/远程侧边栏及菜单栏均能看到改名结果。
- 聚焦单元测试、Swift package 测试与 macOS/iOS 构建通过。

## Stage 7：macOS Terminal 行级渲染缓存

### 目标

降低本地和远程 Mac terminal 在 Codex spinner、进度条等小范围高频刷新时的主线程
占用。终端内容更新不再误触发 AppKit/SwiftUI 布局，只重建发生内容或视觉状态变化
的可见行，并避免对未变化行重复执行 URL 检测和 CoreText 排版。

### 实施范围

1. 以同一 211 × 59 Codex spinner pane 的 Release CPU、绘制行数和主线程采样作为
   固定基线；临时测量代码不得进入发布路径。
2. 在 SwiftTerm CoreGraphics renderer 中缓存每行的 `ViewLineInfo`、`CTLine` 和
   glyph runs；缓存键使用 `BufferLine` identity、generation、绝对 row 和列数。
3. 将 terminal feed、滚屏和 range change 产生的 URL 装饰更新从 `needsLayout` 中
   拆出，在主线程下一轮合并执行；真实尺寸变化仍走原有 layout 路径。
4. 对可见行的 URL 检测结果增加同样由 line identity、generation、绝对 row 和列数
   约束的缓存；只保留当前 viewport，避免每个输出块扫描整屏。
5. selection、hover link、Command-link highlighting 等不由 `BufferLine.generation`
   表达的交互状态直接绕过缓存；字体、主题、ANSI palette 和渲染选项变化时清空缓存。
6. 缓存只保留可见行，避免 scrollback 增长导致内存无界增长。
7. 不修改 terminal feed 数据、relay、tmux stream 和 iOS 渲染逻辑；不重新引入 Stage 3
   已验证无稳定收益的降帧、数据合并或默认 Metal renderer。
8. 增加缓存命中、内容变更、行替换、交互状态绕过和全局失效的聚焦测试，并以相同
   Release 场景比较 CPU、主线程热点和输入响应。

### 验收标准

- 只有 Codex spinner 一行变化时，未变化可见行不再调用 `buildAttributedString` 或
  `CTLineCreateWithAttributedString`。
- 普通输出、滚屏、alternate buffer、窗口 resize、字体/主题切换、链接和文本选择
  显示正确，无陈旧行或残影。
- 缓存容量与可见行数绑定，scrollback 持续增长时缓存不无限增长。
- terminal feed、滚屏和 range change 不再请求完整布局；URL 下划线仍在下一轮主线程
  更新，窗口尺寸变化仍触发原有布局和 resize。
- 同一 211 × 59 Release 场景 CPU 相比约 100% 基线明显下降，且主线程绘制样本显著减少。
- SwiftTerm 聚焦测试、Gallager Swift package 测试与 macOS Release 构建通过。

## Stage 8：新建 Window 的 Terminal Stream 竞态修复

### 目标

修复 macOS 本地会话新建 window 后偶发无法及时选中，或键盘输入已经送入 tmux、
Gallager 终端却不再回显的问题。window 数量和 agent 进程校准只能影响复现概率，
不得作为容量限制或通过降低轮询频率掩盖竞态。

### 实施范围

1. `PaneStreamManager` 对每个 pane 的 reader 创建实行 single-flight；按需订阅、
   control-client pane 发现和周期刷新必须等待同一创建任务，不能重复覆盖 FIFO 或
   `tmux pipe-pane`。
2. reader 创建失败后清除 in-flight 状态，允许下一次发现或订阅重试；shutdown 必须
   取消并等待未完成创建，不遗留 FIFO 或 reader。
3. macOS 本地 `New Window` 复用现有 `PaneSurfaceRetry`，等待 `refreshPanes()` 的缓存
   真正包含新 pane 后再选择 window；超出重试预算时显示明确错误。
4. 不修改 tmux 命令协议、relay、iOS terminal stream 和 10 秒 agent 进程校准逻辑。
5. 增加 per-pane reader 并发创建、失败后重试和 stale refresh 后 window surface 的
   聚焦回归测试。

### 验收标准

- 同一 pane 的多个并发 reader 请求只执行一次底层启动，并复用同一 reader。
- reader 首次启动失败后，后续请求可以重新启动，不永久卡在 in-flight 状态。
- 新建 window 与 5 秒 pane refresh、10 秒 pane discovery 同时发生时，最终仍选中新
  window，并建立可持续接收输出的 pipe reader。
- 输入字符在 tmux pane 和 Gallager 镜像中同步出现，不需要切换 tab 或等待下一轮刷新。
- agent 类型校准频率和分类语义不变。
- 聚焦测试、完整 Swift package 测试与 macOS Release 构建通过。

## Stage 9：iOS Terminal 本地文本复制

### 目标

在不改变 host tmux window 尺寸的前提下，让 iOS 能稳定选择并复制当前屏幕之外的
terminal 内容。复制数据直接来自已经渲染的本地 SwiftTerm buffer，不增加 relay
请求，不依赖 host 重新捕获画面。

### 实施范围

1. 保持现有“host 尺寸 terminal + 外层滚动视口”架构，不发送
   `ResizeTmuxPane`，不在 iOS 单方面重排 terminal buffer。
2. 从 `InteractiveTerminalView` 生成静态纯文本快照，覆盖当前可用 scrollback 与
   viewport，并按 terminal 行去掉右侧填充空格。
3. 快照只在用户打开复制界面时生成，不跟随每个 terminal 数据块重建。
4. 增加只读原生文本选择界面，支持系统跨屏选区、复制和全选；关闭后回到实时
   terminal，既有短文本原位选择保持不变。
5. 快照为空时给出明确反馈，不展示无法操作的空白复制界面。
6. 不修改 relay、host、tmux 命令协议和 macOS terminal 行为。

### 验收标准

- iOS 可从 terminal 工具栏打开复制界面，文本来自当前本地 terminal buffer。
- 长内容能在复制界面跨越手机可见区域选择并复制。
- 打开复制界面后 terminal 继续输出也不会移动当前选区；重新打开才生成新快照。
- 普通 buffer、alternate buffer、中文、宽字符和空白行生成可读文本。
- 无可复制文本时显示明确提示。
- iOS 聚焦测试与 Simulator 构建通过；真机复制行为验证通过。

## Stage 10：Agent 快捷回复可靠提交

### 目标

修复 iOS 在 agent 停止后的顶部回复框点击 Send 时，偶发只把正文写入 TUI、却没有
触发 Enter 提交的问题；同时移除未确认实际发送结果就显示并持久化
`Prompt submitted` 的虚假成功状态。

### 实施范围

1. 顶部 reply-after-stop composer 通过已有 command/response 通道直接发送
   `[.text(...), .delay(200), .enter]`，等待 host 完成 tmux 操作，而不是只确认
   WebSocket 写入。
2. Claude Code 与 Codex 的 prompt/reply-after-stop 翻译采用同样的 TUI settle 边界，
   避免正文与 Enter 在同一个输入 burst 中被 TUI 错误消费。
3. reply composer 不再设置或恢复 `promptSubmitted`。host/tmux 对完整输入序列返回
   command success 后清空草稿；连接失败、超时或 tmux 失败时保留。真实 agent state
   进入 `working` 时仍收起 composer 并清理草稿，作为状态通道可用时的兜底。
4. reply 草稿归属于当前 `ResponseState`：`doneWorking → idle` 的 handled 翻转继续
   保留未发送内容，真正进入 `working` 后销毁旧状态；下一轮 composer 使用新的
   lifecycle identity，禁止 SwiftUI/UITextField 复用上一轮的编辑缓存。
5. 不重发 Enter，不修改 blocking form、terminal 键盘或 sidecar 插件协议。
6. 增加 built-in plugin 翻译、延迟边界与 reply composer 状态聚焦测试。

### 验收标准

- iOS 顶部回复框点击 Send 后，host 先写入 literal 正文，等待 200ms，再发送命名 Enter。
- UI 不再显示 `Prompt submitted`；command success 后输入框清空但 composer 保持可用，
  command failure 时保留原文以便重试。
- agent 进入 working 后旧草稿清空；下一轮结束重新出现 composer 时不得恢复上次内容。
- 导航离开再进入 idle/doneWorking session 时，顶部 composer 仍然出现。
- 空 reply-after-stop 仍只发送 Escape；空 prompt 仍不发送任何内容。
- blocking form 与交互式菜单按键时序保持不变。
- Claude Code、Codex、TmuxService 聚焦测试与 macOS/iOS 构建通过。

## Stage 11：iOS Agent 输入模式

### 目标

让顶部 Agent 快捷输入成为可选体验。默认关闭时，进入 Agent pane 只显示 terminal，
既不弹出键盘，也不显示普通 prompt/reply composer；键盘显示/隐藏按钮始终作为
导航栏直接操作，不再收进 Agent 命令菜单，由用户明确决定何时输入。

### 实施范围

1. 在 iOS 设置中增加持久化的 `Agent Quick Input` 开关，默认关闭；升级用户也使用
   相同默认值，不做隐式迁移。
2. 将普通 prompt/reply-after-stop 与 permission/question/plan 等阻塞表单分开处理：
   开关只控制前者，阻塞表单始终可见。
3. 首次进入或切换到 Agent pane 时不自动启用 terminal 键盘。开关关闭时保持只读
   terminal；开启时展示顶部快捷输入，terminal 键盘仍只由导航栏按钮控制。
4. 阻塞表单到达时退出 terminal 键盘输入模式，避免审批 UI 与 terminal first
   responder 争抢焦点；表单处理后不擅自重新弹出键盘。
5. 将 Agent pane 的键盘按钮从 Commands 菜单移到导航栏；Yolo Mode 与 Session Info
   继续留在 Commands 菜单，普通 terminal pane 的按钮行为不变。
6. 不修改 relay、host、tmux 命令协议及 Stage 10 的可靠提交路径。

### 验收标准

- 全新安装或未保存该设置时，`Agent Quick Input` 默认为关闭。
- 默认设置下进入 Agent pane 不自动显示 terminal 键盘，也不显示顶部快捷输入框。
- 开启设置后，进入 Agent pane 默认显示现有顶部快捷输入框；Send 的可靠提交和清空
  行为不回归。
- permission、question、plan approval 等阻塞表单不受开关影响；到达时键盘收起且表单
  可操作。
- Agent 与普通 terminal pane 的 Show/Hide Keyboard 图标都直接显示在导航栏。
- terminal 键盘只响应用户直接操作；切换 pane 或 agent 状态刷新不会自动弹出。
- 展示策略聚焦测试、Swift package 测试、iOS device 构建及 iPhone 真机验证通过。

## Stage 12：Agent 工作进度兜底

### 目标

让不发送 `OSC 9;4` 的 Codex 等 agent 在工作时也显示蓝色 indeterminate
进度条，同时保留终端程序报告的真实百分比、警告和错误进度的最高优先级。

### 实施范围

1. 在共享 `PaneState` collection 上派生 session 有效进度：先选择第一个真实
   `progress`，仅在所有 pane 都没有真实进度时才以 working agent 兜底为
   `.indeterminate`。
2. macOS 本地 sidebar、Mac viewer、iOS session list 及对应 accessibility proxy
   全部读取同一派生规则。
3. 不解析 Codex terminal title spinner，不新增 relay 字段或可变 UI 状态。
4. 增加无进度、working fallback、非 working 隐藏、多 pane 真实进度优先测试。

### 运行时前置条件

Codex 必须先安装 Gallager agent 插件，并在安装后新建会话，才能通过 hook
产生 `.working` 状态。仅靠进程检测发现的 Codex 会话保持 `.idle`，不会触发
fallback；Claude Code 原生 `OSC 9;4` 进度不受此条件影响。

### 验收标准

- 已安装 Gallager agent 插件的 Codex 进入 `.working` 且没有 `OSC 9;4` 时显示
  蓝色滚动条，完成或等待输入后隐藏。
- 任意 pane 存在真实 terminal progress 时，真实值优先于其他 pane 的 agent fallback。
- Claude Code 的 `OSC 9;4`、`gallager set-progress`、Mac viewer、iOS 和无障碍值不回归。
- 共享聚焦测试以及 macOS/iOS 构建通过。

## Stage 13：macOS Window 标签双击重命名

### 目标

让 macOS 本地 host 与 Mac viewer 的 terminal window 标签支持双击打开现有
`Rename Window` 输入框，减少必须打开右键菜单的操作成本。

### 实施范围

1. 复用 `WindowRenamingModifier` 的同一份输入状态和保存逻辑，不创建第二套重命名 UI。
2. 本地与远程 window 标签主按钮检测 macOS 双击；单击继续选择 window，双击打开
   预填当前名称的输入框。
3. 远程 host 断开时保持重命名禁用；本地及已连接远程会话继续调用现有 rename 闭包。
4. 右键 `Rename Window`、关闭按钮、split 按钮、拖拽排序以及 file/browser/Git 标签行为不变。
5. 更新 Window Rename E2E 场景，使 host 与 Mac viewer 都覆盖真实双击路径。
6. 不修改 tmux、relay、共享命令协议或 iOS 行为。

### 验收标准

- 双击本地 terminal window 标签后出现预填当前名称的 `Rename Window` 输入框。
- 双击 Mac viewer 的远程 terminal window 标签后出现相同输入框，保存后 host 与 viewer 同步。
- 单击仍只选择 window；右键菜单仍可重命名。
- 断开的远程 host 不允许发起重命名。
- close/split/drag 及非 terminal 标签不误触发重命名。
- Window Rename E2E 编译、受影响 Swift tests 与 macOS 构建通过。

## Stage 14：远程终端输入与回显延迟

### 目标

降低 Mac/iOS viewer 控制 Mac host 时的按键到回显延迟，并保证 Codex 等 TUI
持续高频输出时输入仍能及时显示。优化必须保持按键、raw input 和 terminal stream
顺序，不使用会与真实 PTY 状态分叉的本地字符预回显。

### 实施范围

1. 远程按键批处理从 30ms 尾随 debounce 改为首个按键启动、后续按键不重置的
   10ms 有界窗口；现有单消费者发送队列继续保证 keystroke/raw input 顺序。
2. host terminal stream 从 50ms 尾随 debounce 改为首个数据块启动、后续数据不
   重置的 16ms 固定节拍；达到 8KiB 时立即 flush，并取消已经失效的定时任务。
3. 增加连续输入和连续输出测试，证明数据流持续到来时仍会在窗口上界内发送，
   同时覆盖取消、立即 flush 和操作顺序。
4. 所有性能测量和可分发 DMG 使用 macOS Release 构建；Debug 仅用于定位，不作为
   验收结果。记录同一 211 × 59 Codex 高频刷新 pane 的 CPU 和采样热点。
5. Release 采样若仍显示 pipe-pane/MainActor 数据投递为热点，则只合并连续数据
   delegate 投递，并减少确定没有相关转义序列时的多轮全量扫描；不得改变 terminal
   字节顺序、OSC 事件语义或 relay 协议。
6. viewer 的 UI 状态和 SwiftTerm feed 仍在 MainActor；只允许不可变 `Data` 在 actor
   边界传递，不使用 `Task.detached`、`nonisolated(unsafe)` 或伪造 `Sendable`。
7. iOS 复制终端文本 sheet 弹出前同步释放终端 first responder，并在 sheet 存续期间
   禁止底层 terminal 因视图更新重新激活；关闭时只恢复弹出前已开启的输入状态。

### 验收标准

- 单个远程按键的人为等待上界从约 30ms 降至 10ms；连续输入不会等到停止打字才发送。
- terminal stream 人为等待上界从约 50ms 降至 16ms；持续输出仍按固定节拍发送。
- keystroke、raw input、initial state、增量数据及 stream end 的顺序保持不变。
- Codex 高频输出时 Mac/iOS viewer 可持续输入，不出现成批延迟回显或主线程长时间阻塞。
- 聚焦测试、完整 Swift package 测试、macOS/iOS 构建和 macOS Release 签名校验通过。
- 生成的 `Gallager-2.7-zengjice.dmg` 来自 Release 产物，覆盖安装后可正常连接和输入。
- iOS 复制终端文本 sheet 内可滚动、选中和复制，但不会显示系统键盘；关闭后终端输入
  状态与弹出前一致。

## Stage 15：iOS 终端输入控件位置

### 目标

让 iOS 终端的键盘显示/隐藏入口可在原有右上角与底部安全区之间切换，
既保持升级用户的原有布局，也提供更易点击且不与终端手势冲突的底部选项。

### 实施范围

1. 新增持久化的 `Keyboard Control Position` 枚举设置，只允许 `Top Right` 与
   `Bottom Bar` 两个互斥值；默认 `Top Right`，非法旧值也回退到该值。
2. 在 iOS `Settings > Terminal` 使用原生两项 Picker 绑定该设置，切换后当前终端
   页即时更新，不重连 host 或 relay。
3. 保留轻量的共享底部键盘控件：键盘隐藏时显示 `Input`，键盘显示时
   显示 `Hide Keyboard`，使用系统按钮样式和不小于 44pt 的点击区域。
4. 单终端页在 `Top Right` 时使用原导航栏按钮，隐藏导航栏时使用原右上角
   悬浮按钮；`Bottom Bar` 时只通过 `safeAreaInset(edge: .bottom)` 展示底部控件。
   复制按钮保持原有位置。
5. 多 pane 页由父视图根据同一设置只展示一个右上角或底部控件，键盘输入
   继续只发送到当前选中 pane；无选中 pane 或 host 断开时禁用。
6. 保留现有终端滚动、双击、长按、粘贴/选择及 tmux mouse mode 手势，不给终端
   内容区增加键盘触发事件。
7. 保留 Stage 14 的复制 sheet 焦点隔离；sheet 打开时不得弹出键盘，关闭后按原有
   规则恢复输入状态。
8. 不修改 relay、host、tmux 或 agent 协议，不引入自动弹出键盘或新手势。

### 验收标准

- 未保存设置或保存值无效时默认 `Top Right`，显示升级前的右上角按钮。
- 切换到 `Bottom Bar` 后，键盘隐藏时底部安全区显示 `Input` 控件；点击后键盘
  弹出，控件随键盘上移并
  变为 `Hide Keyboard`。
- 两种位置始终互斥；设置切换即时生效，不断开当前 host 连接。
- 单终端、隐藏导航栏和多 pane 页均遵循同一位置设置。
- 多 pane 切换后，只有选中 pane 接收输入；host 断开时不能启用键盘。
- 终端滚动、双击、长按、粘贴/复制及 tmux mouse mode 行为不回归。
- 复制 sheet 依旧不弹出键盘，关闭后输入状态恢复正确。
- 聚焦测试、Swift package 测试、iOS device 构建和 iPhone 真机验证通过。

## Stage 16：远程终端首屏原子揭示

### 目标

修复 Mac viewer 打开或重连远程 pane 时可见的历史内容回刷，并减少多 Viewer
场景下发送给未订阅设备的终端流量。继续只维护正在查看的 pane，不让后台 window
常驻 SwiftTerm 或实时流。

### 实施范围

1. `PipePaneReader` 的 buffer flush 增加真实完成屏障：返回时此前缓存的 delegate
   事件必须已经按顺序投递，不再把 fire-and-forget 当作完成。
2. `TerminalStreamService` 在 initial state 之后排空 bootstrap 数据并立即发送未满的
   16ms batch；只有该内部屏障通过后，`StartTerminalStream` 才返回成功。
3. initial state、title 和增量 terminal 消息只发送给实际订阅该 pane 的 Viewer；
   push notification 和 session state 的广播语义不变。
4. Mac viewer 在连接阶段缓存 initial state 与随后到达的 bootstrap 原始字节，不逐块
   feed SwiftTerm；同时收到有效 initial state 和 start command success 后，以一次
   feed 建立最终首屏，再揭示 terminal、恢复滚动与焦点。
5. Mac viewer 始终将 SwiftTerm 行列锁定为 Host 报告的 pane 尺寸，布局变化不得按
   Viewer 窗口高度重算 terminal rows；尺寸变化只接受 Host 的 dimension change。
6. 保留现有约三屏 scrollback、8KiB/16ms 实时批处理和当前 pane 按需订阅；不使用
   固定等待、ANSI 启发式去重、后台 window 常驻或本地伪回显。
7. 保持现有网络消息格式，复用 `StartTerminalStream` command response 作为 ready
   信号；旧 Host 仍可连接，新 Host 提供更严格的 bootstrap 完成语义。
8. 增加 flush 屏障、initial/data/ready 顺序、多 Viewer 路由、重试及持续输出期间
   首屏揭示的聚焦测试，并以 Release-like 构建验证切换和高频输出行为。

### 验收标准

- Mac viewer 打开、切换或重连远程 pane 时不显示历史内容逐段回刷；首屏准备完成后
  只执行一次 bootstrap feed 并一次出现，且当前终端内容正确。
- Viewer 布局与窗口尺寸变化不会改写 Host pane 的 terminal rows，也不会触发额外的
  SwiftTerm resize/layout 反馈。
- `flushBuffer()` 完成前的所有数据先于 bootstrap ready；未满 8KiB 的末尾 batch
  不等待常规 16ms 定时器。
- 新 Viewer 的 initial state 不再刷新无关 Viewer；增量数据不发送给未订阅该 pane
  的已连接设备。
- 持续输出期间 `StartTerminalStream` 不饥饿、不依赖输出静默，也不因固定延时增加
  首屏等待。
- 切换 window 后只有可见 pane 保持 Viewer 端渲染；CPU、内存和网络不会随后台
  window 数量线性增长。
- 聚焦测试、完整 Swift package 测试和 macOS Release 构建通过；相同远程切换场景
  完成真机/双 Mac 验收。

## Stage 17：Mac Viewer 交互延迟与主线程公平性

### 目标

修复相同网络、Host 和远程 pane 下，Mac Viewer 输入回显明显慢于 iOS Viewer 的问题。
Mac 同时运行本地 sessions 时仍须优先保证交互响应；允许为此使用更多但有界的计算资源，
不得使用会与真实 PTY 状态分叉的本地预回显。

### 实施范围

1. 固定同一远程 pane 的逐字输入场景，分别记录 Viewer 按键回调、按键批次进入发送、
   Host 命令执行、回显 stream 到达和 SwiftTerm feed 边界；区分网络 RTT、Host 执行和
   Viewer 主线程等待，不以主观感受替代定位证据。
2. 对比 macOS 与 iOS 的共享 `KeystrokeDebouncer`、`ViewerRelayClient` 和 stream 路径，
   只修改能够解释平台差异的部分；不增加 relay 消息、不绕过 E2EE。
3. 审计 Mac 本地 pane 的 pipe reader、session 刷新及 SwiftTerm 渲染是否占用 MainActor，
   对比本地 sessions 空闲、持续输出和完全关闭三种状态，确认输入发送或回显绘制是否
   被无界工作饥饿。
4. 若按键发送被 MainActor 延迟，以一个有序、可取消且有界的交互发送路径替代定时器
   竞争；必须保持文本、Meta/Option、raw mouse input 的 FIFO 语义。
5. 若回显渲染被输出工作延迟，在不丢 terminal 字节的前提下合并每个显示周期的 feed，
   并让每批处理后归还执行权；不得让后台 local window 数量线性增加活跃 View 或任务。
6. 增加确定性测试覆盖单键延迟上界、连续输入、公平调度、取消/重连及字节顺序；性能
   结论使用 Release-like 构建和实际采样，不以 Debug 构建耗时作为验收依据。
7. 生成新的 macOS Release 与固定名称 DMG，在同一远程 pane 上完成 Mac/iOS 对照和
   本地 sessions 负载下的双 Mac 真机验收。

### 验收标准

- 同一网络与远程 pane 下，Mac Viewer 不再出现平台自身造成的可感知按键停顿；网络和
  Host 时间相同时，按键发送与回显 feed 不被本地 session 工作长期阻塞。
- 持续输入不会等到停止输入才发送；持续输出期间交互工作不会被输出队列饥饿。
- 文本、Meta/Option、控制键、raw mouse input 和 terminal 字节顺序保持不变。
- 不使用本地预回显、固定静默等待、无界 Task 或为每个字符长期创建独立后台任务。
- 聚焦测试、完整 Swift package 测试、macOS Release 构建、签名与 DMG 校验通过。
- 相同远程场景完成 Mac/iOS Viewer 对照，且 Mac 同时存在本地 sessions 时体验符合预期。

## Stage 18：macOS 本地终端输入延迟

### 目标

缩小 Gallager 本地 terminal 与直接 `tmux attach` 的输入响应差距。复用本地 pane
已经建立的 tmux control-mode 持久连接发送交互按键，避免为每个按键批次启动新的
`tmux send-keys` 进程，同时保持按键顺序、Meta/Option 组合和失败回退语义。

### 实施范围

1. 以本地 terminal 逐字输入为固定场景，记录现有进程式 tmux 命令开销；当前基线为
   200 次 tmux 客户端调用约 0.79 秒，平均约 3.95ms/次，不把该数据误当作完整回显延迟。
2. 在现有 `TmuxControlClientManager` 上增加窄接口，仅为已经订阅且持有 control-mode
   连接的本地 pane 发送交互按键；不得把任意未转义文本拼接为 tmux 命令。
3. 本地 `InteractiveTerminalView` 输入优先走持久连接；连接不存在、编码不支持或在写入前
   已失效时，回退到现有 `TmuxService.sendKeystrokes` 进程路径。写入后的超时或失败不得
   自动重放整个批次，避免产生重复输入。
4. 持久路径和回退路径共用一个有序发送边界，保证普通文本、命名键、Meta/Option 组合
   以及连续输入的 FIFO 顺序；不添加本地预回显。
5. 增加命令编码、持久连接命中、故障回退和输入顺序测试；先验证第一阶段收益，只有仍有
   可测量延迟时才考虑让普通按键绕过 `KeystrokeCoalescer` 的 runloop 合批。
6. 不修改 remote viewer、relay、host 命令协议、pipe-pane 输出、SwiftTerm 渲染或插件
   使用的通用 `TmuxService` 命令路径。

### 验收标准

- 已建立本地 pane stream 时，连续交互输入不再为每个批次启动新的 tmux 客户端进程。
- control-mode 尚未就绪、编码不支持或写入前已断开时，输入按原顺序通过进程路径发送；
  已经写入后的不确定失败不自动重放，避免重复输入，并沿用现有连续失败错误提示。
- literal 文本、空格、Enter、方向键、Escape、Unicode 和 Meta/Option 组合行为不回归。
- 不使用本地预回显、固定等待、无界 Task 或新的长期后台轮询。
- 聚焦测试、完整 Swift package 测试和 macOS Release 构建通过。
- 使用 Release 产物在同一 local session 对比直接 `tmux attach`，确认主观输入停顿改善；
  若仍存在差距，再以测量证据决定是否进入第二阶段按键合并优化。

## Stage 19：macOS 终端选择与链接激活隔离

### 目标

修复 Mac 端选择终端文本时偶发触发系统“应用程序无法打开”的问题。明确区分链接单击、
拖动选择和多击选择，只允许真实的单击手势激活链接，同时保留选择完成后的自动复制。

### 实施范围

1. 为终端鼠标手势维护最小状态：从 `mouseDown` 开始，记录本次手势是否发生拖动；
   `mouseUp` 只在单击且未拖动时尝试激活链接。
2. 双击继续选择单词、三击继续选择整行、拖动继续选择范围；这些手势结束后可自动复制，
   但不得调用 URL opener。普通单击链接和 tmux mouse-mode 下的单击链接行为保持不变。
3. 修复 SwiftTerm fork 的底层链接处理顺序：链接激活同样受单击且未拖动约束，并确保
   所有 `mouseUp` 返回路径都会复位拖动状态，避免状态泄漏到下一次手势。
4. Mac Viewer 收到远端 `file://` 链接时直接消费，不把 Host 文件路径交给本机
   `NSWorkspace`；HTTP/HTTPS 等现有可浏览链接仍按当前内置浏览器策略处理。
5. 增加聚焦回归测试，覆盖真实单击、拖动结束于链接、双击、三击、自动复制、远端
   file URL 以及 tmux mouse-mode 单击行为。
6. 不修改剪贴板格式、终端选择模型、relay 协议、Host 文件浏览协议或 iOS 手势逻辑；
   不用延时、坐标猜测或吞掉所有 URL 的方式规避问题。

### 验收标准

- 拖动选择、双击选词和三击选行均不会打开 URL 或触发系统“应用程序无法打开”。
- 选择完成后的自动复制仍可用，Command+C 和普通终端输入行为不回归。
- 单击 HTTP/HTTPS 链接仍按现有策略打开；本地受支持的文件链接行为保持不变。
- Mac Viewer 的远端 `file://` 链接不再回退给本机系统打开器。
- SwiftTerm 的拖动状态在正常、链接和 mouse-reporting 提前返回路径均被复位。
- 聚焦测试、完整 Swift package 测试和 macOS Release 构建通过。

## Stage 20：终端传输背压与高吞吐恢复

### 目标

让持续大量终端输出不再转化为无界内存增长和不断累积的输入回显延迟。Host、Relay
和 Viewer 必须提供可测量的有界传输链路；当 Viewer 长时间跟不上 Host 时，以原子
terminal snapshot 恢复到最新状态，而不是永久回放已经过时的输出。

### 实施范围

1. 增加低开销、聚合式传输指标，覆盖 pipe/stream 队列深度与 pending bytes、实际
   batch size、加密耗时、WebSocket send 耗时和 SwiftTerm feed 耗时。热路径不得逐帧
   写日志；指标按固定窗口汇总，并提供可测试的快照。
2. 修复实时输出批处理：每条 `dataChunk` 必须真正受最大尺寸约束；处理循环采用明确
   的事件数与字节预算，批次之间归还执行权，避免持续输出独占 MainActor。
3. 为 Host terminal stream 增加按字节计的高水位。超过上限后不任意丢弃 ANSI 字节，
   而是合并为一次重同步请求；通过 `PaneStreamManager` 的原子 capture/buffer/flush
   边界生成最新 snapshot，向该 pane 的 Viewer 发送 reset initial state 后继续增量流。
4. Mac 与 iOS Viewer 将同一轮到达的 terminal bytes 在主线程下一轮合并 feed，保留
   消息顺序、首屏原子揭示和 Host 尺寸语义；每次 feed 记录聚合耗时，不把 SwiftTerm
   parser 移到未经证明线程安全的后台线程。
5. Relay 对已校验为 `.encrypted` 的消息直接转发原始 WebSocket frame，不再将密文
   base64 解码后重新 JSON 编码，并保留原 text/binary opcode；控制、配对和错误消息
   继续走现有强类型路径。
6. 修正本机 Relay 部署配置的 `GALLAGER_SOURCE_DIR`，指向稳定主仓库而非已删除的
   worktree。配置只改本机未跟踪文件，不写入仓库或提交敏感值。
7. 增加聚焦测试覆盖超大实时 chunk 切分、公平调度、高水位去重、snapshot 恢复顺序、
   Viewer feed 合并和 Relay 原始帧透传；完成完整 Swift package 与 macOS/iOS 构建。

### 验收标准

- 单次 64KiB pipe read 不产生超过配置上限的 `dataChunk`；bootstrap 与 live 使用同一
  分片规则，字节顺序和内容完全一致。
- 持续输出时队列深度、pending bytes 和内存有明确上限；控制工作与输入回显不会被
  单次无界 drain 长期饿死。
- 超过高水位只触发一次进行中的重同步；Viewer 先重置为完整 snapshot，再消费边界后
  的增量数据，不显示过时积压或损坏的 ANSI 状态。
- Mac/iOS terminal feed 在同一主线程轮次合并，首屏、窗口切换、选择、复制、滚动和
  输入行为不回归。
- Relay 原始转发保持原 frame 字节不变，仍拒绝非法或非授权连接，连接计数和消息计数
  语义不变。
- 聚焦测试、完整 Swift package、Relay Linux 构建、macOS Release 和 iOS 构建通过；
  两分钟持续输出场景中指标证明队列保持有界，停止输出后不继续长时间回放积压。

## Stage 21：iOS 底部输入按钮栏紧凑化

### 目标

将 iOS 终端页可选的底部键盘按钮栏从约 56pt 压缩到约 28pt，并回收 Home Indicator
上方部分空白，减少对终端可视区域的占用。保持按钮位置设置、键盘显隐、禁用状态及
单 pane/多 pane 行为不变。

### 实施范围

1. 只调整共享 `TerminalKeyboardBar`，两处调用继续复用同一组件，不复制布局代码。
2. 使用系统紧凑按钮尺寸、caption 字号和更小的外边距；去掉 44pt 的可见最小高度，
   目标总栏高不超过原实现的一半。
3. 保留全宽命中区域、无障碍标签与标识符；不增加手势、悬浮层或终端内容区事件。
4. 保留 `.safeAreaInset(edge: .bottom)` 锚定方式，键盘出现时仍由系统将按钮栏放在
   键盘上方，不手工计算键盘或安全区高度。
5. 不修改 `terminalKeyboardControlPosition` 设置、relay/host 协议、输入状态机、复制
   sheet 或终端滚动逻辑。
6. 键盘隐藏时根据实际 bottom safe-area inset 最多回收 16pt，同时至少保留一半系统
   手势区；键盘显示时不回收，无 Home Indicator 的设备也不应用负 padding。

### 验收标准

- `Bottom Bar` 模式的可见高度约 28pt，不超过原约 56pt 的一半。
- `Input` 与 `Hide Keyboard` 状态切换、断线禁用及设置即时切换行为不回归。
- 单 pane 与多 pane 页面呈现一致；`Top Right` 模式完全不受影响。
- Home Indicator 设备的底部空白明显减少但按钮不压住系统手势区；键盘显示及无
  Home Indicator 设备不发生下沉或裁切。
- `git diff --check` 与 iOS 构建通过，并在真机确认按钮可点击且终端可视区域明显增加。

## Stage 22：iOS 终端复制格式与多行粘贴

### 目标

让 iOS 复制页面按终端的逻辑行展示文本，不把终端自动折行误当成真实换行；从系统
剪贴板粘贴多行内容时，保留 bracketed-paste 边界，使 Agent 将其视为一次粘贴而不是
多个 Enter 提交。

### 实施范围

1. 复用 SwiftTerm 已有的文本选择导出逻辑生成快照；它负责合并软换行、保留硬换行和
   空行，并继续跳过宽字符后的空单元格。不自行维护第二套终端行拼接算法。
2. 复制页面继续使用只读 `UITextView` 和系统选择菜单；只调整文本来源及必要的排版参数，
   不引入 WebView、富文本解析或实时观察终端输出。
3. 修复 `TmuxKey` 字节解析对 `CSI 200~` / `CSI 201~` 的处理：这两个序列是
   bracketed-paste 边界，必须按原字节转发，不能作为未知 CSI 丢弃。
4. 保持现有 `SendKeystroke`、输入 FIFO、E2EE 与 Relay 协议不变；不新增粘贴命令，
   不在 Viewer 猜测目标应用类型，也不无条件给普通终端输入包裹转义序列。
5. 增加聚焦测试，覆盖软换行合并、硬换行与空行保留、Unicode，以及 bracketed-paste
   边界和多行内容解析顺序。
6. 完成 iOS 构建、签名、覆盖安装和 iPhone 真机验收。

### 验收标准

- 复制页面不再因终端列宽自动折行而打断同一逻辑行，硬换行、空行和中文保持正确。
- `Copy All` 与手工选区仍使用系统剪贴板和原生选择手势，复制页面不会弹出键盘。
- 多行粘贴的起止边界、正文和换行按原顺序到达 Host；Agent 只收到一次粘贴，不产生
  多个独立提交。
- 单行输入、Enter、方向键、鼠标 raw input、终端滚动和复制页焦点行为不回归。
- 聚焦测试、完整 Swift package、`git diff --check` 与 iOS 构建通过，并完成真机验收。

## Stage 23：iOS 终端双击宽字符选区

### 目标

修复 iOS 正常终端界面双击中文、Emoji 等双列字符时，触点落在字形右半格会命中续格，
导致选区起点、范围或复制内容不准确的问题。保持现有滚动、链接、鼠标模式和复制页面
行为不变。

### 实施范围

1. 在 SwiftTerm 的选择服务中识别双列字符的续格，将选词触点归一到其左侧字符本体；
   不在 Gallager 手势层复制 SwiftTerm 的选词算法。
2. 选词扫描读取续格时沿用所属双列字符，使连续中文仍按现有“字母/数字词”规则形成
   一个范围；保留 ASCII、空白、括号表达式和拖动扩选语义。
3. 不手工叠加内外 `UIScrollView` 的 `contentOffset`。UIKit 已把手势位置转换为终端内容
   坐标，重复补偿会破坏滚动后的命中。
4. 在 SwiftTerm fork 增加聚焦测试，覆盖点击双列字符左半格、右半续格、连续宽字符与
   相邻 ASCII；更新 Gallager 的 SwiftTerm 固定 revision，并统一各入口的解析文件。
5. 不新增手势识别器，不改变双击/三击映射，不修改 Relay、Host、tmux 或复制页面协议。
6. 完成 SwiftTerm 聚焦测试、Gallager 完整 Swift package 测试、iOS device 构建和真机
   双击验收。

### 验收标准

- 双击中文或其它双列字形的左右半边均命中同一个词，选区不再偏到续格或得到空文本。
- 连续中文、中文与 ASCII 组合遵循现有选词规则；ASCII、空白和括号选区不回归。
- 横向/纵向滚动后双击仍命中触点所在内容，链接单击、长按和 tmux mouse mode 不回归。
- 复制页面、多行 bracketed paste、键盘显隐和终端输入行为不受影响。
- SwiftTerm 聚焦测试、Gallager 完整测试、`git diff --check` 与 iOS device 构建通过，
  并完成 iPhone 真机验收。

## Stage 24：Viewer 断线清理与终端首帧恢复

### 目标

修复 Viewer 断线、Host→Relay 连接重建或 WebSocket 发送失败后，Host 仍保留旧 terminal
stream、旧发送 Task 越过重连边界继续工作，以及 iOS 在缺失 initial state 时永久停留在
Connecting 的问题。每次 Viewer 重连必须从干净的 stream 所有权和发送代际开始，且慢首帧
能够通过一次性诊断日志定位，不依赖扩大缓冲区或重排终端字节。

### 实施范围

1. 将 Viewer presence 断线和 Host→Relay 连接失效事件传递给
   `TerminalStreamService`；增加按 viewer ID 清理所有 stream 的窄接口，只移除该 Viewer
   的所有权，其他 Viewer 与 pane subscription 按现有引用语义保留。
2. Host 仅在 Relay WebSocket 和目标 Viewer 均已完成 peer handshake 时发送 terminal
   stream；离线阶段不得继续构造 Base64、E2EE payload 或 WebSocket frame。
3. 为 `ConnectedViewer` 的加密发送队列和 fire-and-forget 命令链增加单调 connection
   generation。连接或 Viewer presence 失效时推进代际并断开 chain head；旧 Task 在等待
   前序任务后必须再次校验代际，禁止在新 WebSocket 上发送旧帧或执行旧输入。
4. WebSocket send 失败必须立即使当前连接失效、取消 socket，并复用现有 receive-loop
   重连流程；不得只记录错误后向上层表现为成功，也不得并行启动第二套重连任务。
5. 为每次 terminal bootstrap 记录 capture、initial payload、发送队列深度与最老等待时间、
   initial send 和总耗时。正常路径不写逐次日志；仅超过固定慢路径阈值时输出一条聚合
   warning，热路径继续使用现有窗口指标。
6. iOS 在 Start command 返回成功但当前 attempt 仍未收到 initial state 时，将该 attempt
   判为失败并进入现有的一次 replacement retry；第二次仍失败则展示明确错误，不无限
   停留在 Connecting。
7. 保持现有 WebSocket/E2EE/terminal stream 消息格式、8KiB/16ms 实时批处理、snapshot
   resync 和多 pane 行为；不增加发送优先级、无界缓冲、固定静默等待或新配置项。

### 验收标准

- 一个 Viewer 断线只清理它在所有 pane 上的 stream 所有权；其他 Viewer 继续收到原有
  增量流，最后一个 Viewer 离开时底层 pane subscription 正常释放。
- Viewer 离线期间 Host 不编码、加密或发送 terminal stream；重连后旧 generation 的
  terminal frame 和 fire-and-forget 命令均不会进入新连接。
- WebSocket send 失败使连接立即进入既有重连状态，不等待 ping watchdog 或 15 秒命令
  超时才发现半开连接。
- 正常 bootstrap 不增加日志噪声；慢路径 warning 在一行内包含 pane、viewer、首帧大小、
  capture/queue/send/total 耗时与发送队列状态。
- iOS 缺失 initial state 时最多执行一次 replacement retry，之后显示错误；正常首帧仍在
  initial state 到达时立即呈现，不等待 command response 才显示。
- 聚焦测试、完整 Swift package 测试、macOS Release 构建和 iOS device 构建通过；并发
  编译不引入 `Sendable`、actor isolation 或数据竞争告警。

## Stage 25：macOS 零中断更新与 control client 收敛

### 目标

修复 Gallager 退出或脚本更新后，App 自己创建的 `tmux -C` control client 未完成退出而被
reparent 给 launchd，进而让后续启动出现额外客户端、资源竞争或本地输入卡顿的问题。更新
过程只能短暂断开 Viewer 和 App 的镜像链路，既有 tmux session、window、pane 及其中运行的
agent 必须保持原身份和进程不变。

### 实施范围

1. `TmuxControlClient` 继续由 actor 独占 `Process`、stdin 和回调状态。断开时先停止读事件、
   关闭 control stdin，再向该 actor 持有的精确子进程发送 `SIGTERM` 并有界等待；仅当同一
   `Process` 仍存活时才对其 PID 发送 `SIGKILL`，不得使用进程名扫描或作用于 tmux server。
2. termination handler 必须携带具体 `Process` 身份回到 actor。旧进程退出不得清空重连后
   的新进程引用，不得重复完成命令 continuation 或触发错误连接的退出回调。
3. App 总退出期限覆盖 pane pipe 清理和 control client 的有界退出，但保持硬上限；不以
   无限等待、detached task、锁或第二套进程管理器掩盖生命周期缺陷。
4. 公网零参数安装脚本继续通过 LaunchServices 启动 App，安装前优先请求正常退出。脚本
   不执行 `tmux kill-server/kill-session/kill-window/kill-pane`，不修改用户 tmux 配置，也不
   把关闭 tmux 会话作为失败恢复手段。
5. 使用独立 tmux socket 做集成验收：记录 session ID、pane ID、pane PID 和 pane 内子进程
   PID，断开 control client 及替换 App 后逐项比对；测试结束只销毁该测试 socket。
6. 完成聚焦单元测试、完整 Swift package 测试、macOS Release 构建、签名 DMG 和公网安装
   文件校验；发布前验证安装脚本与 DMG checksum 一致。

### 验收标准

- `disconnect()` 返回时其精确 control client 子进程已经退出；连续 connect/disconnect 不
  遗留被 launchd 收养的 `tmux -C`，并且旧 termination handler 不破坏新连接。
- App 正常退出、超时兜底和脚本升级均不调用任何 tmux 会话销毁命令；更新前后的 session
  ID、pane ID、pane PID、agent PID 完全一致，pane 内容继续增长。
- 更新完成后 App 由 LaunchServices 启动，stdio 不继承 `curl | bash` 管道；CLI readiness
  与 ping 通过，本地 session 可立即输入。
- 聚焦测试、完整 Swift package、`git diff --check`、macOS Release 构建、DMG 校验及公网
  下载 checksum 全部通过；无新增 Swift 并发隔离或数据竞争告警。

## Stage 26：主仓库可重现打包与可见构建标识

### 目标

将 macOS DMG 和 iOS IPA 的本地打包入口固定到主仓库及主仓库内的独立缓存，
不再复用 DerivedData 或 SwiftPM 中指向已删 worktree 的依赖路径。两端界面同时展示
语义版本、构建号、UTC 构建时间与 Git 短 revision，使真机验收能直接判断是否已更新。

### 实施范围

1. 增加共享的 `AppBuildInfo` 值类型，只从 bundle 标准版本字段和两个自定义 Info.plist
   字段生成展示文本；macOS About 与 iOS Settings/About 复用同一实现。
2. 时间戳与 Git revision 是编译期只读元数据。不改写 `MARKETING_VERSION`、
   `CURRENT_PROJECT_VERSION` 或协议兼容版本，避免破坏 App Store、Sparkle 及 peer 版本比较。
3. 提供零参数 macOS/iOS 本地打包脚本。脚本必须校验当前项目是 Git primary
   worktree，否则立即失败；产物固定写入主仓库 `dist/`。
4. DerivedData 与 cloned SourcePackages 固定在主仓库忽略目录 `.build-local/`；
   Xcode 显式禁用全局 package repository cache，防止命中旧 worktree 镜像路径。
5. iOS 脚本从已忽略的 `Config/Local.xcconfig` 及本机 provisioning profiles 自动完成
   个人团队分层签名；不在仓库硬编码 team、bundle ID、证书 hash 或设备 ID。
6. 现有 `release.sh` 和 `testflight.sh` 也复用主仓库校验、本地缓存路径及构建
   元数据，不保留第二套默认 DerivedData 行为。

### 验收标准

- 在 feature worktree 运行打包脚本会在 Xcode 启动前明确拒绝；在主仓库运行时，
  Xcode 命令中的 workspace、DerivedData、SourcePackages 和产物都在主仓库下。
- 打包日志和产物不包含 `Gallager-worktrees`、已删 Stage 目录或其他 DerivedData 绝对路径。
- Mac About 与 iOS Settings 显示完全相同的 `version (build) · timestamp · revision`；
  未通过打包脚本构建时明确回退为标准 `version (build)`，不显示伪时间。
- `AppBuildInfo` 聚焦测试覆盖完整元数据、缺少自定义字段及缺少标准版本字段。
- 完整 Swift package 测试、macOS Release 打包、iOS 签名 IPA 打包、签名校验和两端
  真机/本机界面验收通过。

## Stage 27：iOS 窗口切换导航稳定性

### 目标

修复 iOS 进入新 tmux window 或切换 window 时，被瞬时 session state 误判为会话已结束，
从终端页面自动弹回 session 列表的问题。窗口状态刷新可以短暂缺失，但不得直接改变导航
层级；真正关闭 session 时仍需及时返回列表。

### 实施范围

1. 将窗口集合变化后的选择行为收敛为纯决策：保留有效选择、选择活动/首个后备窗口，或
   标记 session 暂时缺失；不在集合观察回调中直接散落导航副作用。
2. session state 暂时为空时只显示缺失状态，不自动改变导航层级。快照延迟没有可靠的
   时间上界，因此不得用固定延时推断 session 已被关闭。
3. `LiveTerminalView` 只拥有单个 pane 的流生命周期；收到 `streamEnd` 时执行一次有界
   replacement recovery，不能通过环境 `dismiss` 弹出父 session 页面。
4. 用户通过 App 成功关闭 session 时显式返回列表；外部关闭后由用户使用已有返回按钮离开
   缺失状态，不增加第二套导航状态机。
5. 保持窗口/面板选择命令、键盘输入和 Host/Relay 协议不变，不增加持久化状态或可配置延时。

### 验收标准

- 新建或切换 window 期间，即使出现空窗口快照或旧 pane 的 `streamEnd`，也不会离开终端页面；后续快照
  到达后继续显示正确窗口并保持可输入。
- 当前窗口被外部移除但同一 session 尚有窗口时，选择活动窗口或首个窗口；不会弹回列表。
- Host 断线、首次状态尚未到达或 session 被外部关闭时不隐式返回；页面保留系统返回按钮。
- App 内主动关闭 session 成功后立即返回，失败时留在原页面并展示原有错误。
- 窗口选择决策聚焦测试、完整 Swift package 测试及 iOS device build 通过，并完成真机
  新建/切换窗口验收。

## Stage 28：远程粘贴连字符参数完整性

### 目标

修复 iOS 等远程 Viewer 粘贴包含以 `-` 开头的 shell 参数时，Host 只写入参数之前内容的
问题。例如粘贴 `sudo scutil --set HostName` 必须完整到达 tmux pane，不能停在
`sudo scutil`。

### 实施范围

1. 在 Host 的统一 tmux literal 输入入口使用 `--` 终止 `send-keys` 选项解析，确保
   `--set`、`-n` 等用户文本不会被 tmux 当成命令选项。
2. 保持现有 `TmuxKey`、`SendKeystroke`、E2EE、Relay、bracketed paste 和输入 FIFO
   不变；不为 iOS 增加第二套粘贴命令或剪贴板状态。
3. 更新进程发送路径的聚焦测试，覆盖以双连字符、单连字符开头的 literal 批次，以及
   普通文本、命名按键和 delay 边界。
4. 使用独立 tmux socket 做集成验证，确认完整命令实际进入 pane；完成受影响测试、
   完整 Swift package 测试和 macOS 构建。

### 验收标准

- `sudo scutil --set HostName` 经与 iOS 相同的分段键序列后完整出现在 pane 中。
- 任何 literal 批次以 `-` 或 `--` 开头时均不会触发 tmux `invalid flag`。
- 普通文字、空格、Enter、方向键、bracketed paste 和输入顺序不回归。
- 不修改网络协议或 iOS UI；更新 Host 后旧 Viewer 仍兼容。
- 聚焦测试、完整 Swift package、`git diff --check` 与 macOS 构建通过，并完成真机粘贴验收。

## Stage 29：本地安装包依赖锁定

### 目标

确保 macOS DMG 与 iOS IPA 的零参数打包始终使用仓库已提交的 `Package.resolved`，禁止
Xcode 在打包时隐式升级依赖，使包内 source revision 能准确代表实际源码与依赖图。

### 实施范围

1. macOS 与 iOS 本地打包脚本向 Xcode 明确传入
   `-onlyUsePackageVersionsFromResolvedFile`。
2. 保持现有主 worktree 限制、缓存目录、签名、构建 stamp、source revision、产物名称和
   调用方式不变；不增加命令行参数或环境覆盖入口。
3. 使用现有锁文件完成依赖解析，确认不会修改两个 `Package.resolved`；执行 shell 语法检查
   并从主 worktree 完成一次 macOS Release DMG 构建。

### 验收标准

- 本地打包不会把 `swift-certificates`、`swift-log`、`swift-system` 等间接依赖升级到锁文件
  之外的版本。
- 两个脚本保持零参数调用，shell 语法检查通过。
- macOS DMG 构建、签名、映像和嵌入 source revision 校验通过。
- 打包前后 Git worktree 保持干净。

## Stage 30：macOS tmux window 快捷导航

### 目标

为 macOS 增加只在当前 session 的 tmux window 之间切换的原生快捷键，不把文件、Git、
浏览器 tab 混入导航，也不从终端输入链路截获按键。本地 Host 与远程 Viewer 必须复用
现有 window 点击选择语义。

### 实施范围

1. 在 macOS Window 菜单增加“上一个/下一个 Terminal Window”，默认使用 `⌥⌘←` 与
   `⌥⌘→`；增加 `⌘1` 到 `⌘9` 直接选择当前 session 中第 1 到第 9 个可用 tmux window。
2. 命令通过 scene-scoped `FocusedValue` 路由到当前 panes scene，不使用全局键盘 monitor、
   `NSEvent` 拦截或终端输入回调，避免影响 tmux、TUI、Shell 和输入法。
3. 导航顺序取统一 tab strip 的已协调视觉顺序，再过滤出当前左侧主区域的 window；跳过
   文件、Git、浏览器以及分屏右侧固定内容，首尾循环，一个 window 时无操作。
4. 本地选择复用 `TmuxService.selectWindow`，远程选择复用现有 `SelectTmuxWindow` 命令；
   切回 terminal 时清除左侧非终端 tab 选择，不改变右侧选择。
5. 提取纯导航决策并增加聚焦测试，覆盖顺序过滤、首尾循环、数字越界、右侧排除及空集合。
6. 不增加可配置快捷键、第二套 window 排序、网络协议字段或 tmux 配置。

### 验收标准

- `⌥⌘←` / `⌥⌘→` 在当前 session 的左侧 tmux window 中循环，不经过文件、Git 或浏览器。
- `⌘1` 到 `⌘9` 按视觉 window 顺序直达；不存在对应 window 时保持当前选择。
- 本地与远程选择结果和点击 tab 一致，远程断开时不崩溃、不误改 UI 为不可用 window。
- 分屏右侧内容保持不变，终端焦点和按键输入不被新命令监听器截获。
- 聚焦测试、完整 Swift package 测试、`git diff --check` 与 macOS Debug 构建通过。

## Stage 31：iOS Terminal Stream 租约与抗抖恢复

### 目标

修复 iOS 前台使用期间因 Viewer WebSocket 短暂重连、SwiftUI terminal view 重建或旧异步
任务越过连接边界，导致新 terminal stream 被旧 `StopTerminalStream` 误停并停留在
`Terminal Stream Ended` 的问题。网络抖动可以短暂延迟画面，但不得让旧连接或旧页面拥有
终止新订阅的权限。

### 实施范围

1. Viewer Relay 连接增加单调 connection generation；receive、ping、加密发送和命令等待
   都绑定创建它们的 WebSocket 与 generation。旧连接 Task 不得发送到新 socket，也不得
   清理新连接；WebSocket send 失败立即使精确当前连接进入现有重连流程。
2. `StartTerminalStream` / `StopTerminalStream` 增加可选 stream lease ID。新客户端每次 Start
   使用新 lease，Stop 只能释放同一 viewer 当前匹配的 lease；旧客户端缺少 lease 时保留
   兼容语义。
3. iOS 每个 `LiveTerminalView` 独占当前 lease 和 handler registration token。旧 view 的
   `onDisappear` 只能注销自己的 handler、停止自己的 lease，不能覆盖后继 view。
4. unexpected stream end 使用有界时间窗恢复：孤立结束自动 replacement；短时间连续失败
   达到阈值后显示人工 Reconnect。成功稳定 streaming 后恢复预算，避免“一生只自动恢复一次”。
5. Viewer keepalive 只有连续两轮没有任何入站帧才判定半开，并给各连接首轮 ping 增加稳定
   小抖动，避免同一 iPhone 上的多 Host 连接同时探测、同时断开。不增加用户配置项。
6. Host terminal stream stop 路径记录内部 reason；只有 resync 失败、pane 确认关闭等意外
   force stop 写 warning，正常 Viewer stop/disconnect 不制造日志噪声。
7. 不改变 terminal 数据格式、E2EE 内容、Relay 密文转发、tmux pane 尺寸、输入批处理及
   多 Viewer 共用底层 pane subscription 的现有语义。

### 验收标准

- 旧连接的 send/receive/ping Task 在 Viewer 重连后不能作用于新 WebSocket。
- 新 lease Start 完成后，旧 view 或旧 attempt 的 Stop 被 Host 忽略；匹配 lease 的正常 Stop
  仍释放所有权，最后一个 Viewer 离开时仍释放底层 subscription。
- 旧 view 注销 handler 不会清除同 pane 新 view 的 handler。
- 单次意外 stream end 自动恢复；稳定运行后再次发生孤立结束仍可自动恢复；短时间持续结束
  不形成无限 stop/start 循环，并显示人工 Reconnect。
- 一次 10 秒网络/主线程抖动不会同时断开所有 Host；真正半开连接在第二轮探测后进入既有重连。
- 聚焦生命周期、lease、handler、恢复策略及 keepalive 测试通过；完整 Swift package、
  `git diff --check`、macOS 与 iOS 构建通过，无新增并发隔离警告。
