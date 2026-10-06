#!/bin/bash
# CS2 精简专用服务端 启动脚本 (de_dust2, -insecure)
# 启动前自动完成:
#   1) 放置 steamclient.so 到 $HOME/.steam/sdk64/ (容器 HOME 可能是 /home/container 而非 /root)
#   2) V8 库符号链接 (game/csgo/bin/linuxsteamrt64 -> game/bin/linuxsteamrt64)
cd "$(dirname "$0")"

# 1) steamclient.so 就位
if [ -f steamclient.so ]; then
  mkdir -p "$HOME/.steam/sdk64"
  ln -sf "$(readlink -f steamclient.so)" "$HOME/.steam/sdk64/steamclient.so"
  echo "[setup] steamclient.so -> $HOME/.steam/sdk64/steamclient.so"
else
  echo "[setup] WARN: 当前目录没有 steamclient.so，服务端可能无法初始化 Steamworks" >&2
fi

# 2) V8 库符号链接
cd game/csgo/bin/linuxsteamrt64
for f in libv8.so libv8system.so libv8_icui18n.so libv8_icuuc.so \
         libv8_libbase.so libv8_libcpp.so libv8_libplatform.so libv8_zlib.so; do
  if [ -f "../../../bin/linuxsteamrt64/$f" ]; then
    ln -sf "../../../bin/linuxsteamrt64/$f" "$f"
  fi
done
cd - >/dev/null

exec ./game/bin/linuxsteamrt64/cs2 \
  -dedicated +map de_dust2 +hostname "SlimTest" \
  -maxplayers 12 -ip 0.0.0.0 -port 27015 \
  -insecure -condebug +game_type 0 +game_mode 0 \
  +sv_pure 0 +sv_cheats 1