#!/bin/sh
set -e

# ─────────────────────────────────────────────────────
# Claude Proxy Server — One-Command Installer
# Usage: curl -fsSL https://<url>/install.sh | sh
# ─────────────────────────────────────────────────────

REPO="minhtrungvn6868/openai-compatible-oauth"
INSTALL_DIR="$HOME/.claude-proxy"
BIN_DIR="/usr/local/bin"
VERSION="${CLAUDE_PROXY_VERSION:-latest}"

# When piped via `curl | sh`, stdin is the script itself.
# We must read user input from /dev/tty instead.
if [ ! -t 0 ]; then
  if [ -e /dev/tty ]; then
    TTY=/dev/tty
  else
    echo "Error: Cannot read user input. Run the script directly instead:"
    echo "  curl -fsSL <url>/install.sh -o install.sh && sh install.sh"
    exit 1
  fi
else
  TTY=/dev/stdin
fi

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET=''
fi

info()  { printf "${CYAN}%s${RESET}\n" "$1"; }
ok()    { printf "  ${GREEN}✓${RESET} %s\n" "$1"; }
fail()  { printf "  ${RED}✗${RESET} %s\n" "$1"; }
warn()  { printf "  ${YELLOW}!${RESET} %s\n" "$1"; }

main() {
  print_banner
  check_node
  download_release
  setup_env
  create_launcher
  setup_autostart
  print_summary
}

print_banner() {
  printf "\n"
  printf "  ${BOLD}Claude Proxy Server${RESET} — Installer\n"
  printf "  OpenAI-compatible API for Claude\n"
  printf "\n"
}

check_node() {
  info "[1/5] Checking prerequisites..."

  if ! command -v node > /dev/null 2>&1; then
    fail "Node.js >= 18 is required"
    printf "\n"
    printf "  Install Node.js:\n"
    printf "    macOS:   brew install node\n"
    printf "    Linux:   curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt-get install -y nodejs\n"
    printf "    General: https://nodejs.org\n"
    exit 1
  fi

  NODE_MAJOR=$(node -v | sed 's/v//' | cut -d. -f1)
  if [ "$NODE_MAJOR" -lt 18 ]; then
    fail "Node.js >= 18 required (found $(node -v))"
    exit 1
  fi

  ok "Node.js $(node -v)"
}

download_release() {
  info "[2/5] Downloading..."

  if [ "$VERSION" = "latest" ]; then
    DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/claude-proxy.tar.gz"
  else
    DOWNLOAD_URL="https://github.com/$REPO/releases/download/$VERSION/claude-proxy.tar.gz"
  fi

  mkdir -p "$INSTALL_DIR"

  if command -v curl > /dev/null 2>&1; then
    curl -fsSL "$DOWNLOAD_URL" | tar -xz -C "$INSTALL_DIR"
  elif command -v wget > /dev/null 2>&1; then
    wget -qO- "$DOWNLOAD_URL" | tar -xz -C "$INSTALL_DIR"
  else
    fail "curl or wget is required"
    exit 1
  fi

  ok "Installed to $INSTALL_DIR"
}

