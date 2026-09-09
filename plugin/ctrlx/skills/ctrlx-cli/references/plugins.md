# Installed plugin management

Inspect before changing state:

```bash
ctrlx plugin list --json
ctrlx plugin info my-agent --json
ctrlx plugin logs my-agent
ctrlx plugin update my-agent --json
```

`plugin update` only checks; `--apply` installs updates. Omit the ID to check all
URL-installed plugins, not to broaden a requested single-plugin update.

For an authorized installation, use `plugin install <https-manifest-url>` or
`plugin install --zip /path/to/plugin.zip`. A plugin executes with the user's
permissions, not in a sandbox; SHA-256 verifies integrity, not publisher identity.
Review the source and trust details before installation.

In JSON mode, `plugin install … --json` without `--yes` returns
`.result.status == "needs_trust"` and **does not install**, even though it exits 0.
Only use `--yes` after the user has authorized that specific source; verify the
result is `installed` and inspect `plugin info` afterward.

Other operations, only when requested:

| Command | Effect |
|---|---|
| `plugin enable <id>` / `plugin disable <id>` | Starts / stops the plugin core |
| `plugin update <id> --apply` | Applies an available update; a changed source needs renewed trust |
| `plugin remove <id>` | Uninstalls the plugin, preserving its state directory by default |
| `plugin remove <id> --delete-state` | Also permanently deletes plugin state |
| `plugin call <id> <method>` | Invokes a plugin method; inspect `--help` and its contract first |

Do not treat `plugin call` as inherently read-only: methods such as `install`
modify the agent's configuration. Bundled Claude/Codex plugins cannot be removed.
For CLI failures, check exit status/stderr; not every plugin error emits JSON.
