# Isolated CtrlX staging Relay

Staging is a separate deployment of the same CtrlX Relay image. It must use an
independent directory, data volume, APNs environment, DNS name and
`.env.production` file. No staging or production domain is committed.

Use `CtrlxPackage/caddy/ctrlx-staging.caddy` and provide
`CTRLX_STAGING_RELAY_HOST` in Caddy's service environment. The default upstream
is loopback port 8081. Run the same `/health`, `/ready`, `/version` and `/source`
checks as production and verify that `/source` names the exact staging commit.

Do not reuse production pairing data or secrets. Licensing/payment testing is
outside the CtrlX 3.0.0 community distribution scope.
