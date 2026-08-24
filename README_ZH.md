# CtrlX

[English](README.md)

> **Your tmux, Your Agent, everywhere.**

**多主机，全端访问。** CtrlX 是一个以 tmux 为核心的跨设备终端，让你在任意一台 Mac
或 iPhone 上，查看并控制任意一台已配对 Mac 的 tmux 工作区。

CtrlX 不接管终端生命周期，也不把 Coding Agent 包装进自己的会话模型。你仍然使用原生
`tmux` 创建、挂载和管理 session；CtrlX 只是让这些已经存在的终端安全地出现在其他设备上。

<p align="center">
  <img src="docs/assets/ctrlx-architecture.svg" width="100%" alt="CtrlX 让 Agent 和普通终端持续运行在 tmux 中，支持本地复用，并通过端到端加密 Relay 连接 Mac 和 iPhone Viewer。" />
</p>

## 为什么选择 CtrlX

### tmux 原生复用

- 直接发现命令行创建的 tmux session、window 和 pane。
- CtrlX、系统终端和其他 tmux client 可以连接同一个会话。
- 关闭 App、切换设备或网络断开不会结束 tmux 中的任务。
- Claude Code、Codex 或其他 TUI 保留完整原生命令和更新能力，不依赖 CtrlX 适配 provider
  的每一个内置命令。

### 多主机，全端访问

- 家里、办公室和异地的多台 Mac 可以同时作为 Host 上线。
- Mac 既能共享本机 tmux，也能作为 Viewer 控制其他 Mac。
- iPhone 可以查看和控制任意已配对 Mac 上的 tmux 工作区。
- 每台设备只需主动连接 Relay；远端 Mac 不需要公网 IP，也不需要开放入站端口。
- Host 和 session 顺序可分别调整，让多机器工作区保持稳定、可辨认。

### Agent 感知，而不是 Agent 绑定

CtrlX 在普通终端复用之上识别 Coding Agent 的运行、完成、权限请求、提问和计划审批状态，
并提供通知、快捷输入、文件浏览、Git workbench、Prompt 编辑和 token/cost 信息。Agent 支持
由开放的 sidecar plugin 扩展；没有插件时，CtrlX 仍然是完整的 tmux 远程终端。

## 这是什么连接模式？

面向使用者，我们称它为 **全端访问（Any-device access）**，也可以理解为 **tmux 工作区漫游**：
终端留在原来的 Mac 上，但你可以换一台设备继续查看和操作。

它不是纯 P2P。技术上，CtrlX 使用 **端到端加密 Relay**：所有设备主动建立出站 WebSocket，
Relay 负责配对和转发密文，但不能读取终端内容。这种架构保留了 P2P 般的直接控制体验，
同时适用于 NAT、公司网络和没有公网入口的远端 Mac。

| 设备 | 共享本机 tmux | 控制远端 Mac |
| --- | --- | --- |
| CtrlX for Mac | ✅ | ✅ |
| CtrlX for iPhone | — | ✅ |

完成配对后，Viewer 会在一个界面中看到所有在线 Host 及其 session。多台 Viewer 也可以访问
同一个 Host；tmux 始终是终端状态的唯一事实来源。

## 快速开始

### 安装 macOS 版

要求 Apple Silicon、macOS 15 或更新版本，并已安装 tmux：

```bash
brew install tmux
curl -fsSL https://ctrlx.zengjice.com:7001/install/mac.sh | bash
```

安装器会校验固定 SHA-256、App 签名和 bundle metadata，只替换
`/Applications/CtrlX.app`，不会结束已有 tmux session、window、pane 或 pane 内进程。

当前下载包使用 Apple Development 签名，尚未 notarize，不是面向公众的 App Store 发行包。

### 复用现有 tmux 会话

继续使用熟悉的 tmux 命令：

```bash
tmux new -s coding
tmux attach -t coding
```

启动 CtrlX 后，这些 session 会直接出现在 Local 列表中。远端 Mac 安装并完成配对后，会作为
独立 Host 出现在 Mac 和 iPhone Viewer 中，无需为它重新创建 CtrlX 专用会话。

### iPhone 与其他 Mac

