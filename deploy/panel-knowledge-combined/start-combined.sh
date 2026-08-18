#!/usr/bin/env bash
set -euo pipefail

INSTANCES_FILE="/app/panel/config/metadata-instances.json"
PANEL_PORT="${PANEL_PORT:-8125}"
KNOWLEDGE_PORT="${KNOWLEDGE_PORT:-8424}"
KNOWLEDGE_DATA_DIR="${KNOWLEDGE_DATA_DIR:-/data/knowledge}"

mkdir -p /app/panel/config "$KNOWLEDGE_DATA_DIR" "$(dirname "${KNOWLEDGE_DB_PATH:-$KNOWLEDGE_DATA_DIR/knowledge.db}")"

# Generate instance config from env if not provided via volume mount
if [[ ! -f "$INSTANCES_FILE" ]]; then
  : "${REMOTE_INSTANCE_URL:?REMOTE_INSTANCE_URL is required (or mount metadata-instances.json)}"
  : "${REMOTE_INSTANCE_KEY:?REMOTE_INSTANCE_KEY is required (or mount metadata-instances.json)}"

  INSTANCE_ID="${REMOTE_INSTANCE_ID:-default}"
  INSTANCE_NAME="${REMOTE_INSTANCE_NAME:-$INSTANCE_ID}"
  PROXY_ENDPOINT=""
  [[ -n "${REMOTE_INSTANCE_PROXY_URL:-}" ]] && PROXY_ENDPOINT="\"proxy_endpoint\": \"${REMOTE_INSTANCE_PROXY_URL}\","

  python3 -c "
import json
from pathlib import Path
Path('$INSTANCES_FILE').write_text(json.dumps({'instances': [{
    'id': '$INSTANCE_ID', 'name': '$INSTANCE_NAME',
    'gateway_endpoint': '$REMOTE_INSTANCE_URL', $PROXY_ENDPOINT
    'api_key': '$REMOTE_INSTANCE_KEY'
}]}, indent=2))
"
fi

cleanup() { jobs -p | xargs -r kill 2>/dev/null || true; }
trap cleanup INT TERM EXIT

KS_INTERNAL_URL="http://127.0.0.1:${KNOWLEDGE_PORT}"
KS_PUBLIC_URL="${KNOWLEDGE_PUBLIC_BASE_URL:-${KS_INTERNAL_URL}/v3}"

export API_PREFIX="${API_PREFIX:-/v3}"
export KNOWLEDGE_DATA_DIR="$KNOWLEDGE_DATA_DIR"
export KNOWLEDGE_DB_PATH="${KNOWLEDGE_DB_PATH:-$KNOWLEDGE_DATA_DIR/knowledge.db}"
export KNOWLEDGE_PUBLIC_BASE_URL="$KS_PUBLIC_URL"
export TMC_CALLBACK_URL="${TMC_CALLBACK_URL:-http://127.0.0.1:${PANEL_PORT}}"
export LLM_MODE="${LLM_MODE:-proxy}"
export LLM_PROVIDER="${LLM_PROVIDER:-custom}"
export LLM_API_KEY="${LLM_API_KEY:-}"
export LLM_BASE_URL="${LLM_BASE_URL:-}"
export LLM_MODEL="${LLM_MODEL:-Memory-Model}"
export LLM_MAX_TOKENS="${LLM_MAX_TOKENS:-32768}"
export LLM_TIMEOUT_MS="${LLM_TIMEOUT_MS:-1200000}"

SYNC_ENV="${KNOWLEDGE_LLM_BINDING_SYNC:-1}"
[[ "$LLM_MODE" == "proxy" ]] && SYNC_ENV=1

# Log rotation
LOG_DIR="${LOG_DIR:-$KNOWLEDGE_DATA_DIR/logs}"
mkdir -p "$LOG_DIR"
PANEL_LOG="$LOG_DIR/panel.log"
KNOWLEDGE_LOG="$LOG_DIR/knowledge.log"
[[ -f "$PANEL_LOG" ]] && mv "$PANEL_LOG" "$PANEL_LOG.prev"
[[ -f "$KNOWLEDGE_LOG" ]] && mv "$KNOWLEDGE_LOG" "$KNOWLEDGE_LOG.prev"

# Start Knowledge service
cd /app/knowledge
PORT="${KNOWLEDGE_PORT}" LOG_LEVEL="${LOG_LEVEL:-info}" \
  node "$(test -f dist/server.js && echo dist/server.js || echo dist/server.mjs)" 2>&1 \
  | tee -a "$KNOWLEDGE_LOG" &
KNOWLEDGE_PID=$!

# Wait for Knowledge to be ready
for i in $(seq 1 120); do
  curl -fsS "http://127.0.0.1:${KNOWLEDGE_PORT}/health" >/dev/null 2>&1 && break
  sleep 0.5
  if ! kill -0 "$KNOWLEDGE_PID" 2>/dev/null; then
    echo "knowledge service exited before ready" >&2
    wait "$KNOWLEDGE_PID"
  fi
done
echo "[start] knowledge ready on :${KNOWLEDGE_PORT}"

# Start Panel service
cd /app/panel
HOST=0.0.0.0 PORT="${PANEL_PORT}" \
  METADATA_INSTANCES_CONFIG="$INSTANCES_FILE" \
  METADATA_REMOTE_TIMEOUT_MS="${METADATA_REMOTE_TIMEOUT_MS:-15000}" \
  KNOWLEDGE_SERVICE_URL="$KS_INTERNAL_URL" \
  KNOWLEDGE_AUTH_TOKEN="${KNOWLEDGE_AUTH_TOKEN:-}" \
  KNOWLEDGE_TIMEOUT_MS="${KNOWLEDGE_TIMEOUT_MS:-15000}" \
  KNOWLEDGE_LLM_BINDING_SYNC="$SYNC_ENV" \
  KNOWLEDGE_LLM_PROXY_BASE_URL="${KNOWLEDGE_LLM_PROXY_BASE_URL:-}" \
  LOG_LEVEL="${LOG_LEVEL:-info}" \
  LOG_FORMAT="${LOG_FORMAT:-json}" \
  node dist/index.js 2>&1 \
  | tee -a "$PANEL_LOG" &
PANEL_PID=$!

for i in $(seq 1 120); do
  curl -fsS "http://127.0.0.1:${PANEL_PORT}/health" >/dev/null 2>&1 && break
  sleep 0.5
  if ! kill -0 "$PANEL_PID" 2>/dev/null; then
    echo "panel service exited" >&2
    wait "$PANEL_PID"
  fi
done
echo "[start] panel ready on :${PANEL_PORT}"

wait -n "$KNOWLEDGE_PID" "$PANEL_PID"
