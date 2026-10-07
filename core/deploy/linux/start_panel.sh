#!/bin/bash
# CS2 精简服务端 面板启动脚本（简幻欢 / Pterodactyl 等面板通用）
#
# 面板启动命令: bash start.sh
#
# 分段式交互菜单（仅首次交互启动时显示，之后不再打扰）：
#   bash start.sh             首次交互启动显示菜单，之后直接完整启动
#   bash start.sh menu        强制显示菜单（想再次打开时使用）
#   bash start.sh auto        跳过菜单，直接完整启动（面板自动重启推荐）
#   bash start.sh web         只启动插件管理 Web（打印 token）
#   bash start.sh token       只显示当前 token
#   bash start.sh webstop     停止插件管理 Web
#
# 说明：菜单只在首次交互启动时显示一次，选择后 CS2 前台运行，服务端日志正常显示；
#       之后不再自动显示。想再次打开菜单：在面板环境变量加 CS2LM_MENU=1，
#       或在 start.sh 顶部加 export CS2LM_MENU=1，也可删除 .cs2slim_menu_seen 后再次交互启动。
#
# 本脚本内置一键安装：
#   - 首次启动：若精简树未安装，自动执行 prebuilt 一键安装
#   - 已安装：自动链接 steamclient.so + V8 符号链接后启动服务端
#
# 可用环境变量：
#   CS2_MAPS      选配地图，逗号分隔（默认 de_dust2）
#   CS2_FEATURES  选配功能，逗号分隔（默认空）
#   CS2_SLIM_DIR  精简树路径（默认 $HOME/cs2-slim-build/slim）
#   CS2_PORT      指定端口（默认 27015；面板参数 SERVER_PORT 优先于它）
#   SERVER_PORT   面板注入的端口（简幻欢等，优先级最高）
#   CS2LM_WEB     设为 1 时启用插件管理 Web（默认不启动）
#   CS2LM_MENU    设为 1 时强制显示菜单，设为 0 时强制跳过
#   CS2LM_AUTO    设为 1 时跳过菜单（面板自动重启场景）

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

# 端口：面板参数 SERVER_PORT 优先，其次用户变量 CS2_PORT，默认 27015
PORT="${SERVER_PORT:-${CS2_PORT:-27015}}"

# 首次菜单标记：菜单只在首次交互启动时显示，之后不再显示（除非显式 menu / CS2LM_MENU=1）
MENU_SEEN_FILE="$SLIM_DIR/.cs2slim_menu_seen"

# ---------- 插件管理 Web 段（link-manager 功能；与 CS2 同端口 UDP/TCP 共存） ----------
start_web() {
  if [ ! -x "$SLIM_DIR/cs2lm" ]; then
    echo "[cs2slim] 错误: 未找到 $SLIM_DIR/cs2lm，请先安装 link-manager 功能包" >&2
    return 1
  fi
  # 旧进程清理（面板重启时避免端口占用）
  if [ -f "$SLIM_DIR/web.pid" ]; then
    OLD_PID="$(cat "$SLIM_DIR/web.pid" 2>/dev/null || true)"
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
      echo "[cs2slim] 停止旧的插件管理 Web (pid $OLD_PID)"
      kill "$OLD_PID" 2>/dev/null || true
      sleep 1
    fi
  fi
  # 自动初始化插件仓库（幂等）
  LM_REPO="$SLIM_DIR/plugins-repo"
  if [ ! -f "$LM_REPO/config.json" ]; then
    echo "[cs2slim] 初始化插件仓库: $LM_REPO"
    "$SLIM_DIR/cs2lm" init --server "$SLIM_DIR" --repo "$LM_REPO" >/dev/null 2>&1 || \
      echo "[cs2slim] WARN: cs2lm init 失败（web 不启动），详见 $SLIM_DIR/web.log" >&2
  fi
  # Token：优先环境变量；无论哪种来源都写入 web_token.txt（唯一可靠来源）
  TOKEN="${CS2LM_WEB_TOKEN:-}"
  if [ -z "$TOKEN" ]; then
    TOKEN="$(openssl rand -hex 8 2>/dev/null || tr -dc 'a-f0-9' </dev/urandom | head -c16)"
  fi
  echo "$TOKEN" > "$SLIM_DIR/web_token.txt"
  chmod 600 "$SLIM_DIR/web_token.txt"
  # 可选手动回显 cfg：运行中在 CS2 控制台输入 exec cs2slim_token.cfg 可重新查看 token
  TOKEN_CFG="$SLIM_DIR/game/csgo/cfg/cs2slim_token.cfg"
  if [ -d "$SLIM_DIR/game/csgo" ]; then
    mkdir -p "$(dirname "$TOKEN_CFG")"
    {
      echo 'echo ================================================'
      echo "echo [cs2slim] Plugin manager web: http://SERVER_IP:$PORT/?token=$TOKEN"
      echo 'echo [cs2slim] Token also saved in: web_token.txt'
      echo 'echo ================================================'
    } > "$TOKEN_CFG"
    chmod 600 "$TOKEN_CFG" 2>/dev/null || true
  fi
  # 启动 Web（TCP 端口与 CS2 UDP 端口相同，协议不同互不冲突）
  echo "[cs2slim] 启动插件管理 Web (TCP $PORT): http://<IP>:$PORT/?token=$TOKEN"
  nohup "$SLIM_DIR/cs2lm" web --host 0.0.0.0 --port "$PORT" --auth-token "$TOKEN" \
    >> "$SLIM_DIR/web.log" 2>&1 &
  echo $! > "$SLIM_DIR/web.pid"
  # 启动失败可感知
  sleep 1
  if ! kill -0 "$(cat "$SLIM_DIR/web.pid" 2>/dev/null)" 2>/dev/null; then
    echo "[cs2slim] WARNING: 插件管理 Web 启动失败，请查看 $SLIM_DIR/web.log" >&2
    return 1
  fi
  return 0
}

