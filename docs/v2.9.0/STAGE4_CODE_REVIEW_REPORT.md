# Stage 4 Code Review Report

## Scope

- macOS 本地 tmux pane 状态发布与 Host→Viewer session-state 快照。
- 本地按键 FIFO、tmux control 写入、pipe 回显与 SwiftTerm feed 调度。
- URL 装饰、工作状态动画和 agent 进程扫描的后台开销。
- 新增指标、并发边界和聚焦测试。

## Findings

### Critical / High / Medium

- None。

### Low

- 已修复：输入回显可能先于 tmux command acknowledgement；trace 现在等待 acknowledgement
  与 feed 均到达后才释放，不因正常乱序丢失尾段指标。
- 已修复：tmux 重配置时，旧 process-snapshot Task 可能覆盖新配置缓存；增加 generation 校验，
  旧 Task 只能退出，不能清理或发布新 generation 的状态。
- 已修复：git branch 探测跨 `await` 后可能写回已经切换目录的 pane；写回前同时校验 pane
  仍存在且 `currentPath` 未变化。
- 已修复：正常 view teardown 的待发输入一度会计入 transport failure；现区分 discard 与真实失败。
- 已修复：Observation no-op 测试依赖真实 zsh 启动时序，存在元数据自然变化造成的假失败；改用
  固定 tmux 输出，测试只验证目标语义。

## Correctness Checks

- pane metadata、attached sessions、error 和 background refresh loading 只在语义变化时发布。
- Viewer snapshot 只复制当前 Host model 并注入 editor state，不触发 tmux refresh 或回写可观察状态。
- 按键仍通过单一 FIFO；同 runloop 的 Meta/Option 合并、raw input 顺序和 process fallback 均保留。
- terminal feed 保持字节顺序；无输入时使用 2ms 有界时间片，有待发输入时缩小到 4KB 并逐批
  `yield`，没有 speculative local echo 或第二条发送队列。
- 输入 trace 上限 256、寿命 5 秒；输出前必须已观察到 tmux write，正常 teardown 不计失败。
- URL underline 最多 10Hz 重扫，且 content generation 与 viewport/layout 均未变化时不做扫描。
- agent process snapshot 只短期复用，重配置会取消并隔离旧 generation；取消不记录误导性 warning。
- 未修改 Relay wire model、tmux session 数据、用户配置或 iOS 输入逻辑。

## Verification

- 聚焦 Swift Testing：5 suites、41 tests passed。
- macOS `CtrlxServer` Debug 全量构建和 Apple Development 签名 Release 构建通过。
- Release `f42f066e6852` 已覆盖安装；App 返回 `ready` / `pong`，安装前后 tmux pane 清单一致。
- SwiftFormat 对本 Stage 小型文件通过；大型文件没有新增命中当前 formatter 的变更行。
- `git diff --check` 通过。

## Residual Risk

- pipe output 是无 command ID 的字节流，input→output/feed 指标只能做同 pane、write 之后的
  best-effort 关联；该限制已明确记录，不能用更多状态伪装成精确因果链。
- 自动化测试证明调度、顺序与边界；本 Stage 未补做受控的同场景前后 profiling，用户在签名
  Release 覆盖安装后明确要求合入，本文不把缺失的运行时样本描述成已验证结论。

## Assessment

Approved and merged。未发现 P3 及以上遗留问题。实现没有增加协议、配置面或并行输入架构；
Stage 4 已按用户明确指令合入 `develop/v2.9.0`。
