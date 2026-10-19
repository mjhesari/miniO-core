#!/usr/bin/env bash
#
# Bootstrap miniO-core for a host project (sibling or clone).
#
# Usage:
#   ./scripts/init-project.sh example
#   ./scripts/init-project.sh example --host assets.example.com
#   ./scripts/init-project.sh englishpsd --host assets.englishpsd.ir --network englishpsd_internal
#
# Creates/updates:
#   .env                 (PROJECT_NAME + shared defaults)
#   dev/.env             (from .env.example)
#   prod/.env.example    values filled for copy-on-server
#   policy/public-read.json

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
  echo "Usage: $0 <project-name> [--host <public-assets-host>] [--network <docker-network>]" >&2
  echo "Example: $0 example --host assets.example.com" >&2
  echo "Example: $0 englishpsd --host assets.englishpsd.ir --network englishpsd_internal" >&2
  exit 1
}

PROJECT_NAME="${1:-}"
PUBLIC_HOST=""
NETWORK_OVERRIDE=""
shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      PUBLIC_HOST="${2:-}"
      [[ -n "$PUBLIC_HOST" ]] || usage
      shift 2
      ;;
    --network)
      NETWORK_OVERRIDE="${2:-}"
      [[ -n "$NETWORK_OVERRIDE" ]] || usage
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$PROJECT_NAME" ]] || usage

# S3 bucket names: lowercase, no underscores preferred (we allow hyphens)
BUCKET="$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
CONTAINER="${BUCKET}_minio"
NETWORK="${NETWORK_OVERRIDE:-${BUCKET}_network}"
PUBLIC_HOST="${PUBLIC_HOST:-assets.${BUCKET}.local}"

write_if_missing() {
  local path="$1"
  local content="$2"
  if [[ -f "$path" ]]; then
    echo "  skip (exists): $path"
    return 0
  fi
  printf '%s\n' "$content" >"$path"
  echo "  wrote: $path"
}

echo "==> Initializing miniO-core for project: $PROJECT_NAME"
echo "    bucket:    $BUCKET"
echo "    container: $CONTAINER"
echo "    network:   $NETWORK"
echo "    host:      $PUBLIC_HOST"

write_if_missing "${ROOT}/.env" "$(cat <<EOF
# Shared project identity for miniO-core (repo can sit beside any app)
PROJECT_NAME=${PROJECT_NAME}
MINIO_BUCKET=${BUCKET}
MINIO_CONTAINER=${CONTAINER}
MINIO_NETWORK=${NETWORK}
MINIO_PUBLIC_HOST=${PUBLIC_HOST}
EOF
)"

write_if_missing "${ROOT}/dev/.env" "$(cat <<EOF
# Local MinIO — match your app MINIO_ACCESS_KEY / MINIO_SECRET_KEY
PROJECT_NAME=${PROJECT_NAME}
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin123
MINIO_BUCKET=${BUCKET}
MINIO_CONTAINER=${CONTAINER}
MINIO_NETWORK=${NETWORK}
EOF
)"

# Always refresh prod example so clone stays project-aware
cat >"${ROOT}/prod/.env.example" <<EOF
# Copy to prod/.env on the server.
# Docker Compose: write \$\$ for a literal \$ in the value.
PROJECT_NAME=${PROJECT_NAME}
MINIO_ROOT_USER=${BUCKET}_admin
MINIO_ROOT_PASSWORD=CHANGE_ME_USE_STRONG_PASSWORD
MINIO_BUCKET=${BUCKET}
MINIO_CONTAINER=${CONTAINER}
MINIO_NETWORK=${NETWORK}
MINIO_PUBLIC_HOST=${PUBLIC_HOST}
EOF
echo "  wrote: ${ROOT}/prod/.env.example"

PROJECT_NAME="$PROJECT_NAME" MINIO_BUCKET="$BUCKET" "${ROOT}/scripts/generate-policy.sh"

echo
echo "✓ Done. Next:"
echo "  Dev:  cd dev && docker compose --env-file .env up -d"
echo "  Prod: copy prod/.env.example → prod/.env, create external network ${NETWORK},"
echo "        then: cd prod && docker compose --env-file .env up -d"
echo "  Policy: ./scripts/setup-public-policy.sh"
