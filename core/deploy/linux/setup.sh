#!/bin/bash
# CS2 精简服务端 一次性部署脚本 (在 Linux 上执行一次)
# 1) 放置 steamclient.so 到 /root/.steam/sdk64/
# 2) 创建 V8 库符号链接 (game/csgo/bin/linuxsteamrt64 -> game/bin/linuxsteamrt64)
# 3) 设置可执行权限
set -e
cd "$(dirname "$0")"

echo "[1/3] steamclient.so ..."
if [ -f steamclient.so ]; then
  mkdir -p /root/.steam/sdk64
  ln -sf "$(readlink -f steamclient.so)" /root/.steam/sdk64/steamclient.so
  echo "  OK -> /root/.steam/sdk64/steamclient.so"
else
  echo "  WARN: steamclient.so 不存在于本目录，跳过 (服务端可能无法连接 Steam 网络)"
fi

echo "[2/3] V8 库符号链接 ..."
cd game/csgo/bin/linuxsteamrt64
for f in libv8.so libv8system.so libv8_icui18n.so libv8_icuuc.so \
         libv8_libbase.so libv8_libcpp.so libv8_libplatform.so libv8_zlib.so; do
  if [ -f "../../../bin/linuxsteamrt64/$f" ]; then
    ln -sf "../../../bin/linuxsteamrt64/$f" "$f"
    echo "  link $f"
  else
    echo "  WARN: 缺少 ../../../bin/linuxsteamrt64/$f"
  fi
done
cd - >/dev/null

echo "[3/3] 可执行权限 ..."
chmod +x game/bin/linuxsteamrt64/cs2
chmod +x start_server.sh

echo
echo "部署完成。运行: ./start_server.sh"