#!/usr/bin/env bash
#
# cs2slim 一键安装脚本 (Linux)
#
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/cyqmq/cs2-slim-replica/main/scripts/get-cs2slim.sh | bash
#
# 环境变量（可选）:
#   CS2_MODE       source(默认, 从 depot 构建) | prebuilt(直接拉取 Release 包拼装)
#   CS2_MAPS      逗号分隔地图列表, 默认 de_dust2
#   CS2_FEATURES  逗号分隔功能列表, 默认空
#   CS2_WORKDIR   工作目录, 默认 $HOME/cs2-slim-build
#   CS2_PACKAGE   1=完成后打包 tar.gz, 默认 0
#   CS2_DRY_RUN   1=只生成配置不下载(预览), 默认 0
#   CS2_GH_PROXY  GitHub 加速代理前缀(如 https://ghproxy.com), 用于仓库/Release 下载
#   CS2_PANEL     1=面板模式(简幻欢/Pterodactyl等): 完成后在 $HOME 生成 start.sh, 默认 0
#
# 重要: 使用 curl | bash 时，请先用 export 设置变量！
#   错误: CS2_MODE=prebuilt ... curl ... | bash   (变量只传给 curl，bash 收不到)
#   正确: export CS2_MODE=prebuilt CS2_MAPS=...; curl ... | bash
#
# 示例:
#   export CS2_MODE=prebuilt CS2_MAPS=de_dust2,de_mirage CS2_FEATURES=bots
#   curl -fsSL https://raw.githubusercontent.com/cyqmq/cs2-slim-replica/main/scripts/get-cs2slim.sh | bash
#
set -euo pipefail

# --- 配置 ---
MAPS="${CS2_MAPS:-de_dust2}"
FEATURES="${CS2_FEATURES:-}"
WORKDIR="${CS2_WORKDIR:-$HOME/cs2-slim-build}"
PACKAGE="${CS2_PACKAGE:-0}"
DRY_RUN="${CS2_DRY_RUN:-0}"
MODE="${CS2_MODE:-source}"
PANEL="${CS2_PANEL:-0}"
DD_URL="https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_3.4.0/DepotDownloader-linux-x64.zip"
STEAM_MANIFEST_URL="https://client-update.akamai.steamstatic.com/steam_client_ubuntu12"

echo "== cs2slim 一键安装 (Linux) =="
echo "模式: $MODE / 地图: $MAPS / 功能: ${FEATURES:-无} / 工作目录: $WORKDIR"
if [ "$MODE" = "prebuilt" ]; then
  echo "(预构建模式: 直接从 GitHub Release 拉取并拼装，无需 depot 下载)"
fi

# --- 依赖检查 ---
PY=""
command -v python3 >/dev/null 2>&1 && PY="python3"
if [ -z "$PY" ]; then command -v python >/dev/null 2>&1 && PY="python"; fi
if [ -z "$PY" ]; then echo "错误: 需要 python3 或 python"; exit 1; fi
command -v curl  >/dev/null 2>&1 || { echo "错误: 需要 curl"; exit 1; }

mkdir -p "$WORKDIR/tools"

# --- 1. DepotDownloader ---
DD_DIR="$WORKDIR/tools/depotdownloader"
if [ "$MODE" = "prebuilt" ]; then
  echo "[1/5] (prebuilt) 跳过 DepotDownloader 下载"
elif [ "$DRY_RUN" = "1" ]; then
  echo "[1/5] (dry-run) 跳过 DepotDownloader 下载"
else
  if [ ! -f "$DD_DIR/DepotDownloader" ]; then
    echo "[1/5] 下载 DepotDownloader ..."
    mkdir -p "$DD_DIR"
    curl -fL --retry 3 -C - --progress-bar -o "$DD_DIR/dd.zip" "$DD_URL"
    $PY - "$DD_DIR" <<'PY'
import sys, zipfile, os
d = sys.argv[1]
p = os.path.join(d, "dd.zip")
with zipfile.ZipFile(p) as z:
    z.extractall(d)