setup_env() {
  info "[3/5] Configuring environment..."

  if [ -f "$INSTALL_DIR/.env" ]; then
    printf "\n"
    warn "Existing .env found at $INSTALL_DIR/.env"
    printf "  Overwrite? [y/N] "
    read -r OVERWRITE < "$TTY"
    case "$OVERWRITE" in
      [yY]|[yY][eE][sS]) ;;
      *)
        ok "Keeping existing configuration"
        # Still read ADMIN_KEY for summary
        ADMIN_KEY=$(grep '^ADMIN_KEY=' "$INSTALL_DIR/.env" | cut -d= -f2)
        return
        ;;
    esac
  fi

  # Auto-generate cryptographic keys
  SECRET_KEY=$(node -e "process.stdout.write(require('crypto').randomBytes(32).toString('hex'))")
  SALT_KEY=$(node -e "process.stdout.write(require('crypto').randomBytes(32).toString('hex'))")
  ADMIN_KEY=$(node -e "process.stdout.write(require('crypto').randomBytes(16).toString('base64url'))")

  printf "\n"
  printf "  ┌──────────────────────────────────────────────────────────┐\n"
  printf "  │  ${BOLD}An Anthropic OAuth Token is required.${RESET}                    │\n"
  printf "  │                                                          │\n"
  printf "  │  How to get it:                                          │\n"
  printf "  │  ${CYAN}1.${RESET} Install Claude Code (if not installed):               │\n"
  printf "  │     ${BOLD}https://code.claude.com/docs${RESET}               │\n"
  printf "  │  ${CYAN}2.${RESET} Run in terminal:                                      │\n"
  printf "  │     ${BOLD}claude setup-token${RESET}                                     │\n"
  printf "  │  ${CYAN}3.${RESET} Login and authorize in the browser                    │\n"
  printf "  │  ${CYAN}4.${RESET} Copy the token (starts with ${YELLOW}sk-ant-oat01-${RESET})            │\n"
  printf "  └──────────────────────────────────────────────────────────┘\n"
  printf "\n"
  printf "  Enter ANTHROPIC_OAUTH_TOKEN: "
  read -r TOKEN < "$TTY"

  if [ -z "$TOKEN" ]; then
    fail "Token is required"
    exit 1
  fi

  cat > "$INSTALL_DIR/.env" <<EOF
PORT=3003
ANTHROPIC_OAUTH_TOKEN=$TOKEN
SECRET_KEY=$SECRET_KEY
SALT_KEY=$SALT_KEY
ADMIN_KEY=$ADMIN_KEY
DEFAULT_MODEL=claude-sonnet-4-6
EOF

  ok "Configuration saved"
}

