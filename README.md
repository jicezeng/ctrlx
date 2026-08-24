# CtrlX

[简体中文](README_ZH.md)

> **Your tmux, Your Agent, everywhere.**

**Multiple hosts. Any supported device.** CtrlX is a tmux-native, cross-device
terminal for viewing and controlling the tmux workspaces on any paired Mac from
another Mac or an iPhone.

CtrlX does not own the terminal lifecycle or wrap coding agents in a proprietary
session model. You keep using native `tmux` to create, attach to, and manage
sessions. CtrlX makes those existing terminals securely available on your other
devices.

<p align="center">
  <img src="docs/assets/ctrlx-architecture.svg" width="100%" alt="CtrlX keeps agents and terminals running inside persistent tmux sessions, reuses them locally, and connects Mac and iPhone viewers through an end-to-end encrypted relay." />
</p>

## Why CtrlX

### Native tmux reuse

- Discover tmux sessions, windows, and panes created from the command line.
- Attach CtrlX, a system terminal, and other tmux clients to the same session.
- Keep tasks running when the app closes, the network drops, or you switch devices.
- Preserve the native commands and update paths of Claude Code, Codex, and other
  TUIs instead of waiting for CtrlX to mirror every provider command.

### Multiple hosts, any supported device

- Keep Macs at home, at the office, and on remote networks online as Hosts.
- Use each Mac both as a Host for its local tmux server and as a Viewer for other Macs.
- View and control any paired Mac workspace from an iPhone.
- Connect every device outbound through the Relay. Remote Macs need neither a
  public IP nor an open inbound port.
- Reorder Hosts and sessions independently so a multi-machine workspace stays
  stable and recognizable.

### Agent-aware, not Agent-bound

On top of its general-purpose terminal support, CtrlX detects coding-agent states
such as working, completed, permission requested, question asked, and plan awaiting
approval. It adds notifications, quick input, a file browser, a Git workbench, a
prompt editor, and token/cost information.

Open sidecar plugins extend agent support. Without a plugin, CtrlX remains a full
tmux remote terminal rather than becoming unusable when an agent provider changes.

## What kind of connection is this?

The user-facing model is **any-device access**, or **tmux workspace roaming**: the
terminal stays on its original Mac while you move between supported devices and
continue viewing or controlling it.

This is not pure P2P. CtrlX uses an **end-to-end encrypted Relay**. Every device
opens an outbound WebSocket connection; the Relay pairs devices and routes encrypted
frames but cannot read terminal contents. This preserves direct-control ergonomics
while working across NAT, corporate networks, and remote Macs without public ingress.

| Device | Share local tmux | Control remote Macs |
| --- | --- | --- |
| CtrlX for Mac | Yes | Yes |
| CtrlX for iPhone | No | Yes |

After pairing, a Viewer shows all paired online Hosts and their sessions in one
interface. Multiple Viewers can access the same Host. tmux remains the single
source of truth for terminal state.

## Quick start

### Install CtrlX for macOS

The current build requires Apple Silicon, macOS 15 or later, and tmux:

```bash
brew install tmux
curl -fsSL https://ctrlx.zengjice.com:7001/install/mac.sh | bash
```

The installer verifies a pinned SHA-256, the app signature, and bundle metadata.
It replaces only `/Applications/CtrlX.app` and does not terminate existing tmux
sessions, windows, panes, or processes running inside panes.

The current download uses an Apple Development signature and is not notarized. It
is not a public App Store distribution.

### Reuse existing tmux sessions

Continue using standard tmux commands:

```bash
tmux new -s coding
tmux attach -t coding
```

After CtrlX starts, these sessions appear directly under Local. Install and pair
CtrlX on another Mac, and that Mac appears as a separate Host on both Mac and
iPhone Viewers. No CtrlX-specific session needs to be created.

### Pair an iPhone or another Mac

1. Keep CtrlX running on the Host Mac and generate a pairing code.
2. Connect the Viewer to the same Relay and complete pairing with that code.
3. Open the Host and choose any tmux session, window, and pane.

The iOS app currently requires a locally signed Xcode build. Background push also
requires APNs credentials matching that iOS build on the Relay. Foreground terminal
access and live state synchronization work without APNs.

## Security and self-hosting

- Terminal frames are end-to-end encrypted between Host and Viewer.
- The Relay handles pairing metadata and ciphertext routing but cannot decrypt
  terminal contents.
- Self-hosting requires no CtrlX account, subscription, or third-party overlay network.
- Each Host makes outbound connections only; tmux, SSH, and app ports remain private.
- Optional APNs support is used for background notifications, not the live terminal path.

See [Self-hosting CtrlX Relay](docs/self-hosting.md) to deploy a Relay and the
[Relay monitoring runbook](docs/monitoring.md) for operational guidance.

## Architecture

| Component | Responsibility | Source |
| --- | --- | --- |
| CtrlX for Mac | Local tmux Host, desktop Viewer, agent integration, and workbench | `ClaudeSpyPackage/Sources/ClaudeSpyServerFeature` |
| CtrlX Relay | Pairing, encrypted WebSocket routing, and optional APNs delivery | `ClaudeSpyPackage/Sources/ClaudeSpyExternalServer` |
| CtrlX for iOS | Mobile Viewer, terminal input, and agent actions | `ClaudeSpyPackage/Sources/ClaudeSpyFeature` |

Internal Swift targets and modules retain their historical `ClaudeSpy*` names.
They are implementation details left stable to reduce meaningless upstream merge
conflicts.

## Build from source

Building requires a recent Xcode, Swift 6.3 or later, and macOS 15 or later.

Open `ClaudeSpy.xcworkspace` and build:

- `ClaudeSpyServer` for the macOS app.
- `ClaudeSpy` for the iOS app.

Start a local Relay:

```bash
./sbin/auto-env.sh
./sbin/start_server.sh
```

Run Swift package tests:

```bash
swift test --package-path ClaudeSpyPackage
```

Release artifacts must be built from a clean primary worktree with the checked-in
packaging scripts. Signing overrides and credentials belong only in ignored local
configuration files.

The private macOS download endpoint is served by Nginx on the home Mac. Build a
DMG locally, then publish it over SSH and verify the public bytes with:

```bash
./scripts/package-local-macos.sh
./deploy2home.sh
```

See [RELEASE.md](RELEASE.md) for the formal signed/notarized release path and
the home publication guarantees.

## Corresponding source for binaries

Every published CtrlX binary and hosted Relay version must identify an immutable
Git tag and commit containing its complete corresponding source and build scripts:

```text
Release: v3.0.0
Binary: CtrlX-3.0.0.dmg
Source: refs/tags/v3.0.0
Commit: <full Git commit>
License: GNU AGPL-3.0
```

The hosted Relay exposes the same information through `/version` and `/source`.
A link to a moving development branch alone is not sufficient corresponding source.

## Origin and license

CtrlX is an independent distribution based on
[Gallager](https://github.com/gpambrozio/Gallager), with baseline commit
`919c7772928531d4d0bb266bdf275691d361901e` dated 2026-08-14. CtrlX is maintained
by ZengJice and is not affiliated with or endorsed by the Gallager project.

The repository retains the complete Git history and original copyright notices.
CtrlX is distributed under [GNU AGPL-3.0](LICENSE). If you provide a modified Relay
over a network, you must offer users the complete corresponding source for that
running version. See [NOTICE.md](NOTICE.md), [MODIFICATIONS.md](MODIFICATIONS.md),
and [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

The CtrlX 3.0.0 independent-distribution work is recorded in the
[implementation plan](docs/v3.0.0/IMPLEMENTATION_PLAN.md).