os.remove(p)
PY
    chmod +x "$DD_DIR/DepotDownloader"
  fi
fi
DD_EXE="$DD_DIR/DepotDownloader"

# --- 2. steamclient.so (Steam SDK 包) ---
SC_DIR="$WORKDIR/tools/steamclient64"
if [ "$MODE" = "prebuilt" ]; then
  echo "[2/5] (prebuilt) 跳过 steamclient.so 下载"
elif [ "$DRY_RUN" = "1" ]; then
  echo "[2/5] (dry-run) 跳过 steamclient.so 下载"
else
  if [ ! -f "$SC_DIR/steamclient.so" ]; then
    echo "[2/5] 下载 Steam SDK 获取 steamclient.so ..."
    mkdir -p "$SC_DIR"
    curl -fL --retry 3 -C - -o "$SC_DIR/steam_client_ubuntu12" "$STEAM_MANIFEST_URL"
    SDK_FILE=$(grep -A4 '"bins_sdk_ubuntu12"' "$SC_DIR/steam_client_ubuntu12" | grep '"file"' | sed -n 's/.*"file"[[:space:]]*"\([^"]*\)".*/\1/p')
    if [ -z "$SDK_FILE" ]; then
      echo "错误: 无法在 Steam manifest 中找到 bins_sdk_ubuntu12" >&2
      exit 1
    fi
    curl -fL --retry 3 -C - --progress-bar -o "$SC_DIR/bins_sdk.zip" "https://steamcdn-a.akamaihd.net/client/$SDK_FILE"
    $PY - "$SC_DIR" <<'PY'
import sys, zipfile, os
d = sys.argv[1]
with zipfile.ZipFile(os.path.join(d, "bins_sdk.zip")) as z:
    z.extract("linux64/steamclient.so", d)
os.replace(os.path.join(d, "linux64", "steamclient.so"), os.path.join(d, "steamclient.so"))
os.remove(os.path.join(d, "bins_sdk.zip"))
PY
    rm -rf "$SC_DIR/linux64" "$SC_DIR/steam_client_ubuntu12"
  fi
fi

