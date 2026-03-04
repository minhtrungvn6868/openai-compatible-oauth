# ─────────────────────────────────────────────────────
# Claude Proxy Server — Windows Installer (PowerShell)
# Usage: irm https://<url>/install.ps1 | iex
# ─────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"

$Repo = "minhtrungvn6868/openai-compatible-oauth"
$InstallDir = "$env:USERPROFILE\.claude-proxy"
$Version = if ($env:CLAUDE_PROXY_VERSION) { $env:CLAUDE_PROXY_VERSION } else { "latest" }

function Write-Info { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor Cyan }
function Write-Ok { param([string]$Msg) Write-Host "  ✓ $Msg" -ForegroundColor Green }
function Write-Fail { param([string]$Msg) Write-Host "  ✗ $Msg" -ForegroundColor Red }
function Write-Warn { param([string]$Msg) Write-Host "  ! $Msg" -ForegroundColor Yellow }

function Print-Banner {
    Write-Host ""
    Write-Host "  Claude Proxy Server" -ForegroundColor White -NoNewline
    Write-Host " — Installer"
    Write-Host "  OpenAI-compatible API for Claude"
    Write-Host ""
}

function Check-Node {
    Write-Info "[1/5] Checking prerequisites..."

    try {
        $nodeVersion = (node -v) 2>$null
    }
    catch {
        Write-Fail "Node.js >= 18 is required"
        Write-Host ""
        Write-Host "  Install Node.js from: https://nodejs.org"
        exit 1
    }

    if (-not $nodeVersion) {
        Write-Fail "Node.js >= 18 is required"
        Write-Host "  Install from: https://nodejs.org"
        exit 1
    }

    $major = [int]($nodeVersion -replace 'v(\d+)\..*', '$1')
    if ($major -lt 18) {
        Write-Fail "Node.js >= 18 required (found $nodeVersion)"
        exit 1
    }

    Write-Ok "Node.js $nodeVersion"
}

function Download-Release {
    Write-Info "[2/5] Downloading..."

    if ($Version -eq "latest") {
        $url = "https://github.com/$Repo/releases/latest/download/claude-proxy.tar.gz"
    }
    else {
        $url = "https://github.com/$Repo/releases/download/$Version/claude-proxy.tar.gz"
    }

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    $archivePath = Join-Path $env:TEMP "claude-proxy.tar.gz"
    Invoke-WebRequest -Uri $url -OutFile $archivePath -UseBasicParsing

    tar -xzf $archivePath -C $InstallDir
    Remove-Item $archivePath -Force

    Write-Ok "Installed to $InstallDir"
}

function Setup-Env {
    Write-Info "[3/5] Configuring environment..."

    $envFile = Join-Path $InstallDir ".env"
    if (Test-Path $envFile) {
        Write-Warn "Existing .env found at $envFile"
        $overwrite = Read-Host "  Overwrite? [y/N]"
        if ($overwrite -notmatch "^[yY]") {
            Write-Ok "Keeping existing configuration"
            $script:AdminKey = ((Get-Content $envFile) -match "^ADMIN_KEY=") -replace "^ADMIN_KEY=", ""
            return
        }
    }

    # Auto-generate cryptographic keys
    $script:SecretKey = (node -e "process.stdout.write(require('crypto').randomBytes(32).toString('hex'))")
    $script:SaltKey = (node -e "process.stdout.write(require('crypto').randomBytes(32).toString('hex'))")
    $script:AdminKey = (node -e "process.stdout.write(require('crypto').randomBytes(16).toString('base64url'))")

    Write-Host ""
    Write-Host "  ┌──────────────────────────────────────────────────────────┐"
    Write-Host "  │  " -NoNewline
    Write-Host "An Anthropic OAuth Token is required." -ForegroundColor White -NoNewline
    Write-Host "                    │"
    Write-Host "  │                                                          │"
    Write-Host "  │  How to get it:                                          │"
    Write-Host "  │  1. Install Claude Code (if not installed):              │"
    Write-Host "  │     " -NoNewline
    Write-Host "npm install -g @anthropic-ai/claude-code" -ForegroundColor White -NoNewline
    Write-Host "               │"
    Write-Host "  │  2. Run in terminal:                                     │"
    Write-Host "  │     " -NoNewline
    Write-Host "claude setup-token" -ForegroundColor White -NoNewline
    Write-Host "                                     │"
    Write-Host "  │  3. Login and authorize in the browser                   │"
    Write-Host "  │  4. Copy the token (starts with " -NoNewline
    Write-Host "sk-ant-oat01-" -ForegroundColor Yellow -NoNewline
    Write-Host ")            │"
    Write-Host "  └──────────────────────────────────────────────────────────┘"
    Write-Host ""

    $token = Read-Host "  Enter ANTHROPIC_OAUTH_TOKEN"

    if ([string]::IsNullOrWhiteSpace($token)) {
        Write-Fail "Token is required"
        exit 1
    }

    $envContent = @"
PORT=3003
ANTHROPIC_OAUTH_TOKEN=$token
SECRET_KEY=$($script:SecretKey)
SALT_KEY=$($script:SaltKey)
ADMIN_KEY=$($script:AdminKey)
DEFAULT_MODEL=claude-sonnet-4-6
"@

    Set-Content -Path $envFile -Value $envContent -Encoding UTF8
    Write-Ok "Configuration saved"
}