stop_web() {
  if [ -f "$SLIM_DIR/web.pid" ]; then
    OLD_PID="$(cat "$SLIM_DIR/web.pid" 2>/dev/null || true)"
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
      echo "[cs2slim] 停止插件管理 Web (pid $OLD_PID)"
      kill "$OLD_PID" 2>/dev/null || true
      rm -f "$SLIM_DIR/web.pid"
      return 0
    fi
  fi
  echo "[cs2slim] 插件管理 Web 未在运行"
  return 0
}

show_token() {
  if [ -f "$SLIM_DIR/web_token.txt" ]; then
    TOKEN="$(cat "$SLIM_DIR/web_token.txt" 2>/dev/null || true)"
    echo "[cs2slim] 插件管理 Web: http://<IP>:$PORT/?token=$TOKEN"
    echo "[cs2slim] token 文件: $SLIM_DIR/web_token.txt"
  else
    echo "[cs2slim] 尚未生成 token（请先启动 Web）"
  fi
}

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

# ---------- 分段式参数：无需菜单直接执行 ----------
case "${1:-}" in
  web)         start_web; exit $? ;;
  token)       show_token; exit $? ;;
  webstop|stop) stop_web; exit $? ;;
  auto|start)  MODE=auto ;;
  menu)        MODE=menu ;;
  *)           if [ -t 0 ] && [ ! -f "$MENU_SEEN_FILE" ]; then MODE=menu; else MODE=auto; fi ;;
esac

# ---------- 分段式交互菜单（仅首次显示；之后可用 menu / CS2LM_MENU=1 再次打开） ----------
if [ "$MODE" = "menu" ]; then
  echo ""
  echo "=================================================="
  echo " CS2 精简服务端 - 请选择操作"
  echo "=================================================="
  echo " [1] 完整启动（插件管理 Web + CS2 服务端）"
  echo " [2] 只启动插件管理 Web 并显示 token"
  echo " [3] 只启动 CS2 服务端"
  echo " [4] 查看当前 token"
  echo " [5] 停止插件管理 Web"
  echo " [6] 退出"
  echo "=================================================="
  read -t 15 -p "请输入数字 [默认 1]: " CHOICE || CHOICE="1"
  CHOICE="${CHOICE:-1}"
  touch "$MENU_SEEN_FILE"
else
  CHOICE="1"
fi

case "$CHOICE" in
  2) start_web; exit $? ;;
  4) show_token; exit $? ;;
  5) stop_web; exit $? ;;
  6) echo "[cs2slim] 已退出"; exit 0 ;;
  3) SKIP_WEB=1 ;;
  *) CHOICE="1" ;;
esac

# 完整启动：CS2LM_WEB=1 时启动 Web（可选配置，默认不启动）
if [ "$CHOICE" = "1" ] && [ "${CS2LM_WEB:-0}" = "1" ] && [ -x "$SLIM_DIR/cs2lm" ]; then
  start_web
fi

# 菜单模式提示：接下来控制台将切换到 CS2 服务端日志
if [ "$MODE" = "menu" ]; then
  echo "[cs2slim] 正在启动 CS2 服务端，控制台将显示服务端日志（菜单仅首次显示）"
  echo "[cs2slim] 如需再次打开菜单: 面板环境变量加 CS2LM_MENU=1，或在 start.sh 顶部加 export CS2LM_MENU=1"
fi

# ---------- 5. 启动服务端 ----------
exec ./game/bin/linuxsteamrt64/cs2 \
  -dedicated +map de_dust2 +hostname "SlimTest" \
  -maxplayers 12 -ip 0.0.0.0 -port "$PORT" \
  -insecure -condebug +game_type 0 +game_mode 0 \
  +sv_pure 0 +sv_cheats 1