---
name: create-agent-plugin
description: Create or debug a CtrlX sidecar integration for a coding agent, including its event bridge and distribution bundle. Not for routine use of installed plugins.
---

# CtrlX agent sidecar

A sidecar is a standalone executable spawned by CtrlX. It translates an agent's
events into pane/session state over stdio RPC; no changes to the Mac app are
needed. Start from the bundled Python template, not handwritten framing.

## Essential contract

- Manifest and hook-ingress keys are **snake_case**; stdio RPC keys are
  **camelCase** (`pluginID`, `sessionID`, `tmuxPane`). These are different channels.
- Every event includes `pluginID`, `sessionID` and **`appActions: []`** (or actions).
  Missing required keys makes the host drop the event.
- Stdio uses `Content-Length` framing; ingress uses a 4-byte big-endian length.
  Keep stdout RPC-only; use structured `log` messages or stderr for diagnostics.
- Preserve the agent session ID and `TMUX_PANE` mapping. `sessionEnded.sessionID`
  is the **pane ID**, not the agent ID. Do not let child-agent lifecycle events
  mark the root pane done.
- Use the supplied enum helpers; working is `{"working": {}}`, not `"working"`.
  Optional forms/keys have additional tagged-object shapes; read their reference.

## Workflow

1. Establish the agent's real event surface (shell hooks, native event bus, or
   process detection), sample payloads, process name and launch command. Ask only
   for missing information; do not assume every agent implements Claude hooks.
2. In a workspace directory, copy [sidecar.py](assets/template/sidecar.py) to
   `bin/sidecar` and [plugin.json](assets/template/plugin.json) to the root. Make
   `bin/sidecar` executable. Set identity, process names and launch configuration;
   the eventual install directory name must equal the manifest ID.
3. Adapt `handle_translate_event` and its `EDIT HERE` blocks. Use stable session
   IDs, preserve pane/project context, return `null` for irrelevant events and
   include `appActions`. Read [events](references/events.md) for state/lifecycle
   shapes; only add notifications when the user should actually be alerted.
4. Wire the bridge using [integration](references/integration.md). Shell-hook
   agents can reuse [hook.py](assets/template/hook.py); native event buses need
   their own bridge. Implement actual install/status/uninstall behavior: the
   starter's install handler is a stub, not proof that hooks were registered.
5. Test the local executable with framed initialize/translate/unknown-method/EOF
   cases and representative agent payloads. Verify IDs, casing and event shapes.
   For an authorized live install, verify a real event reaches the intended pane;
   follow [installation and distribution](references/distribution-and-settings.md).

Creating code does not by itself authorize installing into the live plugin
folder, restarting CtrlX, changing global agent config or publishing a bundle.

## Read only the contract needed

| Task | Reference |
|---|---|
| Manifest, framing, RPC methods, startup/crash failures | [Transport and manifest](references/protocol-reference.md) |
| State transitions, session end, event decoding | [Events](references/events.md) |
| Hook/event-bus wiring and event order | [Integration](references/integration.md) |
| Permission/question forms, `deliver_response`, `send_keys` | [Forms and input](references/forms-and-input.md) |
| Folder-drop/ZIP/URL install, trust, `configRoot`, settings | [Distribution and settings](references/distribution-and-settings.md) |
| Token/cost/latency meter | [Telemetry](references/telemetry.md) |

These references are self-contained within the skill; the CtrlX repository is
not required. Keep optional forms and telemetry out of a basic monitoring task.
