#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PACKAGE_ROOT="$PROJECT_ROOT/CtrlxPackage"

for candidate in .env.local .env.production .env.development .env.test; do
    if [ -f "$PACKAGE_ROOT/$candidate" ]; then
        echo "CtrlX Relay already uses $PACKAGE_ROOT/$candidate"
        exit 0
    fi
done

port_seed="$(printf '%s' "$PROJECT_ROOT" | cksum | awk '{print $1}')"
port=$((18000 + port_seed % 1000))
destination="$PACKAGE_ROOT/.env.local"

sed \
    -e "s/^CTRLX_COMPOSE_PROJECT_NAME=.*/CTRLX_COMPOSE_PROJECT_NAME=ctrlx-$port/" \
    -e "s/^CTRLX_RELAY_PORT=.*/CTRLX_RELAY_PORT=$port/" \
    -e "s|^DATA_DIRECTORY=.*|DATA_DIRECTORY=.ctrlx-data-$port|" \
    "$PACKAGE_ROOT/.env.development.example" > "$destination"
chmod 600 "$destination"

echo "Created $destination (CtrlX Relay port $port)"
