@echo off
rem CS2 Windows slim server launcher (de_dust2, -insecure)
rem Network params tuned for VPN/TUN links to avoid NETWORK_DISCONNECT_OVERFLOW.
rem Port precedence: SERVER_PORT (panel env) > CS2_PORT (user) > 27015 default.
rem
rem Optional plugin manager web (link-manager feature):
rem   Enable with CS2LM_WEB=1. Requires cs2lm.bat in this directory.
rem   - CS2LM_WEB_TOKEN: fixed token (default: random -> web_token.txt)
rem   - Same port as CS2 (UDP game + TCP web coexist)
rem   - PID in web.pid, logs in web.log / web.err.log
rem   - Old web process is cleaned up on restart
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "PORT=27015"
if defined CS2_PORT set "PORT=%CS2_PORT%"
if defined SERVER_PORT set "PORT=%SERVER_PORT%"

rem ---------- Optional: plugin manager web (link-manager, CS2LM_WEB=1) ----------
if "%CS2LM_WEB%"=="1" (
  if exist "%~dp0cs2lm.bat" (
    echo [cs2slim] link-manager detected, starting plugin manager web on TCP !PORT!
    rem clean up old web process on restart
    if exist "%~dp0web.pid" (
      set /p OLD_PID=<"%~dp0web.pid"
      if defined OLD_PID (
        taskkill /PID !OLD_PID! /T /F >nul 2>&1
        echo [cs2slim] stopped old plugin manager web, pid !OLD_PID!
      )
    )
    rem auto init plugin repo, idempotent
    if not exist "%~dp0plugins-repo\config.json" (
      echo [cs2slim] initializing plugin repo: %CD%\plugins-repo
      call "%~dp0cs2lm.bat" --repo "%~dp0plugins-repo" init --server "%CD%" >nul 2>&1
    )
    rem token from env var, or random into web_token.txt
    if defined CS2LM_WEB_TOKEN (
      set "TOKEN=%CS2LM_WEB_TOKEN%"
    ) else (
      for /f %%i in ('powershell -NoProfile -Command "([guid]::NewGuid().ToString('N')).Substring(0,16)"') do set "TOKEN=%%i"
      echo !TOKEN!> "%~dp0web_token.txt"
    )
    rem start web in background and save its PID
    powershell -NoProfile -Command "$p = Start-Process -FilePath '%~dp0cs2lm.bat' -ArgumentList @('--repo','%~dp0plugins-repo','web','--host','0.0.0.0','--port','!PORT!','--auth-token','!TOKEN!') -WorkingDirectory '%CD%' -RedirectStandardOutput '%~dp0web.log' -RedirectStandardError '%~dp0web.err.log' -WindowStyle Hidden -PassThru; Write-Output $p.Id" > "%~dp0web.pid"
    echo [cs2slim] plugin manager web: http://<IP>:!PORT!/?token=!TOKEN!
    rem detect startup failure
    ping -n 2 127.0.0.1 >nul
    set "WPID="
    set /p WPID=<"%~dp0web.pid"
    if not defined WPID set "WPID=0"
    tasklist /FI "PID eq !WPID!" 2>nul | findstr /C:"!WPID!" >nul
    if errorlevel 1 (
      echo [cs2slim] WARNING: plugin manager web failed to start, see web.log
    )
  )
)

rem ---------- Start CS2 server ----------
game\bin\win64\cs2.exe -dedicated +map de_dust2 +hostname "SlimTest" -maxplayers 12 -ip 0.0.0.0 -port %PORT% -insecure -condebug +game_type 0 +game_mode 0 +sv_pure 0 +sv_cheats 1 +sv_lan 1 +sv_maxrate 0 +sv_minrate 100000 +sv_maxupdaterate 128 +sv_maxcmdrate 128 +net_maxroutable 1200
