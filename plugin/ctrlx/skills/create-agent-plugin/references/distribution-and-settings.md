# Installation, distribution and settings

Read when installing, configuring or publishing a finished sidecar. Author in a
workspace first; copying into the live plugin directory, modifying agent config,
restarting CtrlX or publishing a bundle requires that work to be in user scope.
Do not overwrite an existing plugin directory without checking its contents.

## 10. Distribution

### Folder-drop (simplest, great for development)

Copy the plugin directory to `~/.ctrlx/plugins/<id>/`. CtrlX discovers it on
next launch. Requires: dir name == sanitized `id`; `plugin.json` decodes with
`runtime == "sidecar"`; the declared executable exists and is `chmod +x`.

> ⚠️ Discovery checks `isDirectory`, which is **false for a symlink-to-directory**
> (Foundation reports the link itself). A dev install script must **copy** the
> plugin into `~/.ctrlx/plugins/<id>/`, not symlink it — and re-copy after edits,
> then relaunch.

### Remote install (for shipping to others)

Host `plugin.json` at an HTTPS URL with `bundle_url`, `bundle_sha256`,
`manifest_url`. The bundle is a zip whose root holds `plugin.json` + the executable.
Users install via Settings → "Add Plugin from URL…" or
`ctrlx plugin install https://example.com/plugin.json`.

CtrlX enforces: https-only fetch → schema/id validation → **trust prompt** →
stream download (≤50 MiB) → SHA-256 verify → zip-slip-hardened unpack → tree
validation (executable present + executable bit) → atomic commit.

`ctrlx plugin update <id>` checks the stored `manifest_url`; add `--apply` to
install an available update. Changed bundle hosts require renewed trust.
`ctrlx plugin remove <id>` calls your `uninstall`, disables, and deletes the
plugin directory. State is kept unless `--delete-state` is explicitly requested.

## 11. Security model

Honest scope: **trusted-on-install, hash-pinned, runs with your permissions** — not
"safe to run untrusted code."

Provided: https-only transport, SHA-256 **integrity** pin (not authenticity), an
explicit trust prompt, zip-slip hardening. **Not** provided: no code signing or
publisher-identity verification (the `signature` field is reserved/ignored), no OS
sandbox (the sidecar runs as the user with full permissions), no marketplace
vetting. Do not run plugins from untrusted sources.

## 13. Settings (generic sidecar settings)

Every folder-dropped sidecar gets the same generic Settings → Agents panel for free
— no per-plugin UI. The settings object reaches you as `initialize.settings` and via
`apply_settings` (`{"settings": {...}}`), and is **snake_case** (it's hand-coded, like
the manifest). The standard keys (all optional, with these defaults):

| Key | Type | Default | Meaning |
|-----|------|---------|---------|
| `command_path` | string | `""` | Launch-command override. Empty → use your own `command_for_launch` default. |
| `auto_run` | bool | `true` | When `false`, return `null` from `command_for_launch` (don't auto-start). |
| `log_level` | string | `"info"` | `debug`/`info`/`warn`/`error`. |
| `additional_config_folders` | [string] | `[]` | Extra per-project config roots (see `configRoot` below). |
| `close_pane_on_session_end` | bool | `false` | Fold into `sessionEnded`'s `closePaneEligible` ([§6a](events.md)). |

A typical sidecar honors these in `command_for_launch` (gate on `auto_run`, prefer
`command_path`) and in `install`/`install_status`/`uninstall`.

### `configRoot` (install scoping)

`install`/`uninstall`/`install_status` receive `{configRoot: string | null}`:

- `null` → the **default** row. Install your bridge into the agent's global config
  (the `sidecar.default_config_root` from the manifest is the label shown for it).
- a path → a **per-project** row the user added (one of `additional_config_folders`).
  Install the bridge into that project's local config so the agent loads it only
  there (e.g. `<root>/.my-agent/plugin/`).

## Verify an authorized local install

Copy (not symlink) the completed plugin to the exact `~/.ctrlx/plugins/<id>/`
location, preserving the executable bit. Check for existing user files first.
After a requested restart, inspect `ctrlx plugin list`, `plugin info <id>` and
`plugin logs <id>`. Structured logs and stderr are separate files under
`~/.ctrlx/state/plugins/<id>/logs/` (`sidecar.log` and `stderr.log`).

Verify one real event end-to-end: agent → bridge → ingress → translation → pane
state. Loading the plugin alone does not prove hook wiring or event decoding.
A local ZIP must contain `plugin.json` and the executable at its root, not an
extra enclosing directory. `ctrlx plugin install --zip /path/to/plugin.zip`
uses the same trust flow as a URL install.

For noninteractive installation, `--json` without `--yes` reports `needs_trust`
and stops; exit 0 is not proof of installation. Only use `--yes` for a source
the user has authorized, then require status `installed` and inspect the plugin.
