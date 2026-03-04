# OpenAI-Compatible Proxy for Claude

Proxy server cung cấp OpenAI-compatible API, cho phép các client (VSCode extensions, Cursor, Continue.dev,...) kết nối tới Claude thông qua giao thức OpenAI.

## Architecture

```
Client (OpenAI SDK) → Proxy Server (Fastify) → pi-ai → Anthropic Claude API
                         ↓
                    API Key Auth
                   (keys.json)
```

## Prerequisites

- Node.js >= 18
- pnpm (`npm install -g pnpm`)
- Anthropic OAuth Token (từ Claude Code)

## Setup

### 1. Install dependencies

```bash
pnpm install
```

### 2. Cấu hình environment

Copy file `.env.example` thành `.env`:

```bash
cp .env.example .env
```

Chỉnh sửa `.env`:

```env
# Port chạy server
PORT=3003

# Anthropic OAuth Token (lấy từ Claude Code)
ANTHROPIC_OAUTH_TOKEN=sk-ant-oat01-...

# Secret key dùng để generate API key cho user
SECRET_KEY=my-super-secret-key

# Salt key dùng để hash API key trước khi lưu
SALT_KEY=my-salt-key

# Admin key dùng để quản lý API keys (CRUD)
ADMIN_KEY=my-admin-key

# Model mặc định khi client không chỉ định
DEFAULT_MODEL=claude-sonnet-4-6
```

**Lấy `ANTHROPIC_OAUTH_TOKEN`:** Token này lấy từ Claude Code OAuth flow. run in terminal `claude setup-token`. Format: `sk-ant-oat01-...`

### 3. Chạy server

```bash
# Development (auto-reload)
pnpm dev

# Production
pnpm build && pnpm start
```

Server sẽ chạy tại `http://localhost:3003`.

## Quản lý API Keys

API keys được quản lý qua admin endpoints, xác thực bằng `ADMIN_KEY`.

### Tạo key mới

```bash
curl -X POST http://localhost:3003/api/keys \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ADMIN_KEY>" \
  -d '{
    "name": "user-1",
    "expiresAt": "2027-01-01T00:00:00Z",
    "rateLimit": 60
  }'
```

Response trả về `key` — **lưu lại key này**, nó chỉ hiển thị 1 lần:

```json
{
  "id": "...",
  "key": "sk-abc123...",
  "name": "user-1",
  "createdAt": "...",
  "expiresAt": "2027-01-01T00:00:00Z",
  "rateLimit": 60
}
```

### Liệt kê keys

```bash
curl http://localhost:3003/api/keys \
  -H "Authorization: Bearer <ADMIN_KEY>"
```

### Xoá key

```bash
curl -X DELETE http://localhost:3003/api/keys/<KEY_ID> \
  -H "Authorization: Bearer <ADMIN_KEY>"
```

## Sử dụng API

### Cấu hình client

Sử dụng bất kỳ OpenAI-compatible client nào:

```
Base URL: http://localhost:3003/v1
API Key:  sk-... (key đã tạo ở bước trên)
```

### Ví dụ với OpenAI SDK (Node.js)

```typescript
import OpenAI from 'openai';

const client = new OpenAI({
  baseURL: 'http://localhost:3003/v1',
  apiKey: 'sk-...',
});

const response = await client.chat.completions.create({
  model: 'claude-sonnet-4-6',
  messages: [{ role: 'user', content: 'Hello!' }],
});
```

### Ví dụ với OpenAI SDK (Python)

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:3003/v1",
    api_key="sk-...",
)

response = client.chat.completions.create(
    model="claude-sonnet-4-6",
    messages=[{"role": "user", "content": "Hello!"}],
)
```

### Ví dụ với curl

```bash
# Chat completions
curl -X POST http://localhost:3003/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-..." \
  -d '{
    "model": "claude-sonnet-4-6",
    "messages": [{"role": "user", "content": "Hello!"}],
    "stream": false
  }'

# Streaming
curl -X POST http://localhost:3003/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-..." \
  -d '{
    "model": "claude-sonnet-4-6",
    "messages": [{"role": "user", "content": "Hello!"}],
    "stream": true
  }'

# List models
curl http://localhost:3003/v1/models
```

## API Endpoints

| Method | Endpoint | Auth |
|--------|----------|------|
| `POST` | `/v1/chat/completions` — Chat completions (streaming + non-streaming) | API Key |
| `POST` | `/v1/completions` — Legacy text completions | API Key |
| `GET` | `/v1/models` — Danh sach models | - |
| `GET` | `/v1/models/:id` — Chi tiet model | - |
| `POST` | `/v1/embeddings` — Embeddings (khong ho tro, tra 501) | API Key |
| `GET` | `/health` — Health check | - |
| `GET` | `/api/keys` — Liet ke API keys | Admin Key |
| `POST` | `/api/keys` — Tao API key | Admin Key |
| `DELETE` | `/api/keys/:id` — Xoa API key | Admin Key |

## Tinh nang ho tro

- Chat completions (streaming & non-streaming)
- Tool/function calling
- Multimodal content (text + image)
- System messages
- Legacy text completions
- Rate limiting (per key, per minute)
- API key management voi HMAC hashing

## Cau hinh IDE

### VSCode Extension (Kilo / Continue.dev)

```json
{
  "provider": "openai",
  "baseUrl": "http://localhost:3003/v1",
  "apiKey": "sk-...",
  "model": "claude-sonnet-4-6"
}
```

### Cursor

Settings > Models > Add Model:
- API Base URL: `http://localhost:3003/v1`
- API Key: `sk-...`
- Model: `claude-sonnet-4-6`
