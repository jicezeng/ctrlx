# CtrlX release process

CtrlX releases bind each binary to an immutable source commit.

1. Update `Config/Shared-Base.xcconfig`, version docs and `MODIFICATIONS.md`.
2. Run all boundary checks, Swift tests, website build and Mac/iOS build checks.
3. Commit from the primary worktree and create `v<version>` at that exact commit.
4. Copy `.env.example` to the selected root environment file and configure the
   signing identity, notary profile and owned download URL.
5. Run the zero-parameter `./scripts/release.sh`.

The script refuses dirty or untagged source, archives and signs `CtrlX.app`,
submits the app and DMG for notarization, generates `CtrlX-<version>.dmg`, a
Sparkle appcast, SHA-256 file and JSON manifest containing the full source
commit and AGPL license.

Sparkle stays disabled in the application until a CtrlX feed URL and EdDSA
public key are supplied in ignored `Config/Local-macOS.xcconfig`. Gallager's
feed, key and domains are never fallback values.

## Publish the macOS package through home

The Nginx bind mount is on the home Mac, not on the build Mac. After either the
private package command or the formal release command has produced
`dist/CtrlX-<version>.dmg`, publish it with:

```bash
./deploy2home.sh
```

The script validates the DMG signature and embedded build/source metadata,
uploads through an SSH staging directory, refuses to replace a same-named DMG
with different bytes, moves the installer last, and verifies both the installer
and DMG through `https://ctrlx.zengjice.com:7001/install/`. It never copies into
a local `happy-nginx` checkout.

The defaults target `192.168.31.5` and
`/Users/zengjice/Work/happy-nginx/deploy/ctrlx`. Override them only through the
`CTRLX_PUBLISH_*` variables documented in `.env.example`; credentials remain in
SSH/Keychain configuration and are not stored in this repository.

TestFlight/App Store upload is intentionally blocked by `scripts/testflight.sh`
until an AGPL/Apple terms review or copyright-holder exception is documented.
Local signed-device builds remain available through
`scripts/package-local-ios.sh`.
