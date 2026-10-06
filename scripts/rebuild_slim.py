#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CS2 精简服务端 组装脚本（Linux + Windows）

前置条件：
  1. 三个 depot 已用 filelists 下载到 depot/2347770, depot/2347773, depot/2347771
  2. loose files 已用 scripts/extract_vpk.py 提取到 loose/game/csgo, loose/game/core

用法：
  python scripts/rebuild_slim.py

输出：
  slim/     Linux 精简树（game/bin/linuxsteamrt64 + csgo loose + core + de_dust2 + prefabs）
  slim-win/ Windows 精简树（game/bin/win64 + 同上 + V8 DLL 复制 + steamclient 三件套）
"""

import os
import shutil

BASE = r"C:\Users\Administrator\cs2-replica"
DEPOT = os.path.join(BASE, "depot")
LOOSE = os.path.join(BASE, "loose")
TOOLS = os.path.join(BASE, "tools")

SHARED = os.path.join(DEPOT, "2347770")   # 共享内容
LINUX_BIN = os.path.join(DEPOT, "2347773")  # Linux 服务端二进制
WIN_BIN = os.path.join(DEPOT, "2347771")     # Windows 服务端二进制

SLIM = os.path.join(BASE, "slim")
SLIM_WIN = os.path.join(BASE, "slim-win")

STEAMCLIENT_SO = os.path.join(TOOLS, "steamclient64", "steamclient.so")
STEAMCLIENT_WIN_DIR = os.path.join(TOOLS, "steamclient64_win")


def copy_tree(src, dst):
    shutil.copytree(src, dst, dirs_exist_ok=True)
    print(f"  tree: {os.path.relpath(dst, BASE)}")


def copy_file(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)
    print(f"  file: {os.path.relpath(dst, BASE)}")


def clear_tree(path):
    if os.path.exists(path):
        shutil.rmtree(path)
    os.makedirs(path, exist_ok=True)
    print(f"  cleared: {os.path.relpath(path, BASE)}")


def copy_shared_content(dst):
    """复制与平台无关的共享内容（csgo loose + core loose + cfg + maps + 根散文件）。"""
    copy_tree(os.path.join(LOOSE, "game", "csgo"), os.path.join(dst, "game", "csgo"))
    copy_tree(os.path.join(LOOSE, "game", "core"), os.path.join(dst, "game", "core"))
    copy_tree(os.path.join(SHARED, "game", "csgo", "cfg"), os.path.join(dst, "game", "csgo", "cfg"))
    copy_file(os.path.join(SHARED, "game", "csgo", "maps", "de_dust2.vpk"),
              os.path.join(dst, "game", "csgo", "maps", "de_dust2.vpk"))
    copy_tree(os.path.join(SHARED, "game", "csgo", "maps", "prefabs"),
              os.path.join(dst, "game", "csgo", "maps", "prefabs"))
    for f in ["gameinfo.gi", "gameinfo_branchspecific.gi", "steam.inf"]:
        copy_file(os.path.join(SHARED, "game", "csgo", f), os.path.join(dst, "game", "csgo", f))
    for f in ["gameinfo.gi", "gameinfo_branchspecific.gi"]:
        copy_file(os.path.join(SHARED, "game", "core", f), os.path.join(dst, "game", "core", f))


def assemble_linux():
    print("=== Linux 精简树 ===")
    clear_tree(SLIM)
    copy_tree(os.path.join(LINUX_BIN, "game", "bin", "linuxsteamrt64"),
              os.path.join(SLIM, "game", "bin", "linuxsteamrt64"))
    copy_tree(os.path.join(LINUX_BIN, "game", "csgo", "bin", "linuxsteamrt64"),
              os.path.join(SLIM, "game", "csgo", "bin", "linuxsteamrt64"))
    copy_shared_content(SLIM)
    copy_file(STEAMCLIENT_SO, os.path.join(SLIM, "steamclient.so"))
    _write_linux_scripts()


def _write_linux_scripts():
    setup_sh = r"""#!/bin/bash
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
"""
    start_sh = r"""#!/bin/bash
# CS2 精简专用服务端 启动脚本 (de_dust2, -insecure)
cd "$(dirname "$0")"
exec ./game/bin/linuxsteamrt64/cs2 \
  -dedicated +map de_dust2 +hostname "SlimTest" \
  -maxplayers 12 -ip 0.0.0.0 -port 27015 \
  -insecure -condebug +game_type 0 +game_mode 0 \
  +sv_pure 0 +sv_cheats 1
"""
    readme = """CS2 精简专用服务端 - Linux 版 (de_dust2)
=========================================

- 体积: 解压后约 1.7GB (原版 72.3GB)
- 单地图: de_dust2
- 运行模式: -insecure (无 VAC)

部署
----
  sudo ./setup.sh
  ./start_server.sh

setup.sh 会:
  1. 将 steamclient.so 链接到 /root/.steam/sdk64/steamclient.so
  2. 在 game/csgo/bin/linuxsteamrt64 下为 V8 库创建相对符号链接
  3. 设置可执行权限