function Create-Launcher {
    Write-Info "[4/5] Creating launcher..."

    # Create a batch file wrapper
    $batchContent = @"
@echo off
setlocal

set "INSTALL_DIR=%USERPROFILE%\.claude-proxy"
set "PIDFILE=%INSTALL_DIR%\.pid"
set "LOGFILE=%INSTALL_DIR%\server.log"

if "%~1"=="" goto help
if "%~1"=="start" goto start
if "%~1"=="stop" goto stop
if "%~1"=="restart" goto restart
if "%~1"=="status" goto status
if "%~1"=="logs" goto logs
if "%~1"=="uninstall" goto uninstall
goto help

:start
if exist "%PIDFILE%" (
    for /f %%i in (%PIDFILE%) do (
        tasklist /fi "PID eq %%i" 2>nul | find "%%i" >nul 2>&1
        if not errorlevel 1 (
            echo claude-proxy is already running ^(PID %%i^)
            goto :eof
        )
    )
)
cd /d "%INSTALL_DIR%"
start /b "claude-proxy" cmd /c "node server.mjs >> "%LOGFILE%" 2>&1"
timeout /t 1 /nobreak >nul
for /f "tokens=2" %%a in ('tasklist /v /fi "WINDOWTITLE eq claude-proxy" /fo list ^| find "PID:"') do (
    echo %%a> "%PIDFILE%"
    echo claude-proxy started ^(PID %%a^)
)
for /f "tokens=2 delims==" %%p in ('findstr /b "PORT=" "%INSTALL_DIR%\.env"') do (
    echo   Admin:  http://localhost:%%p/admin
    echo   API:    http://localhost:%%p/v1
)
echo   Logs:   %LOGFILE%
goto :eof

:stop
if exist "%PIDFILE%" (
    for /f %%i in (%PIDFILE%) do (
        taskkill /pid %%i /f >nul 2>&1
    )
    del "%PIDFILE%"
    echo claude-proxy stopped
) else (
    echo claude-proxy is not running
)
goto :eof

:restart
call :stop
timeout /t 1 /nobreak >nul
call :start
goto :eof

:status
if exist "%PIDFILE%" (
    for /f %%i in (%PIDFILE%) do (
        tasklist /fi "PID eq %%i" 2>nul | find "%%i" >nul 2>&1
        if not errorlevel 1 (
            echo claude-proxy is running ^(PID %%i^)
        ) else (
            echo claude-proxy is not running ^(stale PID file^)
            del "%PIDFILE%"
        )
    )
) else (
    echo claude-proxy is not running
)
goto :eof

:logs
if exist "%LOGFILE%" (
    type "%LOGFILE%"
) else (
    echo No log file found
)
goto :eof

:uninstall
call :stop
echo Removing auto-start...
schtasks /delete /tn "ClaudeProxy" /f >nul 2>&1
echo Removing installation...
cd /d "%USERPROFILE%"
rmdir /s /q "%INSTALL_DIR%" 2>nul
del "%USERPROFILE%\bin\claude-proxy.cmd" 2>nul
echo claude-proxy uninstalled
goto :eof

:help
echo Usage: claude-proxy {start^|stop^|restart^|status^|logs^|uninstall}
echo.
echo Commands:
echo   start      Start the proxy server
echo   stop       Stop the proxy server
echo   restart    Restart the proxy server
echo   status     Show server status
echo   logs       Show server logs
echo   uninstall  Remove claude-proxy completely
goto :eof
"@

    $binDir = Join-Path $env:USERPROFILE "bin"
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null

    $batchPath = Join-Path $binDir "claude-proxy.cmd"
    Set-Content -Path $batchPath -Value $batchContent -Encoding ASCII

    # Add to PATH if not already there
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -notlike "*$binDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$binDir;$currentPath", "User")
        $env:Path = "$binDir;$env:Path"
        Write-Warn "Added $binDir to user PATH (restart terminal to use 'claude-proxy' command)"
    }

    Write-Ok "'claude-proxy' command installed to $binDir"
}

