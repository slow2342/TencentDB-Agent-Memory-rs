# ==============================================================================
# Memory Hub — Panel + Knowledge 合并镜像
# ==============================================================================

# ── Builder base ─────────────────────────────────────────────────────────────
FROM node:22-slim AS builder-base

ARG APT_MIRROR=deb.debian.org
RUN if [ "$APT_MIRROR" != "deb.debian.org" ]; then \
      sed -i "s|deb.debian.org|${APT_MIRROR}|g" /etc/apt/sources.list.d/debian.sources 2>/dev/null || \
      sed -i "s|deb.debian.org|${APT_MIRROR}|g" /etc/apt/sources.list 2>/dev/null || true; \
    fi

RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 make g++ git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# npm@10.9.8 有 arborist crash，升到 11
RUN npm install -g npm@11 --no-audit --no-fund

# ── Panel ────────────────────────────────────────────────────────────────────
FROM builder-base AS panel
WORKDIR /build
COPY panel/package*.json ./
RUN npm install --no-audit --no-fund
COPY panel/ ./
RUN npm run build

# ── Knowledge ────────────────────────────────────────────────────────────────
FROM builder-base AS knowledge
WORKDIR /build
COPY knowledge/package*.json ./
RUN npm install --no-audit --no-fund
COPY knowledge/ ./
RUN npm run build

# ── Runtime ──────────────────────────────────────────────────────────────────
FROM node:22-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV NODE_ENV=production \
    PANEL_PORT=8125 \
    KNOWLEDGE_PORT=8424 \
    REMOTE_INSTANCE_ID="" \
    REMOTE_INSTANCE_NAME="" \
    REMOTE_INSTANCE_URL="" \
    REMOTE_INSTANCE_KEY="" \
    KNOWLEDGE_LLM_BINDING_SYNC=1 \
    KNOWLEDGE_LLM_PROXY_BASE_URL="" \
    LLM_MODE=proxy \
    LLM_PROTOCOL=openai \
    LLM_PROVIDER=custom \
    LLM_API_KEY="" \
    LLM_BASE_URL="" \
    LLM_MODEL=Memory-Model \
    LLM_MAX_TOKENS=32768 \
    LLM_TIMEOUT_MS=1200000 \
    KNOWLEDGE_DATA_DIR=/data/knowledge \
    KNOWLEDGE_DB_PATH=/data/knowledge/knowledge.db \
    LOG_LEVEL=info \
    LOG_FORMAT=json

# Panel
COPY --from=panel /build/dist /app/panel/dist
COPY --from=panel /build/node_modules /app/panel/node_modules
COPY --from=panel /build/package.json /app/panel/package.json

# Knowledge
COPY --from=knowledge /build/dist /app/knowledge/dist
COPY --from=knowledge /build/node_modules /app/knowledge/node_modules
COPY --from=knowledge /build/package.json /app/knowledge/package.json
COPY --from=knowledge /build/openapi.yaml /app/knowledge/openapi.yaml

COPY start-combined.sh /usr/local/bin/start-combined.sh
RUN chmod +x /usr/local/bin/start-combined.sh && mkdir -p /data/knowledge /app/panel/config

EXPOSE 8125 8424

HEALTHCHECK --interval=20s --timeout=8s --retries=15 --start-period=45s \
  CMD curl -fsS http://127.0.0.1:${PANEL_PORT}/health >/dev/null && curl -fsS http://127.0.0.1:${KNOWLEDGE_PORT}/health >/dev/null || exit 1

CMD ["/usr/local/bin/start-combined.sh"]
