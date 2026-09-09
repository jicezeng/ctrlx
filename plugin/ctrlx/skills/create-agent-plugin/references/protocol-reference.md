# Sidecar transport and manifest

Read when defining a manifest, changing RPC framing, launch/project methods, or
debugging startup. The Python template already implements framing and dispatch.
Manifest/ingress use snake_case; stdio RPC uses camelCase.

Related contracts (read only for the feature being implemented):

- [Events, states and session end](events.md)
- [Permission/question forms and keystrokes](forms-and-input.md)
- [Agent hooks and ingress bridge](integration.md)
- [Installation, distribution and settings](distribution-and-settings.md)
- [Token/cost/latency telemetry](telemetry.md)

## 1. Channel casing

CtrlX uses three channels with different framing and key conventions:

| Channel | Direction | Casing | Example keys |
|---|---|---|---|
| `plugin.json` manifest | on disk | **snake_case** | `schema_version`, `display_name`, `short_name`, `process_names` |
| Ingress **socket** frame | your hook → app | **snake_case** | `plugin_id`, `context`, `payload` |
| Stdio **transport** RPC | app ↔ sidecar | **camelCase** | `pluginID`, `sessionID`, `tmuxPane`, `pluginRoot` |

Stdio uses Swift property names verbatim (`pluginID`, not `plugin_id`). Replacing
a required camelCase key with a snake_case key makes the whole event fail to decode.

## 2. Plugin layout & manifest schema

A plugin is a directory containing a `plugin.json` and an executable:

```
~/.ctrlx/plugins/my-agent/
├── plugin.json        # manifest (snake_case)
├── bin/
│   └── sidecar        # executable, chmod +x
└── assets/
    └── icon.png       # optional
```

### Manifest keys (snake_case)

| Key | Type | Required | Notes |
|-----|------|----------|-------|
| `schema_version` | int | no (default 1) | Must be `1` |
| `id` | string | **yes** | Path component — see ID rules |
| `display_name` | string | **yes** | Shown in Settings → Agents |
| `short_name` | string | **yes** | Pane badge label |
| `version` | string | no (default `"0.0.0"`) | Semver |
| `process_names` | [string] | no (default `[]`) | Process base-names for pane auto-detection |
| `runtime` | string | **yes** | Must be `"sidecar"` |
| `sidecar.executable` | string | **yes** | Path to binary under the plugin root (e.g. `"bin/sidecar"`) |
| `sidecar.args` | [string] | no (default `[]`) | Extra argv passed to the executable |
| `sidecar.default_config_root` | string | no | The agent's default config location, shown as the non-removable root row in Settings → Agents (e.g. `"~/.config/my-agent"`). Purely presentational — when absent the UI falls back to `~`. `install` still receives `configRoot: null` for this default row (see [§13](distribution-and-settings.md)). |
| `ui.icon` | string | no | Relative path to an icon asset |
| `ui.color` | string | no | Accent hex, e.g. `"#4A90E2"` (default `"#888888"`) |
| `publisher` | string | no | Human-readable publisher name |
| `manifest_url` | string | no | HTTPS URL of this manifest (remote install) |
| `bundle_url` | string | no | HTTPS URL of the zip bundle (remote install) |
| `bundle_sha256` | string | no | Lowercase hex SHA-256 of the bundle (remote install) |
| `capabilities.rich_pane_detection` | bool | no (default false) | Opt in to the `detect_pane` RPC |
| `capabilities.modal_prompts` | bool | no (default false) | Opt in to the host `prompt_user` modal |
| `otlp.namespace` | string | no | OTLP event-name namespace, no trailing dot (e.g. `"my-agent"`). Declaring it routes `<namespace>.<token_event>` log records into the per-session token/cost/latency meter ([§11a](telemetry.md)). `claude_code` / `codex` cannot be claimed. |
| `otlp.token_event` | string | no (default `"api_request"`) | The namespace-stripped event name carrying the token/latency/model attributes ([§11a](telemetry.md)) |

### ID rules

`id` is a filesystem path component and must:

