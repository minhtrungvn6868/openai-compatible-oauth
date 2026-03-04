# Deploy & Update Guide

Hướng dẫn dành cho **maintainer** (người build và publish release) và **end-user** (người cập nhật version mới).

---

## Dành cho Maintainer

### Quy trình release version mới

#### 1. Update version

```bash
# Sửa version trong package.json
# Ví dụ: 1.0.0 → 1.1.0
```

#### 2. Build release

```bash
pnpm release
```

Output:
```
release/
  ├── server.mjs        # Bundled server (~7.6MB)
  ├── public/
  │   ├── admin.html
  │   └── index.html
  └── package.json

claude-proxy.tar.gz     # Archive (~1.5MB) — file upload lên GitHub Releases
```

#### 3. Tạo Git tag & push

```bash
git add .
git commit -m "release: v1.1.0"
git tag v1.1.0
git push origin main --tags
```

#### 4. Tạo GitHub Release

```bash
gh release create v1.1.0 claude-proxy.tar.gz \
  --title "v1.1.0" \
  --notes "Changelog:
- Feature A
- Fix B"
```

Hoặc tạo thủ công trên GitHub UI:
1. Vào **Releases** → **Draft a new release**
2. Chọn tag `v1.1.0`
3. Upload file `claude-proxy.tar.gz`
4. Viết changelog → **Publish release**

#### 5. Verify

```bash
# Kiểm tra link download hoạt động
curl -fsSL https://github.com/minhtrungvn6868/openai-compatible-oauth/releases/latest/download/claude-proxy.tar.gz -o /dev/null -w "%{http_code}"
# Expected: 200
```

---

## Dành cho End-User

### Cài đặt lần đầu

Xem [README - Quick Install](../readme.md#quick-install).

### Update lên version mới

#### Cách 1: Chạy lại installer (Khuyến nghị)

Installer sẽ detect `.env` đã tồn tại và hỏi có overwrite không. Chọn **N** để giữ config cũ.

**Mac / Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/minhtrungvn6868/openai-compatible-oauth/main/install.sh | sh
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/minhtrungvn6868/openai-compatible-oauth/main/install.ps1 | iex
```

Khi được hỏi `Overwrite? [y/N]` → nhấn **N** hoặc Enter để giữ config hiện tại.

#### Cách 2: Update thủ công

```bash
# 1. Dừng server
claude-proxy stop

# 2. Backup config
cp ~/.claude-proxy/.env ~/.claude-proxy/.env.bak
cp ~/.claude-proxy/keys.json ~/.claude-proxy/keys.json.bak

# 3. Download version mới
curl -fsSL https://github.com/minhtrungvn6868/openai-compatible-oauth/releases/latest/download/claude-proxy.tar.gz \
  | tar -xz -C ~/.claude-proxy/

# 4. Restore config (nếu bị overwrite)
cp ~/.claude-proxy/.env.bak ~/.claude-proxy/.env
cp ~/.claude-proxy/keys.json.bak ~/.claude-proxy/keys.json

# 5. Khởi động lại
claude-proxy start
```

#### Cách 3: Update version cụ thể

```bash
# Chỉ định version qua biến môi trường
CLAUDE_PROXY_VERSION=v1.1.0 curl -fsSL https://raw.githubusercontent.com/minhtrungvn6868/openai-compatible-oauth/main/install.sh | sh
```

### Kiểm tra version hiện tại

```bash
# Xem health endpoint
curl -s http://localhost:3003/health
```

### Rollback về version cũ

```bash
# 1. Dừng server
claude-proxy stop

# 2. Tải version cũ
CLAUDE_PROXY_VERSION=v1.0.0 curl -fsSL https://raw.githubusercontent.com/minhtrungvn6868/openai-compatible-oauth/main/install.sh | sh
```

---

## Cấu trúc thư mục cài đặt

```
~/.claude-proxy/
  ├── server.mjs              # Server bundle (thay thế khi update)
  ├── public/                  # Static files (thay thế khi update)
  │   ├── admin.html
  │   └── index.html
  ├── package.json             # Module config (thay thế khi update)
  ├── claude-proxy-ctl.sh      # Launcher script (thay thế khi update)
  ├── .env                     # Config (GIỮ NGUYÊN khi update)
  ├── keys.json                # API keys data (GIỮ NGUYÊN khi update)
  ├── .pid                     # PID file (runtime)
  └── server.log               # Log file (runtime)
```

**Quan trọng:** Khi update, 2 file sau **không bị ghi đè** nếu chọn giữ config:
- `.env` — chứa token và secret keys
- `keys.json` — chứa API keys đã tạo

---

## Auto-start Service

### macOS (launchd)

```bash
# Xem trạng thái
launchctl list | grep claude-proxy

# Dừng service
launchctl unload ~/Library/LaunchAgents/com.claude-proxy.server.plist

# Khởi động lại service
launchctl load ~/Library/LaunchAgents/com.claude-proxy.server.plist

# Xem file config
cat ~/Library/LaunchAgents/com.claude-proxy.server.plist
```

### Linux (systemd)

```bash
# Xem trạng thái
systemctl --user status claude-proxy

# Dừng
systemctl --user stop claude-proxy

# Khởi động
systemctl --user start claude-proxy

# Xem log
journalctl --user -u claude-proxy -f

# Tắt auto-start
systemctl --user disable claude-proxy
```

### Windows (Task Scheduler)

```powershell
# Xem trạng thái
schtasks /query /tn "ClaudeProxy"

# Chạy ngay
schtasks /run /tn "ClaudeProxy"

# Xóa task
schtasks /delete /tn "ClaudeProxy" /f
```

---

## Troubleshooting

### Server không khởi động

```bash
# Kiểm tra log
claude-proxy logs

# Kiểm tra port có bị chiếm không
lsof -i :3003   # Mac/Linux
netstat -ano | findstr 3003   # Windows
```

### Token hết hạn

```bash
# 1. Lấy token mới
claude setup-token

# 2. Cập nhật .env
# Sửa giá trị ANTHROPIC_OAUTH_TOKEN trong ~/.claude-proxy/.env

# 3. Restart
claude-proxy restart
```

### Quên ADMIN KEY

```bash
# ADMIN_KEY nằm trong file .env
grep ADMIN_KEY ~/.claude-proxy/.env
```

### Gỡ cài đặt hoàn toàn

```bash
claude-proxy uninstall
```

Lệnh này sẽ:
- Dừng server
- Xóa auto-start service
- Xóa thư mục `~/.claude-proxy/`
- Xóa symlink `claude-proxy` khỏi PATH
