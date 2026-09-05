# iOS Agent 监控前台续期 Stage 7 TODO

## Stage Status

- **Status**: ✅ Completed
- **Progress**: 6/6 tasks
- **Dependencies**: Stage 6 ✅

## Tasks

- [x] 完成前后台转换和租约预算审计
- [x] 为每个运行租约保存可续期的进度上限
- [x] 实现真实后台到前台时的原任务续期
- [x] 补充策略测试并完成完整测试
- [x] 完成代码审查、iPhoneOS 构建和真机安装
- [x] 完成真机行为验收

## Blockers

- 当前无阻塞项。

## Verification

- Agent 后台监控定向测试：12 项通过。
- `CtrlxPackage` 完整测试：1757 项、255 个 suite 通过。
- iPhoneOS Debug 无签名构建通过。
- 已签名、深度校验并覆盖安装到 `ZengJice iPhone`，build
  `20260818-stage7`；App 启动成功。
- 真机续期行为验收通过。