function Setup-Autostart {
    Write-Info "[5/5] Setting up auto-start on boot..."

    $nodePath = (Get-Command node).Source
    $serverPath = Join-Path $InstallDir "server.mjs"

    # Use Windows Task Scheduler
    $taskName = "ClaudeProxy"

    # Remove existing task if any
    schtasks /delete /tn $taskName /f 2>$null

    $action = "cmd /c `"cd /d `"$InstallDir`" && `"$nodePath`" `"$serverPath`" >> `"$InstallDir\server.log`" 2>&1`""

    schtasks /create /tn $taskName `
        /tr $action `
        /sc onlogon `
        /rl limited `
        /f | Out-Null

    # Start the server now
    Start-Process -NoNewWindow -FilePath "cmd" -ArgumentList "/c cd /d `"$InstallDir`" && node server.mjs >> `"$InstallDir\server.log`" 2>&1" -WindowStyle Hidden

    Write-Ok "Auto-start configured (Windows Task Scheduler)"
    Write-Ok "Server is now running!"
}

function Print-Summary {
    $port = ((Get-Content (Join-Path $InstallDir ".env")) -match "^PORT=") -replace "^PORT=", ""

    Write-Host ""
    Write-Host "  ══════════════════════════════════════════════════" -ForegroundColor White
    Write-Host "    Setup completed successfully!" -ForegroundColor Green
    Write-Host "  ══════════════════════════════════════════════════" -ForegroundColor White
    Write-Host ""
    Write-Host "  ADMIN KEY" -ForegroundColor White -NoNewline
    Write-Host " (save this — shown only once!):"
    Write-Host "  → $($script:AdminKey)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Commands:" -ForegroundColor White
    Write-Host "    claude-proxy start      Start the server"
    Write-Host "    claude-proxy stop       Stop the server"
    Write-Host "    claude-proxy restart    Restart the server"
    Write-Host "    claude-proxy status     Check server status"
    Write-Host "    claude-proxy logs       Show server logs"
    Write-Host "    claude-proxy uninstall  Remove completely"
    Write-Host ""
    Write-Host "  The server auto-starts on login." -ForegroundColor White
    Write-Host ""
    Write-Host "  Next steps:" -ForegroundColor White
    Write-Host "  1. Open admin panel: " -NoNewline
    Write-Host "http://localhost:${port}/admin" -ForegroundColor White
    Write-Host "  2. Login with the ADMIN KEY above"
    Write-Host "  3. Create an API key"
    Write-Host "  4. Configure your client:"
    Write-Host "     Base URL: " -NoNewline
    Write-Host "http://localhost:${port}/v1" -ForegroundColor White
    Write-Host "     API Key:  <key from admin panel>"
    Write-Host ""
    Write-Host "  ══════════════════════════════════════════════════" -ForegroundColor White
    Write-Host ""
}

# Run
Print-Banner
Check-Node
Download-Release
Setup-Env
Create-Launcher
Setup-Autostart
Print-Summary