- match `^[a-z0-9][a-z0-9._-]*$` (lowercase letters, digits, `.`, `_`, `-`; first char alphanumeric),
- not contain `..`,
- be ≤ 128 chars,
- **exactly equal the directory name** under `~/.ctrlx/plugins/`.

## 3. Stdio JSON-RPC transport

### Framing (LSP-style Content-Length)

Every message, both directions, is:

```
Content-Length: <byte-count-of-body>\r\n
\r\n
<JSON body>
```

ASCII header, terminated by `\r\n\r\n`; `Content-Length` counts the body bytes
only. CtrlX caps the header at 16 KiB and the body at 32 MiB. (This framing is
ONLY for stdio — the ingress socket uses a different format, see [§8](integration.md).)

### Envelope

| Field | Type | Present on |
|-------|------|------------|
| `id` | string | requests and their responses |
| `method` | string | requests and notifications |
| `params` | any JSON | requests and notifications |
| `result` | any JSON | successful responses |
| `error` | `{code, message}` | error responses |

- **Request** = `id` + `method`. Expects a response.
- **Notification** = `method`, no `id`. No response.
- **Response** = `id`, no `method`. **Must echo the request's exact `id`** — a
  response with an unknown `id` is silently discarded.

Error response:
```json
{ "id": "abc-123", "error": { "code": "method_not_found", "message": "Unknown method: foo" } }
```

Respond to **every** request you receive. For methods you don't implement, reply
with a `method_not_found` error (don't leave the request hanging — the app's RPC
has a per-call timeout, but a silent drop wastes it).

## 4. App → Sidecar requests

All are **requests** — the app waits for a response. `params` keys are camelCase.

| Method | `params` | Respond with |
|--------|----------|--------------|
| `initialize` | `PluginEnvWire` (below) | `{}` (any value). Sent once at startup AND after every crash-restart. Respond before doing anything else. |
| `translate_event` | `IngressFrameWire`: `{pluginID, context, payload}` | A `PluginEvent` ([§6](events.md)), or `null` to ignore. **The core method.** |
| `command_for_launch` | `{projectPath}` | `{command, args, env}` or `null` |
| `install` | `{configRoot: string\|null}` | `InstallResult`: `{"installed":{"message":"…"}}` or `{"alreadyInstalled":{}}` |
| `uninstall` | `{configRoot: string\|null}` | `{}` |
| `install_status` | `{configRoot: string\|null}` | `PluginInstallStatus`: `{"installed":{"version":"…"\|null}}` / `{"notInstalled":{}}` / `{"agentUnavailable":{}}` |
| `apply_settings` | `{settings: <json>}` | `SettingsResult`: `{"applied":{}}` or `{"error":{"field":null,"message":"…"}}` |
| `refresh_projects` | `null` | `{}` (then push `set_projects`, §5) |
| `deliver_response` | `{sessionID, requestID, response}` | `{}` (agent-originated forms need no capability) |
| `shutdown` | `null` | `{}`, then flush and exit. SIGTERM follows in 5s, SIGKILL in 10s. |
| `detect_pane` | `SidecarPaneInfo`: `{paneID, processNames, command, cwd}` | `SidecarPaneMatch`: `{matches, projectPath, sessionID}` (only with `rich_pane_detection`) |

### `PluginEnvWire` (params for `initialize`)

```json
{
  "pluginRoot": "/Users/you/.ctrlx/plugins/my-agent",
  "stateDir": "/Users/you/.ctrlx/state/plugins/my-agent",
  "appVersion": "2.4.0",
  "settings": {},
  "marketplaceSource": "/path/to/marketplace/assets",
  "otlpReceiverEndpoint": "http://127.0.0.1:24318"
}
```

`otlpReceiverEndpoint` is `null` when no OTLP receiver is running; the port is
whatever the receiver actually bound this launch — use the value verbatim ([§11a](telemetry.md)).
`settings` is your plugin's current settings object (`{}` when empty). Treat every
`initialize` as a clean-slate boot — it is re-sent after a crash-restart.

## 5. Sidecar → App messages

### Notifications (you send, no response expected)

