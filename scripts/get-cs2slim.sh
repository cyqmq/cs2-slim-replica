#!/usr/bin/env bash
#
# cs2slim 一键安装脚本 (Linux)
#
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/cyqmq/cs2-slim-replica/main/scripts/get-cs2slim.sh | bash
#
# 环境变量（可选）:
#   CS2_MAPS      逗号分隔地图列表, 默认 de_dust2
#   CS2_FEATURES  逗号分隔功能列表, 默认空
#   CS2_WORKDIR   工作目录, 默认 $HOME/cs2-slim-build
#   CS2_PACKAGE   1=完成后打包 tar.gz, 默认 0
#   CS2_DRY_RUN   1=只生成配置不下载(预览), 默认 0
#
# 示例:
#   CS2_MAPS=de_dust2,de_mirage CS2_FEATURES=bots \
#     curl -fsSL https://raw.githubusercontent.com/cyqmq/cs2-slim-replica/main/scripts/get-cs2slim.sh | bash
#
set -euo pipefail

# --- 配置 ---
MAPS="${CS2_MAPS:-de_dust2}"
FEATURES="${CS2_FEATURES:-}"
WORKDIR="${CS2_WORKDIR:-$HOME/cs2-slim-build}"
PACKAGE="${CS2_PACKAGE:-0}"
DRY_RUN="${CS2_DRY_RUN:-0}"
REPO_URL="https://github.com/cyqmq/cs2-slim-replica.git"
DD_URL="https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_3.4.0/DepotDownloader-linux-x64.zip"
STEAMCMD_URL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"

echo "== cs2slim 一键安装 (Linux) =="
echo "地图: $MAPS / 功能: ${FEATURES:-无} / 工作目录: $WORKDIR"

# --- 依赖检查 ---
command -v python3 >/dev/null 2>&1 || { echo "错误: 需要 python3"; exit 1; }
command -v curl  >/dev/null 2>&1 || { echo "错误: 需要 curl"; exit 1; }

mkdir -p "$WORKDIR/tools"

# --- 1. DepotDownloader ---
DD_DIR="$WORKDIR/tools/depotdownloader"
if [ "$DRY_RUN" = "1" ]; then
  echo "[1/5] (dry-run) 跳过 DepotDownloader 下载"
else
  if [ ! -f "$DD_DIR/DepotDownloader" ]; then
    echo "[1/5] 下载 DepotDownloader ..."
    mkdir -p "$DD_DIR"
    curl -fsSL -o "$DD_DIR/dd.zip" "$DD_URL"
    python3 - "$DD_DIR" <<'PY'
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

# --- 2. steamclient.so (SteamCMD) ---
SC_DIR="$WORKDIR/tools/steamclient64"
if [ "$DRY_RUN" = "1" ]; then
  echo "[2/5] (dry-run) 跳过 steamclient.so 下载"
else
  if [ ! -f "$SC_DIR/steamclient.so" ]; then
    echo "[2/5] 下载 SteamCMD 获取 steamclient.so ..."
    mkdir -p "$SC_DIR"
    curl -fsSL -o "$SC_DIR/steamcmd.tar.gz" "$STEAMCMD_URL"
    (cd "$SC_DIR" && tar xzf steamcmd.tar.gz linux64/steamclient.so \
        && mv linux64/steamclient.so ./steamclient.so \
        && rm -rf linux64 steamcmd.tar.gz)
  fi
fi

# --- 3. 获取主仓库 ---
REPO_DIR="$WORKDIR/repo"
if [ ! -d "$REPO_DIR/.git" ]; then
  echo "[3/5] 获取主仓库 ..."
  if command -v git >/dev/null 2>&1; then
    git clone --depth 1 "$REPO_URL" "$REPO_DIR"
  else
    mkdir -p "$REPO_DIR"
    curl -fsSL "https://github.com/cyqmq/cs2-slim-replica/archive/refs/heads/main.tar.gz" \
      | tar xz --strip-components=1 -C "$REPO_DIR"
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

# --- 5. 一键执行 download + extract + build (+package) ---
PACKAGE_FLAG=""
if [ "$PACKAGE" = "1" ]; then
  PACKAGE_FLAG="--package"
fi
if [ "$DRY_RUN" = "1" ]; then
  echo "[5/5] (dry-run) 跳过一键执行"
  echo "将执行: python3 $REPO_DIR/cs2slim.py all --config $CFG $PACKAGE_FLAG"
  exit 0
fi
echo "[5/5] 开始下载/提取/组装 (首次约 1.5GB 下载, 请耐心等待) ..."
python3 "$REPO_DIR/cs2slim.py" all --config "$CFG" $PACKAGE_FLAG

echo
echo "=============================================="
echo "✅ 完成! 启动服务端:"
echo "  bash $WORKDIR/slim/start_server.sh"
if [ "$PACKAGE" = "1" ]; then
  echo "  安装包: $WORKDIR/cs2-slim-linux.tar.gz"
fi
echo "=============================================="