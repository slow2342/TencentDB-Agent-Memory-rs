#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKSPACE_ROOT="$(dirname "$REPO_ROOT")"

TMC_DIR="${TMC_DIR:-$REPO_ROOT/MemoryPanel}"
KNOWLEDGE_DIR="${KNOWLEDGE_DIR:-$REPO_ROOT/MemoryKnowledge}"
IMAGE_NAME="${IMAGE_NAME:-team-memory-panel-knowledge}"
IMAGE_TAG="${IMAGE_TAG:-amd64}"
CTX_DIR="${CTX_DIR:-$WORKSPACE_ROOT/panel-knowledge-builder}"
KEEP_CTX="${KEEP_CTX:-0}"
PREPARE_ONLY="${PREPARE_ONLY:-0}"
PLATFORM="${PLATFORM:-linux/amd64}"

err() { echo "[build] error: $*" >&2; exit 1; }

[[ -f "$TMC_DIR/package.json" ]] || err "MemoryPanel not found at $TMC_DIR"
[[ -f "$KNOWLEDGE_DIR/package.json" ]] || err "MemoryKnowledge not found at $KNOWLEDGE_DIR"
[[ -f "$SCRIPT_DIR/Dockerfile" ]] || err "Dockerfile not found"
[[ -f "$SCRIPT_DIR/start-combined.sh" ]] || err "start-combined.sh not found"

echo "[build] panel=$TMC_DIR knowledge=$KNOWLEDGE_DIR ctx=$CTX_DIR image=$IMAGE_NAME:$IMAGE_TAG"

[[ "$KEEP_CTX" == "1" ]] || rm -rf "$CTX_DIR"
mkdir -p "$CTX_DIR"

# rsync panel — exclude: .git, node_modules, dist, config secrets, docs, tests, docker
echo "[build] rsync panel → $CTX_DIR/panel/"
rsync -a --delete \
  --exclude .git --exclude node_modules --exclude web/node_modules \
  --exclude dist --exclude build --exclude coverage --exclude data \
  --exclude .claude --exclude .env --exclude '.env.*' \
  --exclude 'config/metadata-instances.json' --exclude 'config/*.yaml' --exclude 'config/*.yml' \
  --exclude docs/ --exclude tests/ --exclude scripts/ --exclude docker/ \
  --exclude 'e2e-*.sh' --exclude '*.md' \
  --exclude pnpm-lock.yaml --exclude pnpm-workspace.yaml --exclude vitest.config.ts \
  "$TMC_DIR"/ "$CTX_DIR/panel"/

# rsync knowledge — exclude: .git, node_modules, dist, docs, tests, docker
echo "[build] rsync knowledge → $CTX_DIR/knowledge/"
rsync -a --delete \
  --exclude .git --exclude node_modules --exclude dist \
  --exclude coverage --exclude data --exclude .claude \
  --exclude .env --exclude '.env.*' --exclude bin/ --exclude docs/ \
  --exclude __tests__/ --exclude docker/ --exclude 'docker-compose*.yml' \
  --exclude Dockerfile --exclude .dockerignore --exclude '*.md' \
  --exclude pnpm-lock.yaml --exclude vitest.config.ts --exclude start.sh \
  "$KNOWLEDGE_DIR"/ "$CTX_DIR/knowledge"/

cp "$SCRIPT_DIR/Dockerfile" "$CTX_DIR"/
cp "$SCRIPT_DIR/start-combined.sh" "$CTX_DIR"/
cp "$SCRIPT_DIR/README.md" "$CTX_DIR"/
[[ -f "$SCRIPT_DIR/.dockerignore" ]] && cp "$SCRIPT_DIR/.dockerignore" "$CTX_DIR"/

if [[ "$PREPARE_ONLY" == "1" ]]; then
  echo "[build] context ready: $CTX_DIR"
  exit 0
fi

echo "[build] docker build --platform $PLATFORM -t $IMAGE_NAME:$IMAGE_TAG $CTX_DIR"
docker build --platform "$PLATFORM" -t "$IMAGE_NAME:$IMAGE_TAG" "$CTX_DIR"
echo "[build] done: $IMAGE_NAME:$IMAGE_TAG"