验证启动 (console.log)
----------------------
  [Server] SV:  12 player server started
  [Server] CSource2Server::GameServerSteamAPIActivated()
  [Networking] Network socket 'server' opened on port 27015

注意
----
- 启动时的 Failed loading resource ... (ERROR_FILEOPEN) 为外观类资源缺失，非致命。
- 若提示缺某 pak01_NNN.vpk，需重新提取并补充对应编号包。
"""
    for path, content in [
        (os.path.join(SLIM, "setup.sh"), setup_sh),
        (os.path.join(SLIM, "start_server.sh"), start_sh),
        (os.path.join(SLIM, "README.txt"), readme),
    ]:
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(content)
        print(f"  wrote: {os.path.relpath(path, BASE)}")


def assemble_windows():
    print("=== Windows 精简树 ===")
    clear_tree(SLIM_WIN)
    copy_tree(os.path.join(WIN_BIN, "game", "bin", "win64"),
              os.path.join(SLIM_WIN, "game", "bin", "win64"))
    copy_tree(os.path.join(WIN_BIN, "game", "csgo", "bin", "win64"),
              os.path.join(SLIM_WIN, "game", "csgo", "bin", "win64"))
    copy_shared_content(SLIM_WIN)

    # V8 DLL 复制到 game/csgo/bin/win64 (Windows 用复制代替符号链接)
    v8_dlls = ["v8.dll", "v8system.dll", "v8_icui18n.dll", "v8_icuuc.dll",
               "v8_libbase.dll", "v8_libplatform.dll", "v8_zlib.dll"]
    for d in v8_dlls:
        copy_file(os.path.join(SLIM_WIN, "game", "bin", "win64", d),
                  os.path.join(SLIM_WIN, "game", "csgo", "bin", "win64", d))

    # steamclient 三件套 (来自 Steam 客户端更新包, 非 CS2 depot)
    for d in ["steamclient64.dll", "tier0_s64.dll", "vstdlib_s64.dll"]:
        copy_file(os.path.join(STEAMCLIENT_WIN_DIR, d),
                  os.path.join(SLIM_WIN, "game", "bin", "win64", d))
    copy_file(os.path.join(STEAMCLIENT_WIN_DIR, "steamclient64.dll"),
              os.path.join(SLIM_WIN, "steamclient64.dll"))

    _write_windows_scripts()


def _write_windows_scripts():
    bat = r"""@echo off
rem CS2 Windows 精简服务端 启动脚本 (de_dust2, -insecure)
cd /d "%~dp0"
game\bin\win64\cs2.exe -dedicated +map de_dust2 +hostname "SlimTest" -maxplayers 12 -ip 0.0.0.0 -port 27015 -insecure -condebug +game_type 0 +game_mode 0 +sv_pure 0 +sv_cheats 1
"""
    readme = """CS2 精简专用服务端 - Windows 版 (de_dust2)
===========================================

- 体积: 解压后约 1.9GB (原版 72.3GB)
- 单地图: de_dust2
- 运行模式: -insecure (无 VAC)

依赖
----
- Windows 10/11 或 Windows Server 2016+ (x64)
- 无需安装 Steam。本包已在 game\\bin\\win64\\ 内置:
    steamclient64.dll
    tier0_s64.dll
    vstdlib_s64.dll

启动
----
双击 start_server.bat, 或命令行:
    start_server.bat

日志: -condebug 会在 game\\csgo\\ 目录生成 console.log

验证启动
--------
- console.log 出现以下行即成功:
    [Server] SV:  12 player server started
    [Server] CSource2Server::GameServerSteamAPIActivated()
    [Networking] Network socket 'server' opened on port 27015

注意事项
--------
- 启动过程中的 "Failed loading resource ... (ERROR_FILEOPEN)" 是外观类物品
  (钥匙扣/纪念品/小鸡等) 的缺失警告, 属预期行为, 不影响服务器运行。
- 地图光照纹理 (lightmaps .vtex) 因排除规则未提取, 服务端会回退到错误纹理,
  不影响服务器逻辑。
- 若提示缺某 pak01_NNN.vpk, 需重新提取并补充对应编号包。
"""
    for path, content in [
        (os.path.join(SLIM_WIN, "start_server.bat"), bat),
        (os.path.join(SLIM_WIN, "README_WIN.txt"), readme),
    ]:
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(content)
        print(f"  wrote: {os.path.relpath(path, BASE)}")


def report(tree, name):
    total = 0
    nfiles = 0
    pak = []
    for root, _, files in os.walk(tree):
        for f in files:
            fp = os.path.join(root, f)
            total += os.path.getsize(fp)
            nfiles += 1
            if f.startswith("pak01_") and f.endswith(".vpk"):
                pak.append(os.path.relpath(fp, tree))
    print(f"{name}: {nfiles} files, {total/1024/1024/1024:.2f} GB, pak01 VPKs: {len(pak)}")
    return nfiles, total


def main():
    assemble_linux()
    assemble_windows()
    print()
    report(SLIM, "slim   (Linux)")
    report(SLIM_WIN, "slim-win (Windows)")
    print("REBUILD DONE")


if __name__ == "__main__":
    main()