# --- 3. 获取主仓库 (带 GitHub 镜像回退) ---
REPO_DIR="$WORKDIR/repo"
GIT_URLS=(
  "https://github.com/cyqmq/cs2-slim-replica.git"
  "https://ghproxy.com/https://github.com/cyqmq/cs2-slim-replica.git"
  "https://gitclone.com/github.com/cyqmq/cs2-slim-replica.git"
  "https://ghfast.top/https://github.com/cyqmq/cs2-slim-replica.git"
)
TAR_URLS=(
  "https://github.com/cyqmq/cs2-slim-replica/archive/refs/heads/main.tar.gz"
  "https://ghproxy.com/https://github.com/cyqmq/cs2-slim-replica/archive/refs/heads/main.tar.gz"
  "https://gh-proxy.com/https://github.com/cyqmq/cs2-slim-replica/archive/refs/heads/main.tar.gz"
  "https://ghfast.top/https://github.com/cyqmq/cs2-slim-replica/archive/refs/heads/main.tar.gz"
  "https://github.moeyy.xyz/https://github.com/cyqmq/cs2-slim-replica/archive/refs/heads/main.tar.gz"
)
if [ ! -d "$REPO_DIR/.git" ] && [ ! -f "$REPO_DIR/cs2slim.py" ]; then
  echo "[3/5] 获取主仓库 ..."
  # 尝试 git clone（多镜像）
  if command -v git >/dev/null 2>&1; then
    for url in "${GIT_URLS[@]}"; do
      echo "  尝试: git clone $url"
      if git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=15 clone --depth 1 "$url" "$REPO_DIR" >/dev/null 2>&1; then
        break
      fi
      rm -rf "$REPO_DIR"
    done
  fi
  # git clone 失败则尝试源码包
  if [ ! -d "$REPO_DIR/.git" ] && [ ! -f "$REPO_DIR/cs2slim.py" ]; then
    mkdir -p "$REPO_DIR"
    for url in "${TAR_URLS[@]}"; do
      echo "  尝试: 下载源码包 $url"
      if curl -fL --retry 2 -C - --connect-timeout 15 --max-time 600 -o "$WORKDIR/repo.tar.gz" "$url" \
          && tar xzf "$WORKDIR/repo.tar.gz" --strip-components=1 -C "$REPO_DIR" 2>/dev/null; then
        rm -f "$WORKDIR/repo.tar.gz"
        break
      fi
      rm -rf "$REPO_DIR"/* "$WORKDIR/repo.tar.gz"
    done
  fi
  if [ ! -d "$REPO_DIR/.git" ] && [ ! -f "$REPO_DIR/cs2slim.py" ]; then
    echo "错误: 无法从 GitHub 获取主仓库（网络受限）。可设置加速代理后重试:" >&2
    echo "  export CS2_GH_PROXY=https://ghproxy.com" >&2
    exit 1
  fi
fi

# --- 4. 生成配置 ---
CFG="$WORKDIR/slim.yaml"
{
  echo "platform: linux"
  echo "maps: [$MAPS]"
  echo "features: [$FEATURES]"
  echo "workdir: $WORKDIR"
  echo "depot_tool: $DD_EXE"
} > "$CFG"
echo "[4/5] 配置已生成: $CFG"

# --- 5. 一键执行 (source: 构建 / prebuilt: 拉取拼装) ---
PACKAGE_FLAG=""
if [ "$PACKAGE" = "1" ]; then
  PACKAGE_FLAG="--package"
fi
if [ "$DRY_RUN" = "1" ]; then
  echo "[5/5] (dry-run) 跳过一键执行"
  if [ "$MODE" = "prebuilt" ]; then
    echo "将执行: $PY $REPO_DIR/cs2slim.py prebuilt --config $CFG"
  else
    echo "将执行: $PY $REPO_DIR/cs2slim.py all --config $CFG $PACKAGE_FLAG"
  fi
  exit 0
fi
if [ "$MODE" = "prebuilt" ]; then
  echo "[5/5] 拉取预构建包并自动拼装 (核心包约 1.1GB 下载) ..."
  $PY "$REPO_DIR/cs2slim.py" prebuilt --config "$CFG"
else
  echo "[5/5] 开始下载/提取/组装 (首次约 1.5GB 下载, 请耐心等待) ..."
  $PY "$REPO_DIR/cs2slim.py" all --config "$CFG" $PACKAGE_FLAG
fi

# --- 6. 面板模式: 生成/覆盖 $HOME/start.sh (简幻欢/Pterodactyl 等面板需要) ---
if [ "$PANEL" = "1" ]; then
  echo "[6] 面板模式: 部署启动脚本 ..."
  PANEL_TEMPLATE="$REPO_DIR/core/deploy/linux/start_panel.sh"
  if [ ! -f "$PANEL_TEMPLATE" ]; then
    echo "  本地仓库缺少 start_panel.sh，从 GitHub 获取 ..."
    curl -fL --retry 3 -o "$WORKDIR/start_panel.sh" \
      "https://raw.githubusercontent.com/cyqmq/cs2-slim-replica/main/core/deploy/linux/start_panel.sh"
    PANEL_TEMPLATE="$WORKDIR/start_panel.sh"
  fi
  if [ -f "$HOME/start.sh" ]; then
    echo "  检测到已有 $HOME/start.sh，覆盖为最新模板"
  fi
  cp "$PANEL_TEMPLATE" "$HOME/start.sh"
  chmod +x "$HOME/start.sh"
  echo "  已生成 $HOME/start.sh"
  echo "  请把面板启动命令设为:  bash start.sh"
fi

echo
echo "=============================================="
echo "✅ 完成! 启动服务端:"
if [ "$PANEL" = "1" ]; then
  echo "  bash $HOME/start.sh   (面板启动脚本)"
else
  echo "  bash $WORKDIR/slim/start_server.sh"
fi
if [ "$PACKAGE" = "1" ]; then
  echo "  安装包: $WORKDIR/cs2-slim-linux.tar.gz"
fi
echo "=============================================="