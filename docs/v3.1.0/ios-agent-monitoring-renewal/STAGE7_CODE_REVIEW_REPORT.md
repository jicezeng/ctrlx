# CtrlX 3.1.0 Stage 7 Code Review Report

## Review Scope

- iOS scene 生命周期到 Agent 监控租约的状态转换
- continued-processing 进度预算续期
- 现有系统任务、卡片、Agent pane 状态和连接状态的所有权

## Findings

- P1：无
- P2：无
- P3：无

## Verified Boundaries

- 只有已观察到 `.background` 后的 `.active` 才会续期；首次启动、重复
  active 和 `inactive` 过渡不会续期。
- 续期只更新现有任务的 `Progress.totalUnitCount`，没有提交第二个
  `BGContinuedProcessingTaskRequest`，因此不会主动叠加系统卡片。
- 已失效的租约不会由 scene callback 重建；仍由下一次有效 Agent 输入恢复。
- 租约的原始 `startedAt`、pane phase、输入累计和连接节流状态均不重置。
- 进度上限使用溢出保护；计时循环始终以当前会话上限为终止条件。

## Verification

- Agent 后台监控定向测试：12 项通过
- `CtrlxPackage` 完整测试：1757 项、255 个 suite 通过
- iPhoneOS Debug 构建、手工签名和深度校验：通过
- iPhone build `20260818-stage7`：安装和启动通过
- `git diff --check`：通过

## Residual Risk

- iOS 仍可因系统资源策略提前终止 continued-processing task；扩大 CtrlX 的
  进度预算不能覆盖该系统边界。
- 续期会降低系统卡片显示的完成比例，因为同一任务的总进度增加。这是以
  不创建第二张卡片换取续期的预期视觉结果。

## Decision

代码审查和真机行为验收通过，没有 P1、P2 或 P3 问题，可合入
`develop/v3.1.0`。
