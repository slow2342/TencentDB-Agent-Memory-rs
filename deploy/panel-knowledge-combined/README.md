# Memory Hub

合并镜像：Panel（团队/Agent/Knowledge 管理控制台）+ Knowledge Service（Wiki/CodeGraph 知识服务）。

镜像：[`agentmemory/memory-hub`](https://hub.docker.com/r/agentmemory/memory-hub)

## 快速开始

### 1. 准备实例配置

```json
{
  "instances": [{
    "id": "mem-xxxxxxxx",
    "name": "My Memory",
    "gateway_endpoint": "https://memory.ap-shanghai.tencenttdai.com",
    "api_key": "your-api-key"
  }]
}
```

### 2. 启动

```bash
docker run -d --name memory-hub \
  -p 8125:8125 -p 8424:8424 \
  -v memory-hub:/data/knowledge \
  -v /path/to/metadata-instances.json:/app/panel/config/metadata-instances.json:ro \
  -e KNOWLEDGE_PUBLIC_BASE_URL=http://10.2.3.4:8424/v3 \
  -e KNOWLEDGE_LLM_PROXY_BASE_URL=https://memory.ap-shanghai.tencenttdai.com \
  agentmemory/memory-hub:latest
```

### 必填配置

| 配置 | 说明 |
|------|------|
| `metadata-instances.json` | 实例 ID、Gateway 地址、API Key |
| `KNOWLEDGE_PUBLIC_BASE_URL` | KS 外部地址（必须含 `/v3`） |
| `KNOWLEDGE_LLM_PROXY_BASE_URL` | Gateway 地址（与 `gateway_endpoint` 相同） |

## 可选配置

### LLM

| 变量 | 默认 | 说明 |
|------|------|------|
| `LLM_PROTOCOL` | `openai` | `openai` 或 `anthropic` |
| `LLM_MODEL` | `Memory-Model` | 模型 ID |
| `LLM_MODE` | `proxy` | `proxy`=走 Gateway；`custom`=直连端点 |
| `LLM_API_KEY` | - | `custom` 模式必填 |
| `LLM_BASE_URL` | - | `custom` 模式必填 |

### 网络

| 变量 | 默认 | 说明 |
|------|------|------|
| `PANEL_PORT` | `8125` | Panel 端口 |
| `KNOWLEDGE_PORT` | `8424` | KS 端口 |
| `KNOWLEDGE_DATA_DIR` | `/data/knowledge` | KS 数据目录 |

### 日志

| 变量 | 默认 | 说明 |
|------|------|------|
| `LOG_LEVEL` | `info` | `debug`/`info`/`warn`/`error` |
| `LOG_FORMAT` | `json` | `json` 或 `text` |
| `LOG_DIR` | `/data/knowledge/logs` | 日志目录 |

## 访问地址

| 服务 | 地址 |
|------|------|
| Panel API | `http://localhost:8125/api/v1/` |
| KS Health | `http://localhost:8424/health` |
| KS API | `http://localhost:8424/v3/` |

## Custom 模式

直连 LLM，不走 Gateway：

```bash
docker run -d --name memory-hub \
  -p 8125:8125 -p 8424:8424 \
  -v memory-hub:/data/knowledge \
  -v /path/to/metadata-instances.json:/app/panel/config/metadata-instances.json:ro \
  -e KNOWLEDGE_PUBLIC_BASE_URL=http://10.2.3.4:8424/v3 \
  -e LLM_MODE=custom \
  -e LLM_API_KEY=sk-your-key \
  -e LLM_BASE_URL=https://api.openai.com/v1 \
  -e LLM_MODEL=gpt-4o \
  agentmemory/memory-hub:latest
```

## 构建

```bash
cd deploy/panel-knowledge-combined

# 本地构建
IMAGE_TAG=1.0.0-beta.1 ./build.sh

# 发布到 Docker Hub
VERSION=1.0.0-beta.1 ./publish.sh
```

## FAQ

**Q: 容器内访问宿主机服务？**
用 `172.17.0.1`（docker0 网桥）或 `--add-host=host.docker.internal:host-gateway`

**Q: wiki ingest 超时？**
```bash
-e LLM_TIMEOUT_MS=1800000  # 30 分钟
```

**Q: tools/list 返回 404？**
`KNOWLEDGE_PUBLIC_BASE_URL` 必须含 `/v3` 前缀

**Q: 切换 LLM 协议报错？**
确保 `LLM_PROTOCOL` 和 `LLM_MODEL` 配套：
- OpenAI: `-e LLM_PROTOCOL=openai -e LLM_MODEL=Memory-Model`
- Anthropic: `-e LLM_PROTOCOL=anthropic -e LLM_MODEL=ep-pksklwtb`
