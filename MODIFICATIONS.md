# Modifications

- **Distribution**: CtrlX
- **Fork point**: `919c7772928531d4d0bb266bdf275691d361901e`
- **Fork date**: 2026-08-14
- **Maintainer**: ZengJice `<jicezeng@gmail.com>`
- **Upstream**: [gpambrozio/Gallager](https://github.com/gpambrozio/Gallager)
- **License**: GNU AGPL-3.0

## Major changes

- Rebranded the macOS app, iOS app, CLI, Relay, and documentation as CtrlX.
- Isolated Apple bundle identifiers, App Group, Keychain, local state, sockets,
  environment variables, tmux metadata, update infrastructure, and telemetry
  from Gallager.
- Added explicit build-to-source metadata and Relay source-disclosure endpoints.
- Retained the pre-existing customized terminal, tmux, remote-control, Relay,
  notification, and performance work in the complete Git history.

Detailed implementation and acceptance status live in
[`docs/v3.0.0`](docs/v3.0.0/).

This file records distribution-level changes, not every individual commit.
Consult the Git history and release notes for detailed changes.
