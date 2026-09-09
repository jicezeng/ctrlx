# Layouts and tmux fallback

## Idempotent creation

`ctrlx new-session --name work --if-missing --json` returns `.result.created`.
When false, reuse the existing session; do not blindly re-send startup commands
or create another set of panes. Discover new pane IDs from responses/listings,
never from assumed indexes such as `%5`.

## Declarative layout

For a requested repeatable workspace, `ctrlx apply` accepts YAML/JSON, a directory
containing `.ctrlx.yaml`/`.ctrlx.yml`/`.tmuxp.yaml`/`.tmuxp.yml`, or `-` for stdin.
For example, save this as `work.yaml` with the user's actual directory:

```yaml
session_name: work
start_directory: /path/to/project
windows:
  - window_name: build
    layout: even-horizontal
    panes:
      - shell_command: ['make test']
      - shell_command: ['tail -f /tmp/build.log']
```

```bash
ctrlx apply work.yaml --dry-run --json
ctrlx apply work.yaml --detach
```

`--dry-run` validates and prints planned actions without changing tmux; the app
must still be reachable. Review startup commands before applying. Ordinary
re-apply reuses the session rather than rerunning its pane startup commands, but
still runs `on_apply` hooks and updates session labels/color. It is not read-only.

- `--detach`: do not switch the UI to the resulting session.
- `--require-create`: exit 3 if the session already exists.
- `--rebuild`: **destroys the existing session first**; only use for an explicit
  replacement request, never as an automatic fix for a validation error.
- `--lenient`: relaxes unknown-key errors; prefer correcting the configuration.
- Validation failures exit 2. Use `ctrlx apply --help` for installed-version flags.

## Raw tmux only when needed

CtrlX IDs address real tmux objects. Prefer the CLI for focus and mutations it
supports; raw tmux is useful for session rename, pane resizing, swapping, zoom
and layouts without a dedicated CLI verb.

Inside a managed pane, `$TMUX` selects its tmux server. Outside it, confirm the
host's configured **tmux socket** and use `tmux -S /actual/tmux/socket …`.
`$CTRLX_SOCKET` belongs to the separate CtrlX API and must not be used here.

```bash
tmux display-message -p -t '%3' '#{session_name}:#{window_index} #{pane_id}'
tmux resize-pane -t '%3' -y 15
tmux resize-pane -Z -t '%3'
```

Confirm the read-only result matches the requested local target before mutation.
Local tmux commands cannot operate on a remote host merely because its session
is visible in a CtrlX viewer. CtrlX observes tmux changes, but raw tmux focus is
not a substitute for `ctrlx select-session` / `select-window` UI navigation.
