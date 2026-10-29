#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Safely tears down the stack.
#   1. Shows what will be destroyed and asks for confirmation (type the env name)
#   2. Optionally empties versioned buckets (needed when s3_force_destroy=false)
#   3. Runs `terraform destroy`
#   4. Optionally deletes the remote-state bucket and lock table
#
# Usage:
#   ./scripts/destroy.sh [--auto-approve] [--empty-buckets] [--destroy-backend]
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "$SCRIPT_DIR/../terraform" && pwd)"

AUTO_APPROVE=false
EMPTY_BUCKETS=false
DESTROY_BACKEND=false

for arg in "$@"; do
  case "$arg" in
    --auto-approve) AUTO_APPROVE=true ;;
    --empty-buckets) EMPTY_BUCKETS=true ;;
    --destroy-backend) DESTROY_BACKEND=true ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

log() { printf '\033[1;33m[destroy]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[destroy] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

for bin in aws terraform jq; do
  command -v "$bin" >/dev/null 2>&1 || die "'$bin' is required but not installed."
done

terraform -chdir="$TF_DIR" init -input=false -backend-config=backend.hcl >/dev/null 2>&1 \
  || terraform -chdir="$TF_DIR" init -input=false >/dev/null \
  || die "terraform init failed."

OUTPUTS="$(terraform -chdir="$TF_DIR" output -json 2>/dev/null || echo '{}')"
if [ "$OUTPUTS" = "{}" ]; then
  log "No outputs found in state — the stack may already be destroyed."
fi

out() { echo "$OUTPUTS" | jq -r --arg k "$1" '.[$k].value // empty'; }

ENVIRONMENT="$(out environment)"
ENVIRONMENT="${ENVIRONMENT:-dev}"
REGION="$(out aws_region)"
REGION="${REGION:-${AWS_REGION:-us-east-1}}"

log "Environment:  $ENVIRONMENT ($REGION)"
log "App URL:      $(out app_url)"
log "RDS endpoint: $(out rds_endpoint)"
log "Buckets:      $(out artifacts_bucket) $(out static_assets_bucket) $(out access_logs_bucket)"
log "RDS is configured with skip_final_snapshot=true — ALL DATABASE DATA WILL BE LOST."

if [ "$AUTO_APPROVE" != true ]; then
  read -r -p "Type the environment name ('$ENVIRONMENT') to confirm destruction: " answer
  [ "$answer" = "$ENVIRONMENT" ] || die "Confirmation did not match. Aborting."
fi

# Delete every object version and delete marker from a bucket.
empty_bucket() {
  local bucket="$1" batch
  [ -z "$bucket" ] && return 0
  aws s3api head-bucket --bucket "$bucket" 2>/dev/null || { log "Bucket $bucket not found, skipping."; return 0; }
  log "Emptying s3://$bucket (all versions)..."
  while true; do
    batch="$(aws s3api list-object-versions --bucket "$bucket" --max-items 1000 --output json \
      | jq -c '{Objects: ([(.Versions // [])[], (.DeleteMarkers // [])[]] | map({Key, VersionId})), Quiet: true}')"
    if [ "$(echo "$batch" | jq '.Objects | length')" -eq 0 ]; then
      break
    fi
    aws s3api delete-objects --bucket "$bucket" --delete "$batch" >/dev/null
  done
}

if [ "$EMPTY_BUCKETS" = true ]; then
  for b in "$(out artifacts_bucket)" "$(out static_assets_bucket)" "$(out access_logs_bucket)"; do
    empty_bucket "$b"
  done
fi

log "Running terraform destroy..."
terraform -chdir="$TF_DIR" destroy -input=false -auto-approve

if [ "$DESTROY_BACKEND" = true ]; then
  [ -f "$TF_DIR/backend.hcl" ] || die "backend.hcl not found; cannot locate the state backend."
  STATE_BUCKET="$(sed -nE 's/^bucket *= *"(.*)"/\1/p' "$TF_DIR/backend.hcl")"
  LOCK_TABLE="$(sed -nE 's/^dynamodb_table *= *"(.*)"/\1/p' "$TF_DIR/backend.hcl")"
  BACKEND_REGION="$(sed -nE 's/^region *= *"(.*)"/\1/p' "$TF_DIR/backend.hcl")"
  log "Deleting state backend: s3://$STATE_BUCKET and DynamoDB table $LOCK_TABLE"
  empty_bucket "$STATE_BUCKET"
  aws s3api delete-bucket --bucket "$STATE_BUCKET" --region "$BACKEND_REGION"
  aws dynamodb delete-table --table-name "$LOCK_TABLE" --region "$BACKEND_REGION" >/dev/null
  rm -f "$TF_DIR/backend.hcl"
fi

log "Destroy complete."
