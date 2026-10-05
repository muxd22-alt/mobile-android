@echo off
set "PATH=%PATH%;D:\ARBOR\bin;C:\Users\medo\AppData\Roaming\npm;C:\Users\medo\.openclaw\workspace\skills"
title OpenClaw AI Starter
color 0A
echo ============================================================
echo    OpenClaw + Arbor Agentic Stack
echo    Model: qwen3.5-9b-claude-4.6-opus-reasoning-distilled
echo    LM Studio: http://100.67.202.80:3003/v1
echo    Arbor UI: D:\ARBOR\bin\Arbor.exe
echo    Telegram Bot: @firstboteverybot
echo.
echo    [NOTE] If Tailscale connection fails, run this as Admin:
echo    netsh advfirewall firewall add rule name="AI Stack" dir=in action=allow protocol=TCP localport=18789,8787
echo ============================================================
echo.

:: Ensure execution policy allows openclaw scripts
powershell -Command "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force" 2>nul

:: Check if Node.js is available
where node >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Node.js not found. Please install Node.js 22+ first.
    echo         Download: https://nodejs.org/
    pause
    exit /b 1
)

:: Check if openclaw is installed
where openclaw >nul 2>&1
if %errorlevel% neq 0 (
    echo [WARNING] openclaw not in PATH. Attempting npm global...
    call npm list -g openclaw >nul 2>&1
    if %errorlevel% neq 0 (
        echo [ERROR] openclaw not installed. Run:
        echo         powershell -c "irm https://openclaw.ai/install.ps1 | iex"
        pause
        exit /b 1
    )
)

echo.
echo [1/4] Running diagnostics...
call openclaw doctor
echo.

echo [3/5] Launching Arbor Agentic Dashboard...
echo      Tailscale: http://100.67.202.80:8787
powershell -ExecutionPolicy Bypass -File "D:\ARBOR\bin\generate_config.ps1"
set "OPENAI_API_BASE=http://100.67.202.80:3003/v1"
set "OPENAI_BASE_URL=http://100.67.202.80:3003/v1"
set "OPENAI_API_KEY=sk-lm-Lx9jGf04:PFt54YB1r3KclB2rq6N4"
set "ARBOR_DAEMON_AUTH_TOKEN=arbor-tailscale-access"

set "ARBOR_HTTPD_BIND=0.0.0.0:8787"
tasklist /NH /FI "IMAGENAME eq arbor-httpd.exe" | find /I "arbor-httpd.exe" >nul
if errorlevel 1 (
    echo      Starting Arbor Daemon - Tailscale enabled...
    start /b "" "D:\ARBOR\bin\arbor-httpd.exe"
) else (
    echo      Arbor Daemon is already running.
)

tasklist /NH /FI "IMAGENAME eq Arbor.exe" | find /I "Arbor.exe" >nul
if errorlevel 1 (
    echo      Opening Arbor UI...
    start "" "D:\ARBOR\bin\Arbor.exe"
) else (
    echo      Arbor UI is already open.
)
echo.

echo [4/5] Starting OpenClaw Gateway (Tailscale Mode)...
echo      Tailscale Dashboard: https://desktop-9abbqhj.talpidae-salary.ts.net/
echo      Press Ctrl+C to exit launcher loop.
echo.

:: Clear existing gateway if running
call openclaw gateway stop >nul 2>&1
taskkill /F /IM node.exe /FI "WINDOWTITLE eq OpenClaw*" >nul 2>&1

:gateway_loop
echo [%time%] Starting Gateway on Tailnet...
:: Ensure environment is clean for this run
call openclaw gateway run --port 18789 --verbose
echo.
echo [!] Gateway exited or crashed. Restarting in 5 seconds...
echo     (Press Ctrl+C now to stop)
timeout /t 5 >nul
goto gateway_loop
