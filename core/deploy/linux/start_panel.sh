#!/bin/bash
# CS2 精简服务端 面板启动脚本（简幻欢 / Pterodactyl 等面板通用）
#
# 用法:
#   1) 把本文件放到面板服务器根目录（如 /home/container/start.sh）
#   2) 面板启动命令设为:  bash start.sh
#
# 说明:
#   - 精简树默认在 $HOME/cs2-slim-build/slim，可用环境变量 CS2_SLIM_DIR 覆盖
#   - 启动前自动:
#       a) 把 steamclient.so 链接到 $HOME/.steam/sdk64/steamclient.so
#          （优先当前精简树，其次 game/bin/linuxsteamrt64，最后全盘搜索 linux64）
#       b) 创建 V8 库符号链接 (game/csgo/bin/linuxsteamrt64 -> game/bin/linuxsteamrt64)
#   - 启动参数含 -insecure + sv_pure 0（精简服务端必须）

SLIM_DIR="${CS2_SLIM_DIR:-$HOME/cs2-slim-build/slim}"

cd "$SLIM_DIR" || { echo "无法进入 $SLIM_DIR，请先运行一键脚本或检查 CS2_SLIM_DIR" >&2; exit 1; }

# Steam 家目录：优先 $HOME（root=/root, 容器=/home/container, 任意用户=/home/用户名），
# $HOME 为空时从 passwd 数据库取当前用户家目录
STEAM_HOME="${HOME:-}"
if [ -z "$STEAM_HOME" ]; then
  STEAM_HOME="$(getent passwd "$(id -u)" | cut -d: -f6 2>/dev/null || echo /root)"
fi

# 1) steamclient.so 就位
STEAMCLIENT=""
for cand in \
    "$SLIM_DIR/steamclient.so" \
    "$SLIM_DIR/game/bin/linuxsteamrt64/steamclient.so" \
    "$(find "$HOME" /usr/local /opt -name steamclient.so -path '*/linux64/*' 2>/dev/null | head -n1)"
do
  if [ -n "$cand" ] && [ -f "$cand" ]; then STEAMCLIENT="$cand"; break; fi
done

if [ -n "$STEAMCLIENT" ]; then
  mkdir -p "$STEAM_HOME/.steam/sdk64"
  ln -sf "$(readlink -f "$STEAMCLIENT")" "$STEAM_HOME/.steam/sdk64/steamclient.so"
  echo "[setup] steamclient.so -> $STEAM_HOME/.steam/sdk64/steamclient.so"
else
  echo "[setup] WARN: 找不到 steamclient.so，请先运行一键脚本或 setup.sh" >&2
fi

# 2) V8 库符号链接
if [ -d game/csgo/bin/linuxsteamrt64 ]; then
  cd game/csgo/bin/linuxsteamrt64
  for f in libv8.so libv8system.so libv8_icui18n.so libv8_icuuc.so \
           libv8_libbase.so libv8_libcpp.so libv8_libplatform.so libv8_zlib.so; do
    if [ -f "../../../bin/linuxsteamrt64/$f" ]; then
      ln -sf "../../../bin/linuxsteamrt64/$f" "$f"
    fi
  done
  cd "$SLIM_DIR" || exit 1
fi

# 3) 启动服务端
exec ./game/bin/linuxsteamrt64/cs2 \
  -dedicated +map de_dust2 +hostname "SlimTest" \
  -maxplayers 12 -ip 0.0.0.0 -port 27015 \
  -insecure -condebug +game_type 0 +game_mode 0 \
  +sv_pure 0 +sv_cheats 1