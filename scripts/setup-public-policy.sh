#!/usr/bin/env bash
#
# Apply anonymous GetObject policy for <bucket>/public/* only.
#
# Uses --network container:${MINIO_CONTAINER} so mc talks to 127.0.0.1:9000
# (Docker DNS often cannot resolve container_name with underscores, and
# one-shot containers on an external network may not see Compose aliases.)
#
# Usage:
#   ./scripts/setup-public-policy.sh
#
# Optional:
#   MINIO_ENV_FILE=./prod/.env ./scripts/setup-public-policy.sh
#   PROJECT_NAME=example ./scripts/setup-public-policy.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
POLICY_FILE="${ROOT}/policy/public-read.json"
ENV_FILE="${MINIO_ENV_FILE:-}"
MC_IMAGE="${MINIO_MC_IMAGE:-quay.io/minio/mc:RELEASE.2025-08-13T08-35-41Z}"
MAX_WAIT_SEC="${MINIO_WAIT_SEC:-90}"
ENDPOINT="${MINIO_ENDPOINT:-http://127.0.0.1:9000}"

# Preserve CLI / parent-process overrides
CLI_PROJECT_NAME="${PROJECT_NAME:-}"
CLI_MINIO_BUCKET="${MINIO_BUCKET:-}"
CLI_MINIO_CONTAINER="${MINIO_CONTAINER:-}"

load_env_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  set -a
  # shellcheck disable=SC1090
  source <(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' -e 's/\$\$/$/g' "$f")
  set +a
}

if [[ -z "$ENV_FILE" ]]; then
  if [[ -f "${ROOT}/prod/.env" ]]; then
    ENV_FILE="${ROOT}/prod/.env"
  elif [[ -f "${ROOT}/dev/.env" ]]; then
    ENV_FILE="${ROOT}/dev/.env"
  elif [[ -f "${ROOT}/.env" ]]; then
    ENV_FILE="${ROOT}/.env"
  fi
fi

if [[ -n "${ENV_FILE:-}" ]]; then
  load_env_file "$ENV_FILE"
elif [[ -f "${ROOT}/.env" ]]; then
  load_env_file "${ROOT}/.env"
fi

PROJECT_NAME="${CLI_PROJECT_NAME:-${PROJECT_NAME:-}}"
if [[ -n "$CLI_MINIO_BUCKET" ]]; then
  BUCKET="$CLI_MINIO_BUCKET"
elif [[ -n "$CLI_PROJECT_NAME" ]]; then
  BUCKET="$(echo "$CLI_PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
else
  BUCKET="${MINIO_BUCKET:-${PROJECT_NAME:-}}"
fi
if [[ -n "$CLI_MINIO_CONTAINER" ]]; then
  CONTAINER="$CLI_MINIO_CONTAINER"
elif [[ -n "$CLI_PROJECT_NAME" ]]; then
  CONTAINER="${BUCKET}_minio"
else
  CONTAINER="${MINIO_CONTAINER:-${BUCKET:+${BUCKET}_minio}}"
fi

if [[ -z "$BUCKET" || -z "$CONTAINER" ]]; then
  echo "ERROR: set PROJECT_NAME (or MINIO_BUCKET + MINIO_CONTAINER)." >&2
  echo "Run: ./scripts/init-project.sh <project-name>" >&2
  exit 1
fi

: "${MINIO_ROOT_USER:?MINIO_ROOT_USER missing — set in $ENV_FILE or environment}"
: "${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD missing — set in $ENV_FILE or environment}"

# Ensure policy matches current bucket
PROJECT_NAME="$PROJECT_NAME" MINIO_BUCKET="$BUCKET" "${ROOT}/scripts/generate-policy.sh"

if [[ ! -f "$POLICY_FILE" ]]; then
  echo "ERROR: policy file not found: $POLICY_FILE" >&2
  exit 1
fi

echo "==> Waiting for container ${CONTAINER} to be running (not restarting)..."
elapsed=0
stable=0
STABLE_NEED=6
while true; do
  running="$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo false)"
  status="$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo missing)"
  restarting="$(docker inspect -f '{{.State.Restarting}}' "$CONTAINER" 2>/dev/null || echo true)"

  if [[ "$running" == "true" && "$restarting" == "false" && "$status" == "running" ]]; then
    stable=$((stable + 2))
    if (( stable >= STABLE_NEED )); then
      break
    fi
    echo "    status=running — stabilizing ${stable}/${STABLE_NEED}s..."
  else
    stable=0
    echo "    status=${status} restarting=${restarting} — waiting..."
  fi

  if (( elapsed >= MAX_WAIT_SEC )); then
    echo "ERROR: ${CONTAINER} not healthy after ${MAX_WAIT_SEC}s (status=${status}, restarting=${restarting})." >&2
    echo "==> docker ps -a:" >&2
    docker ps -a --filter "name=${CONTAINER}" >&2 || true
    echo "==> last logs:" >&2
    docker logs --tail 80 "$CONTAINER" >&2 || true
    exit 1
  fi

  sleep 2
  elapsed=$((elapsed + 2))
done

echo "==> Applying anonymous public-read policy (GetObject on ${BUCKET}/public/*)..."
echo "    via:      --network container:${CONTAINER}"
echo "    endpoint: $ENDPOINT"
echo "    policy:   $POLICY_FILE"

docker run --rm \
  --network "container:${CONTAINER}" \
  -e MINIO_ROOT_USER \
  -e MINIO_ROOT_PASSWORD \
  -e BUCKET="$BUCKET" \
  -e ENDPOINT="$ENDPOINT" \
  -e MAX_WAIT_SEC="$MAX_WAIT_SEC" \
  -v "${POLICY_FILE}:/policy/public-read.json:ro" \
  --entrypoint /bin/sh \
  "$MC_IMAGE" \
  -c '
    set -e
    elapsed=0
    until mc alias set local "$ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"; do
      if [ "$elapsed" -ge "$MAX_WAIT_SEC" ]; then
        echo "ERROR: could not reach MinIO at $ENDPOINT after ${MAX_WAIT_SEC}s" >&2
        exit 1
      fi
      echo "waiting for minio at $ENDPOINT..."
      sleep 2
      elapsed=$((elapsed + 2))
    done
    mc mb --ignore-existing "local/${BUCKET}"
    mc anonymous set-json /policy/public-read.json "local/${BUCKET}"
    echo
    echo "==> Verifying policy..."
    mc anonymous get-json "local/${BUCKET}"
  '

echo
echo "✓ MinIO public policy configured successfully."
echo "✓ Public prefix: ${BUCKET}/public/*"
echo "✓ Allowed action: s3:GetObject"
echo "✓ Everything else stays private."
