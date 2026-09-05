#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck source=sbin/environment.sh
source "$SCRIPT_DIR/environment.sh"
select_ctrlx_environment "$PROJECT_ROOT"

cd "$PROJECT_ROOT/CtrlxPackage"
exec docker compose down