| Method | `params` | Effect |
|--------|----------|--------|
| `emit_event` | a `PluginEvent` ([§6](events.md)) | Push a state change outside of a `translate_event` reply |
| `set_projects` | `{projects: [AgentProject]}` | Replace your plugin's project list in the sidebar |
| `send_text` | `{sessionID, text}` | Type text into the session's focused pane |
| `send_keys` | `{sessionID, keys: [TmuxKey]}` | Send key presses into the pane (see [§5a](forms-and-input.md) for the `TmuxKey` shapes — `.text` is **not** a bare string) |
| `log` | `{level, message}` | Structured log (`level` ∈ `debug`/`info`/`warn`/`error`); shows in Settings → View Logs |
| `prompt_user` | `{title, message?}` | Ask the app to show a modal (only with `modal_prompts`; answer arrives via `deliver_response`) |

`AgentProject` = `{name, path, pluginID, configDir?, lastUsed?}` (`id` is computed
host-side, not encoded). `lastUsed` is a `Date` decoded by a default `JSONDecoder`
(`.deferredToDate`), so it must be **seconds since the 2001 reference date**, i.e.
`unix_seconds - 978307200`. A wrong format (e.g. raw unix millis) throws and the
host drops the *entire* project list. When in doubt, omit it (recency sort just
falls back) — leaving it out is safe.

### Requests (you send, app responds)

| Method | `params` | Returns |
|--------|----------|---------|
| `agent_panes` | `null` | `[string]` — tmux pane IDs CtrlX believes belong to your agent |

When you send a request, generate a unique `id`, then watch the inbound stream for
a message whose `id` matches and read its `result`.

## 7. Spawn environment

CtrlX spawns your executable with the parent environment plus five variables.
Its working directory is set to `CTRLX_PLUGIN_ROOT`.

| Variable | Example | Meaning |
|----------|---------|---------|
| `CTRLX_PLUGIN_ROOT` | `~/.ctrlx/plugins/my-agent` | Plugin bundle dir (read-only assets) |
| `CTRLX_STATE_DIR` | `~/.ctrlx/state/plugins/my-agent` | Writable scratch/state dir |
| `CTRLX_APP_VERSION` | `2.4.0` | Host app version |
| `CTRLX_INGRESS_SOCK` | `~/.ctrlx/state/ingress.sock` | Hook ingress socket path ([§8](integration.md)) |
| `CTRLX_PLUGIN_ID` | `my-agent` | Your manifest `id` |

## 9. Lifecycle & crash policy

**Startup:** spawn → `initialize` request → you respond → ready.

**Supervised restart:** on unexpected exit, CtrlX counts crashes in a rolling
60-second window and restarts after backoff (1 s, 2 s, 4 s). **On the 4th crash in
60 s the plugin is auto-disabled** (last 50 stderr lines kept for the banner).
After any restart CtrlX re-sends `initialize` — be ready for it anytime.

**Shutdown:** `shutdown` request → you exit. SIGTERM after 5 s, SIGKILL after 10 s.

**stderr** is captured to `~/.ctrlx/state/plugins/<id>/logs/stderr.log` (rotated
at 5 MB). Structured `log` notifications go to a separate `sidecar.log`. Never
write non-RPC bytes to **stdout** — it corrupts the frame stream.

## 12. Known limitations

- `rich_pane_detection`: the `detect_pane` RPC exists but host detection does not
  currently call it. Use `process_names` and bridge events for detection.
- `modal_prompts`: gates only the **host modal** `prompt_user`, whose UI
  is a follow-on. It does **not** gate the agent-originated form path —
  `awaitingPermission`/`awaitingReplies`/`awaitingPlanApproval` states +
  `deliver_response` work today with no capability declared ([§4a](forms-and-input.md), [§6](events.md)).
- Crash-loop banner UI is a follow-on (the auto-disable still happens).
- OTLP: a declared namespace ([§11a](telemetry.md)) surfaces only the single `token_event` record
  shape. Claude's richer signals (tool-result counts, commit/PR milestones,
  permission-mode events) have no declared-namespace equivalent yet.
