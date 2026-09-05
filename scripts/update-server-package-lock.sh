#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PACKAGE_ROOT="$PROJECT_ROOT/CtrlxPackage"
OUTPUT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ctrlx-server-lock.XXXXXX")"

cleanup() {
    [ ! -d "$OUTPUT_ROOT" ] || /bin/rm -rf -- "$OUTPUT_ROOT"
}
trap cleanup EXIT

docker build \
    --target server-lock \
    --output "type=local,dest=$OUTPUT_ROOT" \
    "$PACKAGE_ROOT"

generated="$OUTPUT_ROOT/Package.server.resolved"
[ -s "$generated" ] || {
    echo "Server lock generation produced no file." >&2
    exit 1
}
python3 -m json.tool "$generated" >/dev/null
cp "$generated" "$PACKAGE_ROOT/Package.server.resolved"
echo "Updated $PACKAGE_ROOT/Package.server.resolved"
