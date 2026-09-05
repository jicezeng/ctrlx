#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_ROOT/Config/Shared-Base.xcconfig"

# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"
load_project_environment "$PROJECT_ROOT"

[ "$#" -eq 0 ] || log_error "CtrlX deployment is zero-parameter; edit the selected .env file instead."
assert_primary_worktree

require_config() {
    local name="$1"
    [ -n "${!name:-}" ] || log_error "Missing $name in ${CTRLX_ENV_FILE:-the selected environment file}."
}

require_config CTRLX_DEPLOY_HOST
require_config CTRLX_RELAY_HEALTH_URL

DEPLOY_USER="${CTRLX_DEPLOY_USER:-root}"
REMOTE_DIR="${CTRLX_RELAY_REMOTE_DIR:-/opt/ctrlx}"
CADDY_CONF_DIR="${CTRLX_CADDY_CONF_DIR:-}"
REMOTE_HOST="$DEPLOY_USER@$CTRLX_DEPLOY_HOST"
VERSION="$(get_version)"
SOURCE_REVISION="$(get_full_source_revision)"

case "$REMOTE_DIR" in
    /*) ;;
    *) log_error "CTRLX_RELAY_REMOTE_DIR must be an absolute path." ;;
esac
case "$CTRLX_DEPLOY_HOST" in
    ''|*[!A-Za-z0-9._-]*) log_error "CTRLX_DEPLOY_HOST must be a DNS name or IPv4 address without shell metacharacters." ;;
esac
case "$DEPLOY_USER" in
    ''|*[!A-Za-z0-9._-]*) log_error "CTRLX_DEPLOY_USER contains unsupported characters." ;;
esac
case "$REMOTE_DIR" in
    *[!A-Za-z0-9_./-]*) log_error "CTRLX_RELAY_REMOTE_DIR contains unsupported characters." ;;
esac
if [ -n "$CADDY_CONF_DIR" ]; then
    case "$CADDY_CONF_DIR" in
        /*) ;;
        *) log_error "CTRLX_CADDY_CONF_DIR must be an absolute path." ;;
    esac
    case "$CADDY_CONF_DIR" in
        *[!A-Za-z0-9_./-]*) log_error "CTRLX_CADDY_CONF_DIR contains unsupported characters." ;;
    esac
fi

if [ -n "$(git -C "$PROJECT_ROOT" status --porcelain)" ]; then
    log_error "Deployment requires a clean worktree so /source identifies the exact running code."
fi

log_info "Checking $REMOTE_HOST"
ssh -q -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE_HOST" true \
    || log_error "Cannot connect to $REMOTE_HOST with SSH key authentication."

ssh "$REMOTE_HOST" "mkdir -p '$REMOTE_DIR'"
rsync -az --delete \
    --exclude='.build' \
    --exclude='.env*' \
    --exclude='data' \
    --exclude='secrets' \
    --exclude='Tests' \
    -e ssh \
    "$PROJECT_ROOT/CtrlxPackage/" \
    "$REMOTE_HOST:$REMOTE_DIR/"

remote_identity="$({
    ssh "$REMOTE_HOST" bash -s -- "$REMOTE_DIR" <<'REMOTE_CHECK'
set -euo pipefail
remote_dir="$1"
config="$remote_dir/.env.production"
[ -f "$config" ] || {
    echo "MISSING"
    exit 0
}
set -a
# shellcheck disable=SC1090
source "$config"
set +a
printf '%s\t%s\n' "${CTRLX_VERSION:-}" "${CTRLX_SOURCE_REVISION:-}"
REMOTE_CHECK
} | tail -1)"

[ "$remote_identity" != "MISSING" ] \
    || log_error "Remote $REMOTE_DIR/.env.production is missing. Copy and edit .env.production.example first."

remote_version="${remote_identity%%$'\t'*}"
remote_revision="${remote_identity#*$'\t'}"
[ "$remote_version" = "$VERSION" ] \
    || log_error "Remote CTRLX_VERSION is $remote_version; expected $VERSION."
[ "$remote_revision" = "$SOURCE_REVISION" ] \
    || log_error "Remote CTRLX_SOURCE_REVISION is $remote_revision; expected $SOURCE_REVISION."

if [ -n "$CADDY_CONF_DIR" ]; then
    ssh "$REMOTE_HOST" "test -d '$CADDY_CONF_DIR'" \
        || log_error "Configured Caddy directory does not exist: $CADDY_CONF_DIR"
    scp "$PROJECT_ROOT/CtrlxPackage/caddy/ctrlx.caddy" \
        "$REMOTE_HOST:$CADDY_CONF_DIR/ctrlx.caddy"
fi

log_info "Building and starting CtrlX Relay $VERSION ($SOURCE_REVISION)"
ssh "$REMOTE_HOST" bash -s -- "$REMOTE_DIR" <<'REMOTE_DEPLOY'
set -euo pipefail
remote_dir="$1"
cd "$remote_dir"
set -a
# shellcheck disable=SC1091
source .env.production
set +a
export CTRLX_ENV_FILE=.env.production
docker compose config --quiet
docker compose up -d --build --remove-orphans
REMOTE_DEPLOY

log_info "Verifying health and corresponding source"
health_body="$(curl -fsS --retry 12 --retry-delay 2 "$CTRLX_RELAY_HEALTH_URL")" \
    || log_error "Relay health check failed: $CTRLX_RELAY_HEALTH_URL"
printf '%s' "$health_body" | grep -q '"status"[[:space:]]*:[[:space:]]*"ok"' \
    || log_error "Relay health response is not healthy."

source_url="${CTRLX_RELAY_HEALTH_URL%/health}/source"
source_body="$(curl -fsS "$source_url")" || log_error "Relay source endpoint failed: $source_url"
printf '%s' "$source_body" | grep -q "$SOURCE_REVISION" \
    || log_error "Running Relay does not report commit $SOURCE_REVISION."

log_success "CtrlX Relay deployed: $VERSION ($SOURCE_REVISION)"
log_success "Source metadata: $source_url"