1. 在 Host Mac 上保持 CtrlX 运行并生成配对码。
2. 让 Viewer 连接同一个 Relay，并用配对码完成一次配对。
3. 从 Host 列表进入对应机器，选择任意 tmux session、window 和 pane。

iOS 目前需要使用 Xcode 签名安装；后台推送还要求 Relay 配置匹配该 iOS 构建的 APNs 凭据。
没有 APNs 时，前台远程终端和实时状态同步仍可正常工作。

## 安全与自托管

- 终端帧在 Host 与 Viewer 之间端到端加密。
- Relay 只处理配对元数据和密文路由，不能解密终端内容。
- 自托管版本不要求 CtrlX 账号、订阅或外部组网服务。
- 每台 Host 只建立出站连接，不必暴露本机 tmux、SSH 或 App 端口。
- 可选 APNs 只用于后台通知，不影响实时终端链路。

部署自己的 Relay 请阅读 [Self-hosting CtrlX Relay](docs/self-hosting.md)，运行监控说明见
[Relay monitoring runbook](docs/monitoring.md)。

## 架构

| 组件 | 职责 | 源码 |
| --- | --- | --- |
| CtrlX for Mac | 本机 tmux Host、桌面 Viewer、Agent 集成和 workbench | `ClaudeSpyPackage/Sources/ClaudeSpyServerFeature` |
| CtrlX Relay | 配对、加密 WebSocket 路由和可选 APNs 分发 | `ClaudeSpyPackage/Sources/ClaudeSpyExternalServer` |
| CtrlX for iOS | 移动 Viewer、终端输入和 Agent 操作 | `ClaudeSpyPackage/Sources/ClaudeSpyFeature` |

内部 Swift target 和 module 仍保留历史 `ClaudeSpy*` 名称。它们只是实现细节，用于降低与上游
同步时的无意义改名风险。

## 从源码构建

要求近期 Xcode、Swift 6.3 或更新版本，以及 macOS 15 或更新版本。

打开 `ClaudeSpy.xcworkspace`：

- 构建 `ClaudeSpyServer` 获得 macOS App。
- 构建 `ClaudeSpy` 获得 iOS App。

本地启动 Relay：

```bash
./sbin/auto-env.sh
./sbin/start_server.sh
```

运行 Swift package 测试：

```bash
swift test --package-path ClaudeSpyPackage
```

正式产物必须从干净的 primary worktree 使用仓库内打包脚本构建。签名覆盖项和凭据只允许放在
Git 忽略的本地配置文件中。

私有 macOS 下载入口由 home Mac 上的 Nginx 提供。本机生成 DMG 后，通过 SSH 推送到 home
并从公网回读校验，不再复制到本机的 `happy-nginx` 目录：

```bash
./scripts/package-local-macos.sh
./deploy2home.sh
```

正式签名、公证流程及 home 发布的校验保证见 [RELEASE.md](RELEASE.md)。

## 二进制对应源码

每个发布的 CtrlX 二进制和托管 Relay 都必须指向包含完整对应源码与构建脚本的不可变 Git tag
和 commit：

```text
Release: v3.0.0
Binary: CtrlX-3.0.0.dmg
Source: refs/tags/v3.0.0
Commit: <full Git commit>
License: GNU AGPL-3.0
```

托管 Relay 通过 `/version` 和 `/source` 暴露相同信息；只链接到会移动的开发分支不构成完整
的对应源码说明。

## 来源与许可证

CtrlX 是基于 [Gallager](https://github.com/gpambrozio/Gallager) 的独立发行版，基线为
2026-08-14 的 commit `919c7772928531d4d0bb266bdf275691d361901e`。CtrlX 由
ZengJice 维护，与 Gallager 项目不存在隶属或官方背书关系。

仓库保留完整 Git 历史和原始版权声明，并以 [GNU AGPL-3.0](LICENSE) 发布。如果通过网络
提供修改后的 Relay，必须向用户提供该运行版本的完整对应源码。另见 [NOTICE.md](NOTICE.md)、
[MODIFICATIONS.md](MODIFICATIONS.md) 和 [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)。

CtrlX 3.0.0 独立发行工作记录在
[实施计划](docs/v3.0.0/IMPLEMENTATION_PLAN.md) 中。
