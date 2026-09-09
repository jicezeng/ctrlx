# Optional telemetry

Read only when adding token/cost/latency/model reporting. It is not required for
session monitoring or permission forms.

## 11a. Telemetry — the OTLP meter

Optional: give your agent the same per-session token / cost / latency / model
meter Claude Code and Codex have. Two steps:

1. **Manifest**: declare your namespace (`otlp.namespace`, `otlp.token_event` —
   see the schema table in [§2](protocol-reference.md)). Records in undeclared namespaces are silently
   dropped; the declaration applies while your plugin is enabled. Matching is
   **case-sensitive** — declaring `"MyAgent"` while emitting
   `myagent.api_request` gets nothing.
2. **Emit**: POST OTLP/JSON log records to `<otlpReceiverEndpoint>/v1/logs`
   (the endpoint arrives in the `initialize` env; `null` when no receiver is
   running — then skip telemetry). One record per completed model call, with
   Claude's exact `api_request` attribute keys, values **additive** per record
   (never cumulative totals):

```json
{ "resourceLogs": [{ "scopeLogs": [{ "logRecords": [{
  "eventName": "my-agent.api_request",
  "attributes": [
    { "key": "event.name",            "value": { "stringValue": "my-agent.api_request" } },
    { "key": "session.id",            "value": { "stringValue": "<your reported sessionID>" } },
    { "key": "input_tokens",          "value": { "intValue": 1234 } },
    { "key": "output_tokens",         "value": { "intValue": 567 } },
    { "key": "cache_read_tokens",     "value": { "intValue": 0 } },
    { "key": "cache_creation_tokens", "value": { "intValue": 0 } },
    { "key": "cost_usd",              "value": { "doubleValue": 0.0123 } },
    { "key": "duration_ms",           "value": { "intValue": 4200 } },
    { "key": "model",                 "value": { "stringValue": "some-model" } }
  ]
}] }] }] }
```

`session.id` must equal the `sessionID` your sidecar reports in its
`PluginEvent`s — the host re-stamps the pane's telemetry join key from **every**
reported event, so use the id your *turn* events carry (opencode: its `ses_…`
session id, not the pane id, which only its synthetic launch frame reports). Fold reasoning/thinking tokens into
`output_tokens` (Claude's convention). The agent process usually does not
inherit CtrlX's env, so bake the endpoint into whatever emits (the opencode
plugin substitutes a token in its bridge at `install`, exactly like its ingress
socket path).
