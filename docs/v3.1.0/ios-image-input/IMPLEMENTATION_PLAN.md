# CtrlX 3.1.0：iOS 图片输入

## 问题

iOS Viewer 目前只能向终端发送键盘和文本输入。用户无法从照片中选择图片并交给远端
Agent；macOS Viewer 已有图片粘贴能力，但这条能力尚未暴露给 iOS。

## 设计

1. iOS 当前 window 的工具栏提供系统照片选择入口，一次选择一张图片。
2. 图片读取完成后在后台规范化为 PNG/JPEG；超过 Relay 预算时逐级缩放、压缩。
3. 继续使用现有 `SendDroppedFiles` E2EE 命令。Host 将图片保存到 `$TMPDIR/ctrlx-drop-*`
   并把 shell-safe 路径 bracketed-paste 到当前 pane。
4. 选择图片时固定目标 pane；异步处理期间切换 pane 不允许把图片误投到新 pane。
5. 上传期间禁用重复选择并显示进度；读取、压缩、断线和 Host 拒绝均显示明确错误。
6. 不自动发送 Enter。Agent 或 shell 只收到一个本机可读图片路径，由用户决定何时提交。

## 实施范围

- 将 macOS 已验证的图片规范化器下沉到 `CtrlxCommon`，供 macOS/iOS 共用。
- 在 iOS `WindowLayoutView` 接入 `PhotosPicker`、上传生命周期和错误反馈。
- 增加图片格式识别、透传、压缩和无效输入的纯逻辑测试。
- 验证共享 Swift 测试、macOS 构建和无签名 iPhoneOS arm64 构建。

## 非目标

- 不增加多图、文件选择、相机拍摄或图片编辑。
- 不读取整个照片库，也不新增照片库权限声明。
- 不修改 Relay 协议、部署配置、Host 落盘规则或 tmux 输入语义。
- 不把图片直接编码为终端 escape sequence，也不自动执行 Agent prompt。

## 验收标准

- iOS 可从照片中选择一张 PNG、JPEG 或 HEIC 图片并投递到当前 pane。
- Host 收到的路径指向可读取的 PNG/JPEG 文件，路径以一次 bracketed paste 写入且不带 Enter。
- 大图自动压缩到 `SendDroppedFiles.maxRawBytes`；无法压缩时不发送并提示原因。
- 读取或上传期间不能重复发送；页面退出会取消未完成任务。
- 多 pane 场景固定发送到选择图片时的 active pane，不随之后的焦点切换漂移。
- 断线、pane 不存在和网络失败均结束 loading，不留下不可恢复状态。
- 现有 macOS 图片粘贴行为与传输协议保持兼容。

## Stage 2：多入口与发送前确认

### 目标

在 Stage 1 单张相册图片的基础上，补齐 iOS 常用图片来源，并在上传前给用户
一次明确的确认机会。

### 实施范围

1. 单一工具栏入口提供相册、文件、相机和剪贴板图片。
2. 相册和文件一次最多选择 5 张；相机和剪贴板每次加入 1 张。
3. 图片在后台统一规范化；多图共享现有 512 KiB Relay 原始数据预算。
4. 发送前展示缩略图、大小和删除操作；用户明确点击发送后才上传。
5. 打开图片入口时固定目标 pane，选择、预览或压缩期间的焦点变化不能改变投递目标。
6. 继续使用 `SendDroppedFiles`，每张图片作为一次独立 paste 按顺序投递，
   使 Codex 等 TUI 能识别为 `Image #N` 附件；不修改 E2EE wire model、Relay 或 Host。

### 非目标

- 不导入视频、PDF 或任意文件。
- 不增加图片编辑、裁剪、标注或压缩质量选项。
- 不为多图新增分片协议；超出现有预算时使用共享压缩策略。
- 不自动发送 Enter，不代替用户提交 Agent prompt。

### 验收标准

- 四种入口都能将有效图片加入预览，无效输入显示可理解错误。
- 多图可在预览中删除，总大小不超过 `SendDroppedFiles.maxRawBytes`。
- 点击发送会按顺序将每张图片以一次独立 bracketed paste 写入；
  支持图片附件的 TUI 显示 `Image #N`，普通终端中的多个路径保持空格分隔。
- 取消选择、关闭预览或离开 window 均不留下持续 loading 或误发任务。
- 无相机设备时禁用拍摄入口；相机权限由系统仅在用户选择拍摄时请求。
