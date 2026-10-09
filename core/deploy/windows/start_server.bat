@echo off
rem CS2 Windows slim server launcher (de_dust2, -insecure)
rem Network params tuned for VPN/TUN links to avoid NETWORK_DISCONNECT_OVERFLOW.
rem Port precedence: SERVER_PORT (panel env) > CS2_PORT (user) > 27015 default.
rem
rem Network mode CS2_NET_MODE: 1(lan) | 2(lan+bind 0.0.0.0, default) | 3(public, requires GSLT)
rem   GSLT precedence CS2_GSLT > GSLT > CS2LM_GSLT; mode 3 falls back to 2 without GSLT.
rem   WARNING: this slim build is unauthenticated / may violate ToS; binding a GSLT
rem   publicly can get that Steam account's GSLT service banned.
rem
rem Optional plugin manager web (link-manager feature):
rem   Enable with CS2LM_WEB=1. Requires cs2lm.bat in this directory.
rem   - CS2LM_WEB_TOKEN: fixed token (default: random)
rem   - Token is ALWAYS saved in web_token.txt
rem   - Same port as CS2 (UDP game + TCP web coexist)
rem   - PID in web.pid, logs in web.log / web.err.log
rem
rem Segmented interactive menu (shown once at first interactive start, then hidden):
rem   start_server.bat            menu on first run, then full start (default 1 after 15s)
rem   start_server.bat menu        force menu (use this to reopen later)
rem   start_server.bat auto        skip menu, full start
rem   start_server.bat web         start plugin manager web only (print token)
rem   start_server.bat token       show current token
rem   start_server.bat webstop      stop plugin manager web
rem Note: after first menu, .cs2slim_menu_seen marker suppresses it; reopen with menu arg.
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "PORT=27015"
if defined CS2_PORT set "PORT=%CS2_PORT%"
if defined SERVER_PORT set "PORT=%SERVER_PORT%"
set "MENU_SEEN=%~dp0.cs2slim_menu_seen"

rem ---------- segmented subcommands ----------
if /i "%~1"=="web" (
  call :web
  exit /b !errorlevel!
)
if /i "%~1"=="token" (
  call :token
  exit /b !errorlevel!
)
if /i "%~1"=="webstop" (
  call :webstop
  exit /b !errorlevel!
)

rem ---------- menu mode detection ----------
set "MENU=0"
if /i "%~1"=="menu" set "MENU=1"
if "%~1"=="" if not defined CS2LM_AUTO if not exist "%MENU_SEEN%" set "MENU=1"
if /i "%~1"=="auto" set "MENU=0"
if /i "%~1"=="start" set "MENU=0"
if defined CS2LM_MENU set "MENU=1"
if "%CS2LM_MENU%"=="0" set "MENU=0"

if "%MENU%"=="1" (
  echo.
  echo ==================================================
  echo  CS2 slim server - startup options
  echo ==================================================
  echo  [1] Full start - plugin web + CS2 server
  echo  [2] Start plugin manager web only - print token
  echo  [3] Start CS2 server only
  echo  [4] Show current token
  echo  [5] Stop plugin manager web
  echo  [6] Exit
  echo ==================================================
  choice /c 123456 /t 15 /d 1 /m "Enter a number (default 1): "
  set "CHOICE=!errorlevel!"
  type nul > "%MENU_SEEN%"
) else (
  set "CHOICE=1"
)

if "%CHOICE%"=="2" (
  call :web
  exit /b !errorlevel!
)
if "%CHOICE%"=="4" (
  call :token
  exit /b !errorlevel!
)
if "%CHOICE%"=="5" (
  call :webstop
  exit /b !errorlevel!
)
if "%CHOICE%"=="6" (
  echo [cs2slim] exited
  exit /b 0
)

rem choice 1: start web if CS2LM_WEB=1; choice 3: skip web
if "%CHOICE%"=="1" (
  if "%CS2LM_WEB%"=="1" (
    call :web
  )
)

rem ---------- network mode ----------
rem CS2_NET_MODE: 1(lan) | 2(lan+bind 0.0.0.0, default) | 3(public, requires GSLT)
rem  1 = LAN only            +sv_lan 1 (no -ip)
rem  2 = LAN + bind all NICs  +sv_lan 1 -ip 0.0.0.0 (default, current behavior)
rem  3 = public              +sv_lan 0 + GSLT (+sv_setsteamaccount)
rem       WARNING: this slim build is unauthenticated / may violate ToS; binding a
rem       GSLT publicly can get that Steam account's GSLT service banned.
rem       Without a GSLT, falls back to mode 2.
rem GSLT source precedence: CS2_GSLT > GSLT > CS2LM_GSLT
set "NET_MODE=%CS2_NET_MODE%"
if not defined NET_MODE set "NET_MODE=2"
set "SV_LAN=1"
set "BIND_IP="
set "NET_ARGS="
if "%NET_MODE%"=="1" set "BIND_IP="
if "%NET_MODE%"=="3" (
  set "SV_LAN=0"
  set "NET_ARGS="
  if defined CS2_GSLT set "NET_ARGS=+sv_setsteamaccount %CS2_GSLT%"
  if not defined NET_ARGS if defined GSLT set "NET_ARGS=+sv_setsteamaccount %GSLT%"
  if not defined NET_ARGS if defined CS2LM_GSLT set "NET_ARGS=+sv_setsteamaccount %CS2LM_GSLT%"
  if not defined NET_ARGS (
    echo [cs2slim] WARN: CS2_NET_MODE=3 but no GSLT (CS2_GSLT/GSLT/CS2LM_GSLT), falling back to mode 2
    set "SV_LAN=1"
    set "BIND_IP=-ip 0.0.0.0"
  )
)
if "%NET_MODE%"=="2" set "BIND_IP=-ip 0.0.0.0"
if "%NET_MODE%" neq "1" if "%NET_MODE%" neq "2" if "%NET_MODE%" neq "3" (
  echo [cs2slim] WARN: unknown CS2_NET_MODE=%NET_MODE%, falling back to mode 2
  set "NET_MODE=2"
  set "BIND_IP=-ip 0.0.0.0"
)

