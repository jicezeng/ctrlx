# Stage 2 Code Review Report

## Review Scope

- Range: `0ce4988..HEAD`
- iOS 相册多选、图片文件、相机和剪贴板入口
- 发送前缩略图、大小、删除和确认交互
- 多图共享 Relay 预算、E2EE `SendDroppedFiles` 复用与目标 pane 固定
- iOS 剪贴板图片读取与相机权限配置

## Findings

### P2 / Resolved：平均分配会浪费小图未使用的预算

初版在批次总大小超限后，直接将总预算平分给每张图。当批次由多张小图和
一张大图组成时，小图只使用少量份额，大图却仍只能使用平均份额；这会造成不必要的
画质损失，甚至拒绝实际可以装入 512 KiB 的批次。

**Resolution**：先固定已低于当前公平份额的图片，再将它们未使用的字节重新分配
给剩余图片。新增“多张小图 + 一张大图”回归，验证大图可使用高于平均份额的
剩余预算，同时批次总大小仍不超限。

### P2 / Resolved：预览 sheet 弹出时清空图片草稿

工具栏 view 在预览 sheet 替换层级时会收到 `onDisappear`。初版将该回调直接连接到
销毁性清理，导致预览页打开后显示 `0 images`。

**Resolution**：仅在没有任何图片来源或预览界面处于展示状态时执行退出清理。
真正离开终端仍会取消任务并释放草稿，正常 sheet 生命周期不再误删状态。

### P2 / Resolved：多图合并 paste 破坏 TUI 图片附件识别

Codex TUI 仅在一次 paste 的完整内容是单个有效图片路径时创建 `Image #N` 附件。
初版把多个路径合并到一次 bracketed paste，导致 TUI 将其作为普通绝对路径文本显示。

**Resolution**：保留共享 512 KiB 批次预算，但按顺序发送单文件 `SendDroppedFiles`
命令，使每张图片维持 Stage 1 的单路径 paste 语义。图片间单独发送一个空格，保证
不支持附件的普通终端仍能正确分隔路径；失败时只保留尚未确认发送的图片供重试。

## Verification

- `swift test --package-path CtrlxPackage --filter RelayImagePreparerTests`：9/9 通过。
- iPhoneOS arm64 Debug 无签名构建：通过。
- macOS arm64 Debug 无签名构建：通过。
- `NSCameraUsageDescription` 已进入 iOS 目标构建设置。
- iPhone 真机已验收单图及 3/5 张多图；预览数量正确，Codex TUI 生成
  独立 `Image #N` 附件，Agent 可分别读取图片。
- `git diff --check`：通过。
- SwiftLint 未安装；Xcode 仅报告既有构建脚本提示。

## Design Review

- 所有入口共用一套规范化、预览和发送状态，未按来源复制上传实现。
- 目标 pane 在打开系统选择器前捕获，异步读取、压缩和预览不会重定向。
- 取消任务通过 operation ID 丢弃过期结果，旧任务不能覆盖新页面状态。
- 剪贴板仅在用户点击“Paste Image”时读取；相册继续使用系统 PhotosPicker。
- 多图按顺序复用单文件 `SendDroppedFiles` E2EE 命令，Relay 和 Host 协议无变更，
  并兼容尚未升级的 Host。

## Assessment

代码审查通过，无剩余 P1、P2 或 P3。Stage 2 的编译、自动化验证与
iPhone 真机验收均已完成，可合入 `develop/v3.1.0`。
