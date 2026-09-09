# Events, states and session lifecycle

Read when implementing `translate_event` or pushing `emit_event`. The examples
below use the sidecar's camelCase stdio channel, not the ingress socket format.

## 6. PluginEvent & AgentState (the heart)

`translate_event` (and `emit_event`) deliver a **PluginEvent** — the single
carrier for everything your plugin wants to change about a session. camelCase keys:

```json
{
  "pluginID": "my-agent",
  "sessionID": "abc-123",
  "state": { "doneWorking": { "summary": "Fixed the bug." } },
  "notification": { "title": "my-agent", "body": "Done." },
  "appActions": [],
  "tmuxPane": "%4",
  "projectPath": "/Users/you/code/proj",
  "permissionMode": "default"
}
```

| Field | Required | Meaning |
|-------|----------|---------|
| `pluginID` | yes | Your plugin id (echo `params.pluginID`) |
| `sessionID` | yes | Stable id for this agent session. Derive from the payload; fall back to `tmuxPane` |
| `appActions` | **yes** | Array of `AppAction` (§6a). Usually `[]`; omitting it drops the whole event. |
| `state` | no | New `AgentState` (below). `null`/omitted = "no opinion, leave unchanged" |
| `notification` | no | `{title, body}` — fires a Mac notification + iOS push |
| `tmuxPane` | no | Bootstraps the session↔pane mapping. Comes from `context.TMUX_PANE` |
| `projectPath` | no | Lets the sidebar show the project name immediately |
| `permissionMode` | no | `default`/`plan`/`acceptEdits`/`bypassPermissions`, if your agent reports it |

The Swift initializer's `appActions = []` default does **not** apply to JSON
decoding. Always include the array in both replies and `emit_event` notifications.

### Tagged-enum encoding rule (applies to `state`, `appActions`, and responses)

Every Swift enum below serializes the same way (auto-synthesized `Codable`, no key
strategy):

- **No associated values** → a single-key object with an empty object value:
  `.working` → `{"working": {}}`, `.idle` → `{"idle": {}}`. (NOT the bare string
  `"working"` — that fails to decode.)
- **Labeled associated values** → keys are the labels:
  `.doneWorking(summary:)` → `{"doneWorking": {"summary": "…"}}`.
- **One *unlabeled* associated value** → it becomes the key `"_0"`:
  `.awaitingPermission(req, requestID:)` → `{"awaitingPermission": {"_0": <req>, "requestID": "…"}}`.
- **Mixed** → unlabeled positions are `"_0"`, `"_1"`, …; labeled ones use their label.

This applies to `AgentState`, `AppAction`, `AgentResponse`, `PermissionDecision`
and `TmuxKey` ([§5a](forms-and-input.md)); `PlanDecision` is instead a raw string.

### AgentState encodings (single-key tagged object)

| State | JSON | Attention badge? |
|-------|------|------------------|
| Working | `{"working": {}}` | no |
| Idle / handled | `{"idle": {}}` | no |
| Finished a turn | `{"doneWorking": {"summary": "…" \| null}}` | **yes** |

Richer agents can also produce **blocked-on-input** states. These open a response
form in the Mac app / iOS viewer and route the answer back through
`deliver_response` ([§4a](forms-and-input.md)). **They do NOT require any capability** — `modal_prompts`
gates only the host-originated `prompt_user` modal, not these agent-originated
forms. Each wraps a structured request (its first, unlabeled associated value →
`"_0"`) plus a `requestID` you echo back when the answer arrives:

| State | JSON | Request type (`_0`) |
|-------|------|----------------------|
| Blocked on a tool permission | `{"awaitingPermission": {"_0": <PermissionRequest>, "requestID": "…"}}` | `PermissionRequest` |
| Blocked on questions | `{"awaitingReplies": {"_0": <AskUserQuestionRequest>, "requestID": "…"}}` | `AskUserQuestionRequest` |
| Blocked on plan approval | `{"awaitingPlanApproval": {"_0": <ApprovePlanRequest>, "requestID": "…"}}` | `ApprovePlanRequest` |

Pick a `requestID` that is **stable per prompt** (e.g. `"<sessionID>:permission:<agent-prompt-id>"`)
so a re-sent event collapses to one form, and so a later `deliver_response` can map
it back to the right agent prompt. Start with `working`/`idle`/`doneWorking`; add
the awaiting cases once the basic round-trip works. The request/response shapes are
in [§4a](forms-and-input.md).

## 6a. AppAction (the `appActions` array)

`appActions` carries side-effects the host should perform that are *not* a session
state change. Each element is a single-key tagged object. **Almost every event
sends `[]`** — the one you will likely use is `sessionEnded`.

| Action | JSON | Effect |
|--------|------|--------|
| End the session | `{"sessionEnded": {"sessionID": "%4", "closePaneEligible": false}}` | Removes the sidebar row, resets the pane's session-scoped state. **`sessionID` here is the tmux PANE id** (the host keys session-end by pane), NOT your agent's session id — use `context.TMUX_PANE`. `closePaneEligible: true` closes the pane too; gate it on your `close_pane_on_session_end` setting ([§13](distribution-and-settings.md)). |
| Suggest opening a file | `{"openFileSuggestion": {"sessionID": "…", "path": "/…", "displayName": "plan.md", "isPlan": false, "projectDir": "/…"\|null}}` | Surfaces an "open this file?" prompt. Niche — most plugins never emit it. |
| Clear file suggestions | `{"dismissFileSuggestions": {"sessionID": "…"}}` | Dismisses outstanding suggestions. |

**Session lifecycle pattern.** If your agent fires no event on launch or quit,
the host's periodic process reconciliation is only a fallback. Emit two
synthetic events of your own — one when
your bridge starts (→ `state: {"idle": {}}`, `appActions: []`, so the session appears)
and one on graceful exit (→ `state: null`, `appActions: [{"sessionEnded": …}]`).
This mirrors Claude Code's `SessionStart`/`SessionEnd`. (A graceful-exit signal — a
shutdown finalizer in the agent's plugin, awaited so the frame flushes before the
process dies — covers `/exit` and Ctrl-C; a hard kill skips it and the session
lingers until the host next reconciles.)