create_launcher() {
  info "[4/5] Creating launcher..."

  # Create the launcher script with start/stop/restart/status
  cat > "$INSTALL_DIR/claude-proxy-ctl.sh" <<'LAUNCHER_SCRIPT'
#!/bin/sh
INSTALL_DIR="$HOME/.claude-proxy"
PIDFILE="$INSTALL_DIR/.pid"
LOGFILE="$INSTALL_DIR/server.log"

case "${1:-help}" in
  start)
    PORT=$(grep '^PORT=' "$INSTALL_DIR/.env" | cut -d= -f2)
    # Check if already running (by PID file or port)
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      echo "claude-proxy is already running (PID $(cat "$PIDFILE"))"
      echo "  Admin:  http://localhost:${PORT}/admin"
      echo "  API:    http://localhost:${PORT}/v1"
      exit 0
    fi
    # Prefer launchd on macOS, systemd on Linux
    PLIST="$HOME/Library/LaunchAgents/com.claude-proxy.server.plist"
    if [ "$(uname -s)" = "Darwin" ] && [ -f "$PLIST" ]; then
      launchctl load "$PLIST" 2>/dev/null
      sleep 1
      PID=$(lsof -ti :"$PORT" 2>/dev/null | head -1)
      echo "claude-proxy started via launchd${PID:+ (PID $PID)}"
    elif [ "$(uname -s)" = "Linux" ] && systemctl --user is-enabled claude-proxy >/dev/null 2>&1; then
      systemctl --user start claude-proxy
      sleep 1
      PID=$(lsof -ti :"$PORT" 2>/dev/null | head -1)
      echo "claude-proxy started via systemd${PID:+ (PID $PID)}"
    else
      cd "$INSTALL_DIR"
      nohup node server.mjs > "$LOGFILE" 2>&1 &
      echo $! > "$PIDFILE"
      PID=$!
      echo "claude-proxy started (PID $PID)"
    fi
    echo "  Admin:  http://localhost:${PORT}/admin"
    echo "  API:    http://localhost:${PORT}/v1"
    echo "  Logs:   $LOGFILE"
    ;;
  stop)
    STOPPED=false
    # On macOS, unload launchd service first (prevents auto-restart)
    PLIST="$HOME/Library/LaunchAgents/com.claude-proxy.server.plist"
    if [ "$(uname -s)" = "Darwin" ] && [ -f "$PLIST" ]; then
      launchctl unload "$PLIST" 2>/dev/null && STOPPED=true
    fi
    # On Linux, stop systemd service
    if [ "$(uname -s)" = "Linux" ]; then
      systemctl --user stop claude-proxy 2>/dev/null && STOPPED=true
    fi
    # Also kill by PID file (for manual nohup starts)
    if [ -f "$PIDFILE" ]; then
      PID=$(cat "$PIDFILE")
      if kill -0 "$PID" 2>/dev/null; then
        kill "$PID"
        STOPPED=true
      fi
      rm -f "$PIDFILE"
    fi
    if [ "$STOPPED" = true ]; then
      echo "claude-proxy stopped"
    else
      echo "claude-proxy is not running"
    fi
    ;;
  restart)
    "$0" stop
    sleep 1
    "$0" start
    ;;
  status)
    PORT=$(grep '^PORT=' "$INSTALL_DIR/.env" | cut -d= -f2)
    PID=""
    # Check PID file first
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      PID=$(cat "$PIDFILE")
    else
      # Fallback: check if something is listening on the port (launchd/systemd managed)
      PID=$(lsof -ti :"$PORT" 2>/dev/null | head -1)
    fi
    if [ -n "$PID" ]; then
      echo "claude-proxy is running (PID $PID)"
      echo "  Admin:  http://localhost:${PORT}/admin"
      echo "  API:    http://localhost:${PORT}/v1"
    else
      echo "claude-proxy is not running"
    fi
    ;;
  logs)
    if [ -f "$LOGFILE" ]; then
      tail -f "$LOGFILE"
    else
      echo "No log file found"
    fi
    ;;
  uninstall)
    "$0" stop 2>/dev/null || true
    echo "Removing auto-start..."
    OS=$(uname -s)
    case "$OS" in
      Darwin)
        PLIST="$HOME/Library/LaunchAgents/com.claude-proxy.server.plist"
        launchctl unload "$PLIST" 2>/dev/null || true
        rm -f "$PLIST"
        ;;
      Linux)
        systemctl --user stop claude-proxy 2>/dev/null || true
        systemctl --user disable claude-proxy 2>/dev/null || true
        rm -f "$HOME/.config/systemd/user/claude-proxy.service"
        systemctl --user daemon-reload 2>/dev/null || true
        ;;
    esac
    echo "Removing installation..."
    rm -rf "$INSTALL_DIR"
    LAUNCHER_LINK="/usr/local/bin/claude-proxy"
    [ -L "$LAUNCHER_LINK" ] && rm -f "$LAUNCHER_LINK"
    LAUNCHER_LINK="$HOME/bin/claude-proxy"
    [ -L "$LAUNCHER_LINK" ] && rm -f "$LAUNCHER_LINK"
    echo "claude-proxy uninstalled"
    ;;
  help|*)
    echo "Usage: claude-proxy {start|stop|restart|status|logs|uninstall}"
    echo ""
    echo "Commands:"
    echo "  start      Start the proxy server"
    echo "  stop       Stop the proxy server"
    echo "  restart    Restart the proxy server"
    echo "  status     Show server status"
    echo "  logs       Tail the server logs"
    echo "  uninstall  Remove claude-proxy completely"
    ;;
esac
LAUNCHER_SCRIPT
  chmod +x "$INSTALL_DIR/claude-proxy-ctl.sh"

  # Create symlink in PATH
  if [ -w "$BIN_DIR" ]; then
    ln -sf "$INSTALL_DIR/claude-proxy-ctl.sh" "$BIN_DIR/claude-proxy"
    ok "'claude-proxy' command installed to $BIN_DIR"
  else
    mkdir -p "$HOME/bin"
    ln -sf "$INSTALL_DIR/claude-proxy-ctl.sh" "$HOME/bin/claude-proxy"
    BIN_DIR="$HOME/bin"

    # Add to PATH if not already there
    case ":$PATH:" in
      *":$HOME/bin:"*) ;;
      *)
        SHELL_RC=""
        if [ -f "$HOME/.zshrc" ]; then
          SHELL_RC="$HOME/.zshrc"
        elif [ -f "$HOME/.bashrc" ]; then
          SHELL_RC="$HOME/.bashrc"
        elif [ -f "$HOME/.profile" ]; then
          SHELL_RC="$HOME/.profile"
        fi

        if [ -n "$SHELL_RC" ]; then
          echo 'export PATH="$HOME/bin:$PATH"' >> "$SHELL_RC"
          warn "Added \$HOME/bin to PATH in $SHELL_RC (restart shell or run: source $SHELL_RC)"
        fi
        export PATH="$HOME/bin:$PATH"
        ;;
    esac
    ok "'claude-proxy' command installed to $HOME/bin"
  fi
}

