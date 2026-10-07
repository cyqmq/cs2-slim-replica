#!/bin/bash
# CS2 精简服务端 面板启动脚本（简幻欢 / Pterodactyl 等面板通用）
#
# 面板启动命令: bash start.sh
#
# 本脚本内置一键安装：
#   - 首次启动：若精简树未安装，自动执行 prebuilt 一键安装
#   - 已安装：自动链接 steamclient.so + V8 符号链接后启动服务端
#
# 可用环境变量：
#   CS2_MAPS      选配地图，逗号分隔（默认 de_dust2）
#   CS2_FEATURES  选配功能，逗号分隔（默认空）
#   CS2_SLIM_DIR  精简树路径（默认 $HOME/cs2-slim-build/slim）

SLIM_DIR="${CS2_SLIM_DIR:-$HOME/cs2-slim-build/slim}"
CS2_BIN="$SLIM_DIR/game/bin/linuxsteamrt64/cs2"

# ---------- 1. 未安装时自动一键安装 ----------
if [ ! -x "$CS2_BIN" ]; then
  echo "[cs2slim] 未检测到精简服务端，开始自动安装（prebuilt 模式）..."
  echo "[cs2slim] 地图: ${CS2_MAPS:-de_dust2} / 功能: ${CS2_FEATURES:-无}"
  export CS2_MODE=prebuilt
  export CS2_MAPS="${CS2_MAPS:-de_dust2}"
  export CS2_FEATURES="${CS2_FEATURES:-}"
  export CS2_PANEL=1
  curl -fsSL --retry 3 \
    https://raw.githubusercontent.com/cyqmq/cs2-slim-replica/main/scripts/get-cs2slim.sh | bash
  # 安装成功会重新生成 start.sh（同款模板），重新执行以干净状态继续
  if [ -x "$CS2_BIN" ]; then
    exec bash "$HOME/start.sh"
  fi
  echo "[cs2slim] 错误: 自动安装失败，请检查网络/磁盘后再次启动" >&2
  exit 1
fi

cd "$SLIM_DIR" || { echo "[cs2slim] 错误: 无法进入 $SLIM_DIR" >&2; exit 1; }

# ---------- 2. 权限修复（面板默认只给 start.sh 执行权限） ----------
chmod +x game/bin/linuxsteamrt64/cs2 2>/dev/null || true
chmod +x start_server.sh 2>/dev/null || true

# ---------- 3. steamclient.so 就位 ----------
STEAM_HOME="${HOME:-}"
if [ -z "$STEAM_HOME" ]; then
  STEAM_HOME="$(getent passwd "$(id -u)" | cut -d: -f6 2>/dev/null || echo /root)"
fi

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

# ---------- 4. V8 库符号链接 ----------
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

# ---------- 5. 插件管理 Web（可选配置：CS2LM_WEB=1 且已装 link-manager；与 CS2 同端口 UDP/TCP 共存）----------
if [ "${CS2LM_WEB:-0}" = "1" ] && [ -x "$SLIM_DIR/cs2lm" ]; then
  # 5.1 旧进程清理（面板重启时避免端口占用）
  if [ -f "$SLIM_DIR/web.pid" ]; then
    OLD_PID="$(cat "$SLIM_DIR/web.pid" 2>/dev/null || true)"
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
      echo "[cs2slim] 停止旧的插件管理 Web (pid $OLD_PID)"
      kill "$OLD_PID" 2>/dev/null || true
      sleep 1
    fi
  fi

  # 5.2 自动初始化插件仓库（幂等）
  LM_REPO="$SLIM_DIR/plugins-repo"
  if [ ! -f "$LM_REPO/config.json" ]; then
    echo "[cs2slim] 初始化插件仓库: $LM_REPO"
    "$SLIM_DIR/cs2lm" init --server "$SLIM_DIR" --repo "$LM_REPO" >/dev/null 2>&1 || \
      echo "[cs2slim] WARN: cs2lm init 失败（web 不启动），详见 $SLIM_DIR/web.log" >&2
  fi

  # 5.3 Token：优先环境变量，否则随机生成并写入 web_token.txt
  TOKEN="${CS2LM_WEB_TOKEN:-}"
  if [ -z "$TOKEN" ]; then
    TOKEN="$(openssl rand -hex 8 2>/dev/null || tr -dc 'a-f0-9' </dev/urandom | head -c16)"
    echo "$TOKEN" > "$SLIM_DIR/web_token.txt"
    chmod 600 "$SLIM_DIR/web_token.txt"
  fi

  # 5.4 启动 Web（TCP 端口与 CS2 UDP 端口相同，协议不同互不冲突）
  PORT="${SERVER_PORT:-27015}"
  echo "[cs2slim] 启动插件管理 Web (TCP $PORT): http://<IP>:$PORT/?token=$TOKEN"
  nohup "$SLIM_DIR/cs2lm" web --host 0.0.0.0 --port "$PORT" --auth-token "$TOKEN" \
    >> "$SLIM_DIR/web.log" 2>&1 &
  echo $! > "$SLIM_DIR/web.pid"

  # 5.5 启动失败可感知
  sleep 1
  if ! kill -0 "$(cat "$SLIM_DIR/web.pid" 2>/dev/null)" 2>/dev/null; then
    echo "[cs2slim] WARNING: 插件管理 Web 启动失败，请查看 $SLIM_DIR/web.log" >&2
  fi
fi

# ---------- 6. 启动服务端 ----------
exec ./game/bin/linuxsteamrt64/cs2 \
  -dedicated +map de_dust2 +hostname "SlimTest" \
  -maxplayers 12 -ip 0.0.0.0 -port "${SERVER_PORT:-27015}" \
  -insecure -condebug +game_type 0 +game_mode 0 \
  +sv_pure 0 +sv_cheats 1