# CtrlX 3.0.0 Stage 2 TODO：用户可见品牌与视觉隔离

## Stage Status

- **Status**：✅ Completed
- **Progress**：8/8 tasks
- **Dependencies**：Stage 1 ✅

## Tasks

- [x] 生成不复用 Gallager 视觉元素的 CtrlX 1024×1024 主图标。
- [x] 从主图标生成 macOS、iOS 和网站尺寸，验证无 alpha 与像素尺寸。
- [x] 替换 Mac 菜单、窗口、About、设置、错误和帮助中的用户可见品牌。
- [x] 替换 iOS 配对、设置、About 与通知中的用户可见品牌。
- [x] 替换网站品牌、CLI 示例和源码链接，移除 Gallager 生产购买/下载入口。
- [x] 增加生产 UI 旧品牌白名单检查；来源声明允许出现 Gallager。
- [x] 运行 Swift parse、资源 catalog、网站构建和相关单元测试。
- [x] 将单纯 X 优化为双滑轨 X，在不改变黑色材质风格的前提下补充 Control 语义。

## Acceptance

- [x] Mac/iOS 图标只使用 `Brand/CtrlX-AppIcon.png` 派生资产。
- [x] 普通生产 UI 不显示 Gallager 或 Ctrlx 品牌。
- [x] About/README 显示 Gallager 来源和非官方声明。
- [x] CtrlX 不链接 Gallager 的下载、付费 checkout 或更新服务。
- [x] 16–32 px 仍优先识别为 X；放大后两条滑轨和两个调节节点清晰可辨。

## Asset provenance

- **Generator**：OpenAI built-in image generation tool
- **Final master**：`Brand/CtrlX-AppIcon.png`
- **Prompt intent**：minimal black control/X mark, matte obsidian and gunmetal surfaces,
  restrained silver-gray edge highlights, no color gradient, no text, no Apple/Gallager marks,
  no watermark; retain the complete X silhouette while integrating exactly two restrained
  diagonal adjustment rails and two slider nodes to convey Control without extra lettering
