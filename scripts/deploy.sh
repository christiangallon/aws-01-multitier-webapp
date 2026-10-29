#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Ships a new application release without a full `terraform apply`:
#   1. Packages ../app (excluding node_modules/.env) into a zip
#   2. Uploads it to the artifacts bucket (releases/app.zip + a versioned copy)
#   3. Syncs app/public to the static-assets bucket
#   4. Starts rolling ASG instance refreshes (app tier, and web tier)
#   5. Optionally waits for completion and smoke-tests /health
#
# Usage:
#   ./scripts/deploy.sh [--skip-web] [--no-wait] [--skip-tests]
#
# Requires: aws, terraform, zip, jq, curl (and npm unless --skip-tests).
# Reads bucket/ASG names from `terraform output` in ../terraform.
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"
APP_DIR="$ROOT_DIR/app"

REFRESH_WEB=true
WAIT=true
RUN_TESTS=true

for arg in "$@"; do
  case "$arg" in
    --skip-web) REFRESH_WEB=false ;;
    --no-wait) WAIT=false ;;
    --skip-tests) RUN_TESTS=false ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

log() { printf '\033[1;34m[deploy]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[deploy] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

for bin in aws terraform zip jq curl; do
  command -v "$bin" >/dev/null 2>&1 || die "'$bin' is required but not installed."
done

tf_out() { terraform -chdir="$TF_DIR" output -raw "$1"; }

log "Reading Terraform outputs..."
ARTIFACTS_BUCKET="$(tf_out artifacts_bucket)" || die "Run 'terraform apply' first."
STATIC_BUCKET="$(tf_out static_assets_bucket)"
BUNDLE_KEY="$(tf_out app_bundle_key)"
APP_ASG="$(tf_out app_asg_name)"
WEB_ASG="$(tf_out web_asg_name)"
APP_URL="$(tf_out app_url)"
REGION="$(tf_out aws_region)"

VERSION="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)"
if [ -n "$(git -C "$ROOT_DIR" status --porcelain -- app 2>/dev/null)" ]; then
  VERSION="${VERSION}-dirty-$(date +%H%M%S)"
fi

# ------------------------------------------------------------------ test ----
if [ "$RUN_TESTS" = true ]; then
  command -v npm >/dev/null 2>&1 || die "npm is required to run tests (or pass --skip-tests)."
  log "Running unit tests..."
  (cd "$APP_DIR" && npm ci --no-audit --no-fund >/dev/null && npm test)
fi

# --------------------------------------------------------------- package ----
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
BUNDLE="$BUILD_DIR/app.zip"

log "Packaging app (version $VERSION)..."
(cd "$APP_DIR" && zip -qr "$BUNDLE" . -x 'node_modules/*' -x '.env' -x 'coverage/*')
log "Bundle size: $(du -h "$BUNDLE" | cut -f1)"

# ---------------------------------------------------------------- upload ----
log "Uploading to s3://$ARTIFACTS_BUCKET/$BUNDLE_KEY"
aws s3 cp "$BUNDLE" "s3://$ARTIFACTS_BUCKET/releases/app-$VERSION.zip" --region "$REGION" --only-show-errors
aws s3 cp "$BUNDLE" "s3://$ARTIFACTS_BUCKET/$BUNDLE_KEY" --region "$REGION" --only-show-errors \
  --metadata "version=$VERSION"

log "Syncing static assets to s3://$STATIC_BUCKET/"
aws s3 sync "$APP_DIR/public/" "s3://$STATIC_BUCKET/" --region "$REGION" --only-show-errors

# --------------------------------------------------------------- refresh ----
start_refresh() {
  local asg="$1" warmup="$2"
  log "Starting instance refresh for $asg..."
  aws autoscaling start-instance-refresh \
    --region "$REGION" \
    --auto-scaling-group-name "$asg" \
    --strategy Rolling \
    --preferences "{\"MinHealthyPercentage\":100,\"MaxHealthyPercentage\":200,\"InstanceWarmup\":$warmup}" \
    --query InstanceRefreshId --output text
}

wait_refresh() {
  local asg="$1" id="$2" status pct
  log "Waiting for refresh $id on $asg (this usually takes 5-10 minutes)..."
  while true; do
    read -r status pct < <(aws autoscaling describe-instance-refreshes \
      --region "$REGION" \
      --auto-scaling-group-name "$asg" \
      --instance-refresh-ids "$id" \
      --query 'InstanceRefreshes[0].[Status,PercentageComplete]' --output text)
    log "  $asg: $status (${pct:-0}%)"
    case "$status" in
      Successful) return 0 ;;
      Failed|Cancelled|RollbackSuccessful|RollbackFailed) die "Instance refresh for $asg ended with status $status." ;;
    esac
    sleep 30
  done
}

APP_REFRESH_ID="$(start_refresh "$APP_ASG" 180)"
WEB_REFRESH_ID=""
if [ "$REFRESH_WEB" = true ]; then
  WEB_REFRESH_ID="$(start_refresh "$WEB_ASG" 120)"
fi

if [ "$WAIT" = true ]; then
  wait_refresh "$APP_ASG" "$APP_REFRESH_ID"
  [ -n "$WEB_REFRESH_ID" ] && wait_refresh "$WEB_ASG" "$WEB_REFRESH_ID"

  log "Smoke test: $APP_URL/health"
  for attempt in $(seq 1 10); do
    if body="$(curl -fsS --max-time 5 "$APP_URL/health")"; then
      echo "$body" | jq .
      log "Deployment $VERSION complete."
      exit 0
    fi
    log "  health check failed (attempt $attempt), retrying in 10s"
    sleep 10
  done
  die "Health check did not succeed after deployment."
else
  log "Refresh started (app: $APP_REFRESH_ID${WEB_REFRESH_ID:+, web: $WEB_REFRESH_ID}). Not waiting."
fi