rem ---------- Start CS2 server ----------
if "%MENU%"=="1" (
  echo [cs2slim] starting CS2 server, console will show server logs - menu hidden
  echo [cs2slim] to reopen menu, run: start_server.bat menu
)
game\bin\win64\cs2.exe -dedicated +map de_dust2 +hostname "SlimTest" -maxplayers 12 %BIND_IP% -port %PORT% -insecure -condebug +game_type 0 +game_mode 0 +sv_pure 0 +sv_cheats 1 +sv_lan %SV_LAN% %NET_ARGS% +sv_maxrate 0 +sv_minrate 100000 +sv_maxupdaterate 128 +sv_maxcmdrate 128 +net_maxroutable 1200
exit /b %errorlevel%

rem ================= subroutines =================

:web
if not exist "%~dp0cs2lm.bat" (
  echo [cs2slim] ERROR: cs2lm.bat not found, please install link-manager feature
  exit /b 1
)
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
rem token from env var or random; ALWAYS write web_token.txt
if defined CS2LM_WEB_TOKEN (
  set "TOKEN=%CS2LM_WEB_TOKEN%"
) else (
  for /f %%i in ('powershell -NoProfile -Command "([guid]::NewGuid().ToString('N')).Substring(0,16)"') do set "TOKEN=%%i"
)
echo !TOKEN!> "%~dp0web_token.txt"
rem optional manual-exec cfg: type "exec cs2slim_token.cfg" in CS2 console later
if not exist "%~dp0game\csgo\cfg" mkdir "%~dp0game\csgo\cfg"
> "%~dp0game\csgo\cfg\cs2slim_token.cfg" echo echo ================================================
>> "%~dp0game\csgo\cfg\cs2slim_token.cfg" echo echo [cs2slim] Plugin manager web: http://SERVER_IP:!PORT!/?token=!TOKEN!
>> "%~dp0game\csgo\cfg\cs2slim_token.cfg" echo echo [cs2slim] Token also saved in: web_token.txt
>> "%~dp0game\csgo\cfg\cs2slim_token.cfg" echo echo ================================================
rem start web in background and save its PID
powershell -NoProfile -Command "$p = Start-Process -FilePath '%~dp0cs2lm.bat' -ArgumentList @('--repo','%~dp0plugins-repo','web','--host','0.0.0.0','--port','!PORT!','--auth-token','!TOKEN!') -WorkingDirectory '%CD%' -RedirectStandardOutput '%~dp0web.log' -RedirectStandardError '%~dp0web.err.log' -WindowStyle Hidden -PassThru; Write-Output $p.Id" > "%~dp0web.pid"
echo [cs2slim] plugin manager web: http://^<IP^>:!PORT!/?token=!TOKEN!
rem detect startup failure
ping -n 2 127.0.0.1 >nul
set "WPID="
set /p WPID=<"%~dp0web.pid"
if not defined WPID set "WPID=0"
tasklist /FI "PID eq !WPID!" 2>nul | findstr /C:"!WPID!" >nul
if errorlevel 1 (
  echo [cs2slim] WARNING: plugin manager web failed to start, see web.log
)
exit /b 0

:token
if not exist "%~dp0web_token.txt" (
  echo [cs2slim] no token yet, start web first
  exit /b 1
)
set /p TOKEN=<"%~dp0web_token.txt"
echo [cs2slim] plugin manager web: http://^<IP^>:!PORT!/?token=!TOKEN!
echo [cs2slim] token file: %~dp0web_token.txt
exit /b 0

:webstop
if not exist "%~dp0web.pid" (
  echo [cs2slim] plugin manager web is not running
  exit /b 0
)
set /p OLD_PID=<"%~dp0web.pid"
if defined OLD_PID (
  taskkill /PID !OLD_PID! /T /F >nul 2>&1
  echo [cs2slim] stopped plugin manager web, pid !OLD_PID!
)
del /q "%~dp0web.pid" >nul 2>&1
exit /b 0