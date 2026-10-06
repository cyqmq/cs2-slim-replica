@echo off
rem CS2 Windows 精简服务端 启动脚本 (de_dust2, -insecure)
rem 网络参数针对 VPN/TUN 链路优化, 避免 NETWORK_DISCONNECT_OVERFLOW
cd /d "%~dp0"
game\bin\win64\cs2.exe -dedicated +map de_dust2 +hostname "SlimTest" -maxplayers 12 -ip 0.0.0.0 -port 27015 -insecure -condebug +game_type 0 +game_mode 0 +sv_pure 0 +sv_cheats 1 +sv_lan 1 +sv_maxrate 0 +sv_minrate 100000 +sv_maxupdaterate 128 +sv_maxcmdrate 128 +net_maxroutable 1200
