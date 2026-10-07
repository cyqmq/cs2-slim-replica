#!/bin/bash
# CS2 精简专用服务端 启动脚本 (de_dust2, -insecure)
# 启动前自动完成:
#   1) 放置 steamclient.so 到 $HOME/.steam/sdk64/ (容器 HOME 可能是 /home/container 而非 /root)
#   2) V8 库符号链接 (game/csgo/bin/linuxsteamrt64 -> game/bin/linuxsteamrt64)
cd "$(dirname "$0")"

# 端口：面板参数 SERVER_PORT 优先，其次用户变量 CS2_PORT，默认 27015
PORT="${SERVER_PORT:-${CS2_PORT:-27015}}"

# 0) 修复执行权限（面板/部署环境可能未保留 +x）
chmod +x game/bin/linuxsteamrt64/cs2 2>/dev/null || true

# 计算 Steam 家目录：优先 $HOME（root=/root, 容器=/home/container, 任意用户=/home/用户名）
STEAM_HOME="${HOME:-}"
if [ -z "$STEAM_HOME" ]; then
  STEAM_HOME="$(getent passwd "$(id -u)" | cut -d: -f6 2>/dev/null || echo /root)"
fi

# 1) steamclient.so 就位
if [ -f steamclient.so ]; then
  mkdir -p "$STEAM_HOME/.steam/sdk64"
  ln -sf "$(readlink -f steamclient.so)" "$STEAM_HOME/.steam/sdk64/steamclient.so"
  echo "[setup] steamclient.so -> $STEAM_HOME/.steam/sdk64/steamclient.so"
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

# 3) 可选: 插件管理 Web（link-manager 功能；与 CS2 同端口 UDP/TCP 共存，需 CS2LM_WEB=1）
if [ "${CS2LM_WEB:-0}" = "1" ] && [ -x "$(pwd)/cs2lm" ]; then
  SLIM_DIR="$(pwd)"
  # 旧进程清理
  if [ -f "$SLIM_DIR/web.pid" ]; then
    OLD_PID="$(cat "$SLIM_DIR/web.pid" 2>/dev/null || true)"
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
      echo "[setup] 停止旧的插件管理 Web (pid $OLD_PID)"
      kill "$OLD_PID" 2>/dev/null || true
      sleep 1
    fi
  fi
  # 自动初始化插件仓库（幂等）
  LM_REPO="$SLIM_DIR/plugins-repo"
  if [ ! -f "$LM_REPO/config.json" ]; then
    echo "[setup] 初始化插件仓库: $LM_REPO"
    "$SLIM_DIR/cs2lm" init --server "$SLIM_DIR" --repo "$LM_REPO" >/dev/null 2>&1 || \
      echo "[setup] WARN: cs2lm init 失败（web 不启动），详见 $SLIM_DIR/web.log" >&2
  fi
  # Token：优先环境变量，否则随机生成并写入 web_token.txt
  TOKEN="${CS2LM_WEB_TOKEN:-}"
  if [ -z "$TOKEN" ]; then
    TOKEN="$(openssl rand -hex 8 2>/dev/null || tr -dc 'a-f0-9' </dev/urandom | head -c16)"
    echo "$TOKEN" > "$SLIM_DIR/web_token.txt"
    chmod 600 "$SLIM_DIR/web_token.txt"
  fi
  echo "[setup] 启动插件管理 Web (TCP $PORT): http://<IP>:$PORT/?token=$TOKEN"
  nohup "$SLIM_DIR/cs2lm" web --host 0.0.0.0 --port "$PORT" --auth-token "$TOKEN" \
    >> "$SLIM_DIR/web.log" 2>&1 &
  echo $! > "$SLIM_DIR/web.pid"
  # 启动失败可感知
  sleep 1
  if ! kill -0 "$(cat "$SLIM_DIR/web.pid" 2>/dev/null)" 2>/dev/null; then
    echo "[setup] WARNING: 插件管理 Web 启动失败，请查看 $SLIM_DIR/web.log" >&2
  fi
fi

exec ./game/bin/linuxsteamrt64/cs2 \
  -dedicated +map de_dust2 +hostname "SlimTest" \
  -maxplayers 12 -ip 0.0.0.0 -port "$PORT" \
  -insecure -condebug +game_type 0 +game_mode 0 \
  +sv_pure 0 +sv_cheats 1