#!/usr/bin/env bash
#
# Generate policy/public-read.json from PROJECT_NAME / MINIO_BUCKET.
#
# Usage:
#   ./scripts/generate-policy.sh
#   PROJECT_NAME=example ./scripts/generate-policy.sh
#   MINIO_BUCKET=example ./scripts/generate-policy.sh
#
# Loads (in order, first found wins for unset vars):
#   MINIO_ENV_FILE, then prod/.env, then dev/.env, then .env

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="${ROOT}/policy/public-read.json.template"
OUT="${ROOT}/policy/public-read.json"

# Preserve CLI / parent-process overrides (do not let .env clobber them)
CLI_PROJECT_NAME="${PROJECT_NAME:-}"
CLI_MINIO_BUCKET="${MINIO_BUCKET:-}"

load_env_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  set -a
  # shellcheck disable=SC1090
  source <(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' -e 's/\$\$/$/g' "$f")
  set +a
}

if [[ -n "${MINIO_ENV_FILE:-}" ]]; then
  load_env_file "$MINIO_ENV_FILE"
elif [[ -f "${ROOT}/prod/.env" ]]; then
  load_env_file "${ROOT}/prod/.env"
elif [[ -f "${ROOT}/dev/.env" ]]; then
  load_env_file "${ROOT}/dev/.env"
elif [[ -f "${ROOT}/.env" ]]; then
  load_env_file "${ROOT}/.env"
fi

PROJECT_NAME="${CLI_PROJECT_NAME:-${PROJECT_NAME:-}}"
if [[ -n "$CLI_MINIO_BUCKET" ]]; then
  BUCKET="$CLI_MINIO_BUCKET"
elif [[ -n "$CLI_PROJECT_NAME" ]]; then
  # CLI project name wins over stale MINIO_BUCKET from .env
  BUCKET="$(echo "$CLI_PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
else
  BUCKET="${MINIO_BUCKET:-${PROJECT_NAME:-}}"
fi

if [[ -z "$BUCKET" ]]; then
  echo "ERROR: set PROJECT_NAME or MINIO_BUCKET (or put them in prod/.env / dev/.env)." >&2
  echo "Example: PROJECT_NAME=example ./scripts/generate-policy.sh" >&2
  exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
  echo "ERROR: template not found: $TEMPLATE" >&2
  exit 1
fi

sed "s/__BUCKET__/${BUCKET}/g" "$TEMPLATE" >"$OUT"

echo "✓ Wrote $OUT"
echo "  bucket:  $BUCKET"
echo "  public:  ${BUCKET}/public/*"
echo "  action:  s3:GetObject"