setup_autostart() {
  info "[5/5] Setting up auto-start on boot..."

  OS=$(uname -s)
  NODE_PATH=$(which node)

  case "$OS" in
    Darwin)
      PLIST="$HOME/Library/LaunchAgents/com.claude-proxy.server.plist"
      mkdir -p "$HOME/Library/LaunchAgents"
      cat > "$PLIST" <<PLIST_CONTENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.claude-proxy.server</string>
  <key>ProgramArguments</key>
  <array>
    <string>${NODE_PATH}</string>
    <string>${INSTALL_DIR}/server.mjs</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${INSTALL_DIR}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${INSTALL_DIR}/server.log</string>
  <key>StandardErrorPath</key>
  <string>${INSTALL_DIR}/server.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/usr/local/bin:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
PLIST_CONTENT
      launchctl unload "$PLIST" 2>/dev/null || true
      launchctl load "$PLIST"
      ok "Auto-start configured (macOS launchd)"
      ok "Server is now running!"
      ;;
    Linux)
      SYSTEMD_DIR="$HOME/.config/systemd/user"
      mkdir -p "$SYSTEMD_DIR"
      cat > "$SYSTEMD_DIR/claude-proxy.service" <<SERVICE_CONTENT
[Unit]
Description=Claude Proxy Server - OpenAI-compatible API for Claude
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${NODE_PATH} ${INSTALL_DIR}/server.mjs
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=default.target
SERVICE_CONTENT
      systemctl --user daemon-reload
      systemctl --user enable claude-proxy
      systemctl --user start claude-proxy
      ok "Auto-start configured (systemd user service)"
      ok "Server is now running!"
      ;;
    *)
      warn "Auto-start not supported on $OS"
      warn "Start manually: claude-proxy start"
      ;;
  esac
}

print_summary() {
  PORT=$(grep '^PORT=' "$INSTALL_DIR/.env" | cut -d= -f2)

  printf "\n"
  printf "  ${BOLD}══════════════════════════════════════════════════${RESET}\n"
  printf "  ${GREEN}${BOLD}  Setup completed successfully!${RESET}\n"
  printf "  ${BOLD}══════════════════════════════════════════════════${RESET}\n"
  printf "\n"
  printf "  ${BOLD}ADMIN KEY${RESET} (save this — shown only once!):\n"
  printf "  ${YELLOW}${BOLD}→ ${ADMIN_KEY}${RESET}\n"
  printf "\n"
  printf "  ${BOLD}Commands:${RESET}\n"
  printf "    claude-proxy start      Start the server\n"
  printf "    claude-proxy stop       Stop the server\n"
  printf "    claude-proxy restart    Restart the server\n"
  printf "    claude-proxy status     Check server status\n"
  printf "    claude-proxy logs       Tail server logs\n"
  printf "    claude-proxy uninstall  Remove completely\n"
  printf "\n"
  printf "  ${BOLD}The server auto-starts on boot.${RESET}\n"
  printf "\n"
  printf "  ${BOLD}Next steps:${RESET}\n"
  printf "  ${CYAN}1.${RESET} Open admin panel: ${BOLD}http://localhost:${PORT}/admin${RESET}\n"
  printf "  ${CYAN}2.${RESET} Login with the ADMIN KEY above\n"
  printf "  ${CYAN}3.${RESET} Create an API key\n"
  printf "  ${CYAN}4.${RESET} Configure your client:\n"
  printf "     Base URL: ${BOLD}http://localhost:${PORT}/v1${RESET}\n"
  printf "     API Key:  ${BOLD}<key from admin panel>${RESET}\n"
  printf "\n"
  printf "  ${BOLD}══════════════════════════════════════════════════${RESET}\n"
  printf "\n"
}

main
