# Forms and terminal input

Read only when the agent has blocking prompts or the plugin sends text/keys.
Keep the agent's actual permission policy; do not mark approvals auto-approvable
merely to simplify integration. Clear or reject stale prompt IDs.

## 4a. Answering forms — request & response shapes

When you put the session into an `awaitingPermission` / `awaitingReplies` /
`awaitingPlanApproval` state ([§6](events.md)), you embed a **request** describing the form. When
the user answers, the app calls `deliver_response` with `{sessionID, requestID,
response}` — `requestID` is the exact value you sent in the state, and `response` is
an `AgentResponse` (a single-key tagged object). **No capability required.**

You then act on the answer however your agent allows — call your agent's API, or (if
the agent's only surface is its TUI) inject keystrokes with `send_keys` ([§5](protocol-reference.md)).
Match `sessionID` and `requestID` to a still-open prompt before sending input.
Respond `{}` promptly after handling the answer; do not replay a stale response.

### The request you embed

**PermissionRequest** (the `_0` of `awaitingPermission`):
```json
{
  "title": "Run shell command",
  "description": "rm -rf build/",
  "isAutoApprovable": false,
  "suggestions": [ { "id": "always", "label": "Allow always for this session", "detail": null } ],
  "allowsCustomInstructions": true
}
```
`title`/`description`/`isAutoApprovable`/`suggestions`/`allowsCustomInstructions` are
all required (`suggestions[].detail` is the only optional). `isAutoApprovable: true`
lets the app auto-approve in yolo mode without showing a form.

**AskUserQuestionRequest** (the `_0` of `awaitingReplies`):
```json
{
  "questions": [
    {
      "id": "q0",
      "question": "Which approach?",
      "header": "Approach",
      "options": [
        { "id": "q0-o0", "label": "Rewrite", "description": "…", "preview": null }
      ],
      "multiSelect": false,
      "allowsFreeText": true
    }
  ]
}
```
`preview` is optional; everything else required. Use stable option ids like
`"q<i>-o<j>"` so you can map the answer back.

(`ApprovePlanRequest` is analogous; if your agent has no plan-approval step, leave
it unused — start with permission/questions.)

### The `response` you receive

`AgentResponse` cases (single-key tagged object):

| Case | JSON | Notes |
|------|------|-------|
| `permission` | `{"permission": {"decision": <PermissionDecision>, "appliedSuggestionID": "always"\|null}}` | `appliedSuggestionID` is the `suggestions[].id` the user tapped, if any |
| `askUserQuestion` | `{"askUserQuestion": {"answers": [{"questionID": "q0", "selectedOptionIDs": ["q0-o1"], "freeText": null}]}}` | one entry per question; `freeText` set when the user typed "Other" |
| `prompt` | `{"prompt": {"text": "…"}}` | free-text prompt submission |
| `replyAfterStop` | `{"replyAfterStop": {"text": "…"}}` | empty text = "interrupt, send nothing" |
| `approvePlan` | `{"approvePlan": {"decision": <PlanDecision>, "editedPlan": "…"\|null}}` | |

**PermissionDecision** uses synthesized tagged objects, not bare strings:
`{"allow": {}}`, `{"deny": {}}`, or
`{"denyWithFeedback": {"_0": "use tabs instead"}}`.
**PlanDecision** is a raw-string enum instead: `"approve"` or `"reject"`.

## 5a. TmuxKey encoding (for `send_keys`)

`keys` is an array of `TmuxKey`, each a single-key tagged object (same auto-derived
`Codable` rules as [§6](events.md) — **a `_0`-wrapped associated value, NOT a bare string**). The
whole array is decoded with `try?`: if even one element is malformed, **every**
keystroke is silently dropped and nothing is sent.

| Key | JSON |
|-----|------|
| Literal text | `{"text": {"_0": "hello"}}` — ⚠️ NOT `{"text": "hello"}` (that fails to decode) |
| Enter / Shift-Enter | `{"enter": {}}` / `{"shiftEnter": {}}` |
| Escape / Tab / Backtab | `{"escape": {}}` / `{"tab": {}}` / `{"backtab": {}}` |
| Space / Backspace / Delete | `{"space": {}}` / `{"backspace": {}}` / `{"delete": {}}` |
| Arrows | `{"up": {}}` / `{"down": {}}` / `{"left": {}}` / `{"right": {}}` |
| Home / End / PageUp / PageDown | `{"home": {}}` / `{"end": {}}` / `{"pageUp": {}}` / `{"pageDown": {}}` |
| Ctrl / Alt / Ctrl+Alt + char | `{"ctrl": {"_0": "c"}}` / `{"alt": {"_0": "b"}}` / `{"ctrlAlt": {"_0": "x"}}` |
| Delay (ms, not a real key) | `{"delay": {"_0": 100}}` |

Example `send_keys` to type "yes" and submit:
```json
{ "method": "send_keys",
  "params": { "sessionID": "%4", "keys": [ {"text": {"_0": "yes"}}, {"enter": {}} ] } }
```
