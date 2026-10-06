@echo off
rem CS2 Windows 精简服务端 启动脚本 (de_dust2, -insecure)
rem 网络参数针对 VPN/TUN 链路优化, 避免 NETWORK_DISCONNECT_OVERFLOW
rem 端口: 优先使用面板环境变量 SERVER_PORT（简幻欢等），否则默认 27015
cd /d "%~dp0"
set "PORT=27015"
if defined SERVER_PORT set "PORT=%SERVER_PORT%"
game\bin\win64\cs2.exe -dedicated +map de_dust2 +hostname "SlimTest" -maxplayers 12 -ip 0.0.0.0 -port %PORT% -insecure -condebug +game_type 0 +game_mode 0 +sv_pure 0 +sv_cheats 1 +sv_lan 1 +sv_maxrate 0 +sv_minrate 100000 +sv_maxupdaterate 128 +sv_maxcmdrate 128 +net_maxroutable 1200
