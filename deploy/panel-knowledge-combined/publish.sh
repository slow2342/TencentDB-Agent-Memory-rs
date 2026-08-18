#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKSPACE_ROOT="$(dirname "$REPO_ROOT")"

TMC_DIR="${TMC_DIR:-$REPO_ROOT/MemoryPanel}"
KNOWLEDGE_DIR="${KNOWLEDGE_DIR:-$REPO_ROOT/MemoryKnowledge}"
CTX_DIR="${CTX_DIR:-$WORKSPACE_ROOT/panel-knowledge-builder}"
VERSION="${VERSION:-1.0.0-beta.1}"
HUB_IMAGE="${HUB_IMAGE:-agentmemory/memory-hub}"
LOCAL_NAME="${LOCAL_NAME:-team-memory-panel-knowledge}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
BUILDER="${BUILDER:-multiarch}"
DRY_RUN="${DRY_RUN:-0}"
PUSH="${PUSH:-1}"
ALSO_BETA="${ALSO_BETA:-1}"
ALSO_LATEST="${ALSO_LATEST:-0}"
SECRET_SCAN="${SECRET_SCAN:-$TMC_DIR/scripts/secret-scan.sh}"

err() { echo "[publish] error: $*" >&2; exit 1; }
log() { echo "[publish] $*"; }

[[ -f "$TMC_DIR/package.json" ]] || err "MemoryPanel not found at $TMC_DIR"
[[ -f "$KNOWLEDGE_DIR/package.json" ]] || err "MemoryKnowledge not found at $KNOWLEDGE_DIR"
[[ -f "$SECRET_SCAN" ]] || err "secret-scan not found at $SECRET_SCAN"
command -v docker >/dev/null || err "docker required"
command -v rsync >/dev/null || err "rsync required"

# 1) Secret scan source code
log "scanning source code..."
(cd "$TMC_DIR" && bash "$SECRET_SCAN" src web/src config package.json)
(cd "$KNOWLEDGE_DIR" && bash "$SECRET_SCAN" src .env.example package.json)

# 2) Prepare build context
log "preparing context → $CTX_DIR"
KEEP_CTX=1 PREPARE_ONLY=1 CTX_DIR="$CTX_DIR" IMAGE_TAG="scan-$VERSION" \
  bash "$SCRIPT_DIR/build.sh"

[[ -f "$CTX_DIR/panel/package.json" && -f "$CTX_DIR/knowledge/package.json" ]] \
  || err "context preparation failed"

# 3) Scan build context
(cd "$CTX_DIR" && bash "$SECRET_SCAN" panel knowledge Dockerfile start-combined.sh .dockerignore)

[[ "$DRY_RUN" == "1" ]] && { log "DRY_RUN: context ready at $CTX_DIR"; exit 0; }

# 4) Build and push
HUB_TAGS=(-t "${HUB_IMAGE}:${VERSION}")
[[ "$ALSO_BETA" == "1" ]] && HUB_TAGS+=(-t "${HUB_IMAGE}:beta")
[[ "$ALSO_LATEST" == "1" ]] && HUB_TAGS+=(-t "${HUB_IMAGE}:latest")

if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
  log "creating buildx builder: $BUILDER"
  docker buildx create --name "$BUILDER" --driver docker-container --use
fi
docker buildx use "$BUILDER"
docker buildx inspect --bootstrap >/dev/null

if [[ "$PUSH" == "1" ]]; then
  log "building and pushing ${HUB_IMAGE}:${VERSION} ($PLATFORMS)"
  docker buildx build --builder "$BUILDER" --platform "$PLATFORMS" \
    "${HUB_TAGS[@]}" --push "$CTX_DIR"
  log "pushed ${HUB_IMAGE}:${VERSION}"
else
  LOAD_PLATFORM="${LOAD_PLATFORM:-linux/amd64}"
  log "building locally ($LOAD_PLATFORM) as ${LOCAL_NAME}:${VERSION}"
  docker buildx build --builder "$BUILDER" --platform "$LOAD_PLATFORM" \
    -t "${LOCAL_NAME}:${VERSION}" --load "$CTX_DIR"

  # Verify no secrets leaked into image
  cid=$(docker create "${LOCAL_NAME}:${VERSION}")
  trap "docker rm -f '$cid' >/dev/null 2>&1 || true" EXIT
  if docker export "$cid" | tar -t 2>/dev/null \
    | grep -qE '(\.env$|metadata-instances\.json)'; then
    err "sensitive files found in image"
  fi
  trap - EXIT
  docker rm -f "$cid" >/dev/null 2>&1
  log "local image ready: ${LOCAL_NAME}:${VERSION}"
fi

log "done. verify: docker buildx imagetools inspect ${HUB_IMAGE}:${VERSION}"
