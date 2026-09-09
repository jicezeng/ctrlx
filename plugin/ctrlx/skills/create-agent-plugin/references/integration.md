# Agent bridge and ingress

Read when wiring hooks or an agent-native event bus. Verify the agent's actual
event API and sample payloads first; the starter's event names are illustrative.

## 8. Hook ingress channel

Something running in your agent's process must forward events to CtrlX through
the ingress socket — a **different** channel from the stdio transport. What that
"something" is depends on the agent:

- **Shell hooks** (Claude Code, Codex): the agent runs a script per event. Use the
  bundled `assets/template/hook.py` as the bridge; your `install` registers it.
- **Agent-native plugin / event bus** (for agents that have *removed* shell hooks):
  the agent loads a small plugin, written in its own plugin format, that subscribes
  to its event bus and forwards frames. The bridge bakes in the socket path + plugin
  id at install time (the agent process does not inherit CtrlX's env).
- **No event surface at all:** the agent is only process-detected (`process_names`)
  and you may need little beyond `initialize`.

Either way the frame format is identical:

### Frame format: 4-byte big-endian length prefix (NOT Content-Length)

```
[UInt32 big-endian byte count][JSON body bytes]
```

Body (snake_case):
```json
{
  "plugin_id": "my-agent",
  "context": { "TMUX_PANE": "%4", "CLAUDE_PROJECT_DIR": "/path" },
  "payload": { "event": "turn_start", "session_id": "abc-123" }
}
```

- `plugin_id` must equal `CTRLX_PLUGIN_ID` — it routes the frame to your sidecar.
- `context.TMUX_PANE` must be present (pane routing). Add any other env keys your
  `translate_event` reads.
- `payload` is your agent's raw hook event; it arrives at `translate_event` as the
  already-parsed `params.payload`.

Your sidecar's `install` should copy and register a bridge in the agent's config.
Use the bundled [hook.py](../assets/template/hook.py) for a working shell-hook bridge.

## Routing and ordering

Preserve a stable agent session ID and `context.TMUX_PANE`. For agents with
subagents, only root lifecycle events should change the pane's working/done
state; child prompts that block the root TUI need root-session routing.
If the agent fires hooks concurrently, serialize forwarding so start/busy/done
cannot overtake each other. Await the graceful-exit frame before process exit;
use native lifecycle events when available, synthetic ones only when missing.

`install`, `uninstall` and `install_status` must honor `configRoot` and preserve
unrelated agent configuration; see [settings](distribution-and-settings.md).
Bake the actual ingress socket and plugin ID into the installed bridge instead
of assuming the agent inherits the sidecar environment.
