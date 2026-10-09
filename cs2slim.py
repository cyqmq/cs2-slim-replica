#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
cs2slim - CS2 精简服务端 配置驱动 CLI（主仓库入口）

多仓库架构:
  - 本仓库 (cs2-slim)   : 核心配方 + 入口脚本 + 组件注册表
  - cs2-slim-maps       : 地图组件仓库 (filelist 片段 + 预构建包)
  - cs2-slim-features   : 功能组件仓库 (bots/gotv 等)

子命令:
  init      生成 slim.yaml 配置模板
  download  按配置组合 filelist 并调用 DepotDownloader 下载
  extract   提取 loose files
  build     组装精简树 (核心 + 选配地图)
  package   打包
  run       启动服务端

示例:
  python cs2slim.py init
  python cs2slim.py download --config slim.yaml
  python cs2slim.py download --platform win64 --maps de_dust2,de_mirage --features bots
  python cs2slim.py extract --config slim.yaml
  python cs2slim.py build  --config slim.yaml
  python cs2slim.py package --config slim.yaml --format zip
  python cs2slim.py run    --config slim.yaml

依赖: 仅 Python 3 标准库 (无需 PyYAML)。
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.error
import urllib.request
import zipfile

CLI_DIR = os.path.dirname(os.path.abspath(__file__))
CORE_DIR = os.path.join(CLI_DIR, "core")
SCRIPTS_DIR = os.path.join(CLI_DIR, "scripts")
REGISTRY_DIR = os.path.join(CLI_DIR, "registry")

PLATFORM_DEPOT = {
    "linux": ("2347773", "filelist_2347773.txt"),
    "win64": ("2347771", "filelist_2347771.txt"),
}
BIN_DIR = {
    "linux": "game/bin/linuxsteamrt64/cs2",
    "win64": "game/bin/win64/cs2.exe",
}


# ---------------------------------------------------------------------------
# 极简 YAML 子集解析（满足 slim.yaml 需求，零依赖）
# ---------------------------------------------------------------------------
def _strip_inline_comment(line):
    """去掉行尾 YAML 注释（` # ...`），引号内的 # 保留。"""
    in_single = in_double = False
    for i, ch in enumerate(line):
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif ch == "#" and not in_single and not in_double:
            # 注释需以空白或行首开头（避免误伤 hostname: "my#tag" 这类）
            if i == 0 or line[i - 1] in " \t":
                return line[:i].rstrip()
    return line.rstrip()


def parse_yaml_simple(text):
    """解析极简 YAML：顶层 `key: value`、`key:` + 缩进 `- item`、内联 `[a, b]`、
    以及段内嵌套 `key: value`（如 server 配置段）。支持行尾 ` # 注释`。"""
    data = {}
    section_key = None
    for raw in text.splitlines():
        line = _strip_inline_comment(raw)
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(" "))
        content = line.strip()
        if content.startswith("#"):
            continue
        if indent == 0 and ":" in content and not content.startswith("- "):
            key, _, val = content.partition(":")
            key = key.strip()
            val = val.strip()
            section_key = None
            if val == "":
                data[key] = []
                section_key = key
            elif val.startswith("[") and val.endswith("]"):
                data[key] = [v.strip().strip("'\"") for v in val[1:-1].split(",") if v.strip()]
            elif val.startswith("{") and val.endswith("}"):
                d = {}
                for part in val[1:-1].split(","):
                    if ":" in part:
                        k, _, v = part.partition(":")
                        d[k.strip().strip("'\"")] = v.strip().strip("'\"")
                data[key] = d
            else:
                data[key] = val.strip("'\"")
        elif indent > 0 and content.startswith("- "):
            if section_key is not None and isinstance(data.get(section_key), list):
                data[section_key].append(content[2:].strip().strip("'\""))
        elif indent > 0 and ":" in content and not content.startswith("- "):
            # 段内嵌套键值对（如 server 下的 hostname/maxplayers/port）
            if section_key is not None:
                k, _, v = content.partition(":")
                k = k.strip()
                v = v.strip()
                if isinstance(data.get(section_key), list) and not data[section_key]:
                    data[section_key] = {}
                if isinstance(data.get(section_key), dict):
                    data[section_key][k] = v.strip("'\"")
    return data


def load_config(path):
    if not os.path.exists(path):
        sys.exit(f"配置不存在: {path}")
    # utf-8-sig 自动去除 BOM (PowerShell Set-Content -Encoding UTF8 会写 BOM)
    text = open(path, encoding="utf-8-sig").read()
    if path.lower().endswith(".json"):
        return json.loads(text)
    return parse_yaml_simple(text)


# ---------------------------------------------------------------------------
# registry（组件注册表）
# ---------------------------------------------------------------------------
def load_registry(name, registry_base=None):
    """读取组件注册表 JSON。registry_base 为远程 raw URL 时优先远程。"""
    if registry_base:
        url = gh_proxy_url(registry_base.rstrip("/") + "/" + name)
        try:
            with urllib.request.urlopen(url, timeout=15) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception as e:
            print(f"  WARN: 远程注册表加载失败 {url}: {e}")
    local = os.path.join(REGISTRY_DIR, name)
    if os.path.exists(local):
        return json.load(open(local, encoding="utf-8"))
    sys.exit(f"找不到注册表: {name}")


def parse_csv(value):
    if isinstance(value, str):
        return [v.strip() for v in value.split(",") if v.strip()]
    return list(value or [])


def resolve_maps(cfg):
    maps = parse_csv(cfg.get("maps") or ["de_dust2"])
    if "de_dust2" not in maps:
        maps.insert(0, "de_dust2")  # 核心地图必含
    return maps


# ---------------------------------------------------------------------------
# filelist 组合器
# ---------------------------------------------------------------------------
def build_combined_filelist(core_filelist, cfg, registry_base=None):
    """核心 filelist + 地图组件片段 + 功能组件片段 => 合并行列表。"""
    with open(core_filelist, encoding="utf-8") as f:
        lines = [ln.rstrip("\n") for ln in f]

    # 核心行也纳入去重集合，避免地图/功能片段重复追加核心已含文件（如 de_dust2.vpk）
    added = set(lines)
    reg_maps = load_registry("maps.json", registry_base)
    for m in resolve_maps(cfg):
        meta = reg_maps.get("maps", {}).get(m)
        if not meta:
            print(f"  WARN: 未知地图组件 {m}，跳过")
            continue
        for path in meta.get("filelist", []):
            if path not in added:
                lines.append(path)
                added.add(path)
        print(f"  + 地图 {m}")

    reg_feat = load_registry("features.json", registry_base)
    for feat in parse_csv(cfg.get("features") or []):
        meta = reg_feat.get("features", {}).get(feat)
        if not meta:
            print(f"  WARN: 未知功能组件 {feat}，跳过")
            continue
        for path in meta.get("filelist", []):
            if path not in added:
                lines.append(path)
                added.add(path)
        print(f"  + 功能 {feat}")
    return lines


# ---------------------------------------------------------------------------
# 下载/解压工具
# ---------------------------------------------------------------------------
def gh_proxy_url(url):
    """若设置了 CS2_GH_PROXY（如 https://ghproxy.com），为 GitHub URL 加代理前缀。"""
    proxy = os.environ.get("CS2_GH_PROXY", "").strip().rstrip("/")
    if proxy and (url.startswith("https://github.com/")
                  or url.startswith("https://raw.githubusercontent.com/")):
        return f"{proxy}/{url}"
    return url


def download_file(url, dest, desc=""):
    """下载文件到 dest，带进度显示 + 断点续传。

    未完成部分保存在 dest.part；中断后再次运行会从断点继续（HTTP Range）。
    失败时保留 .part，不清理。
    """
    url = gh_proxy_url(url)
    print(f"下载 {desc or os.path.basename(dest)} ...")
    tmp = dest + ".part"
    resume = os.path.getsize(tmp) if os.path.exists(tmp) else 0
    if resume:
        print(f"  检测到未完成下载 ({resume/1024/1024:.1f} MB)，断点续传 ...")

    def open_conn():
        headers = {"Range": f"bytes={resume}-"} if resume else {}
        req = urllib.request.Request(url, headers=headers)
        try:
            return urllib.request.urlopen(req, timeout=60)
        except urllib.error.HTTPError as e:
            if e.code == 416 and resume:  # Range 不可满足: 重下
                os.remove(tmp)
                nonlocal_resume_zero()
                return urllib.request.urlopen(urllib.request.Request(url), timeout=60)
            raise

    def nonlocal_resume_zero():
        nonlocal resume
        resume = 0

    try:
        with open_conn() as r, open(tmp, "ab" if resume and r.status == 206 else "wb") as f:
            if r.status == 200:
                resume = 0
            total = int(r.headers.get("Content-Length") or 0) + resume
            done = resume
            while True:
                chunk = r.read(1024 * 1024)
                if not chunk:
                    break
                f.write(chunk)
                done += len(chunk)
                if total:
                    pct = done * 100 // max(total, 1)
                    print(f"\r  {pct}% ({done/1024/1024:.0f}/{total/1024/1024:.0f} MB)", end="", flush=True)
        print()
        os.replace(tmp, dest)
    except Exception as e:
        # 保留 .part 供断点续传
        sys.exit(f"下载失败 {url}: {e} (已保留 {tmp}，下次运行可断点续传)")


def _safe_join(dest, name):
    """防 zip-slip / path traversal：确保解压目标在 dest 内。"""
    dest_real = os.path.realpath(dest)
    target = os.path.realpath(os.path.join(dest_real, name))
    if target != dest_real and not target.startswith(dest_real + os.sep):
        raise ValueError(f"非法解压路径: {name}")
    return target


def extract_archive(path, dest):
    """解压 zip / tar.gz 到 dest（带 zip-slip 防护）。"""
    os.makedirs(dest, exist_ok=True)
    if path.endswith(".zip"):
        with zipfile.ZipFile(path) as z:
            for info in z.infolist():
                _safe_join(dest, info.filename)
            z.extractall(dest)
    else:
        with tarfile.open(path, "r:gz") as t:
            for m in t.getmembers():
                _safe_join(dest, m.name)
            t.extractall(dest)


def _make_zip(tree, out):
    """用 Python zipfile 生成标准 ZIP（Linux 无 bsdtar zip 支持时的可靠方案）。"""
    print(f"打包 {os.path.basename(tree)} -> {os.path.basename(out)} ...")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as z:
        for root, _, files in os.walk(tree):
            for fn in files:
                fp = os.path.join(root, fn)
                arc = os.path.relpath(fp, tree).replace(os.sep, "/")
                z.write(fp, arc)


STEAM_MANIFEST_URL = "https://client-update.akamai.steamstatic.com/steam_client_ubuntu12"


def _is_valid_elf64(path, min_size=0):
    """检查文件是否为有效的 64 位 ELF（用于验证 steamclient.so）。"""
    try:
        if os.path.getsize(path) < min_size:
            return False
        with open(path, "rb") as f:
            magic = f.read(4)
            cls = f.read(1)
        return magic == b"\x7fELF" and cls == b"\x02"
    except Exception:
        return False


def ensure_steamclient(tree, workdir):
    """确保精简树根目录有有效的 64 位 steamclient.so。

    若缺失/损坏，从 Steam 客户端更新清单（bins_sdk_ubuntu12.zip）重新获取。
    供 prebuilt 模式使用（source 模式由 get-cs2slim 脚本负责下载）。
    """
    dst = os.path.join(tree, "steamclient.so")
    if _is_valid_elf64(dst, 40_000_000):
        print("  steamclient.so 已存在且有效 (ELF 64-bit)")
        return

    print("  steamclient.so 缺失或无效，从 Steam SDK 包重新获取 ...")
    manifest_path = os.path.join(workdir, "steam_client_ubuntu12")
    download_file(STEAM_MANIFEST_URL, manifest_path, "Steam manifest")
    with open(manifest_path, encoding="utf-8", errors="replace") as f:
        content = f.read()
    m = re.search(r'"bins_sdk_ubuntu12\.zip\.([0-9a-f]+)"', content)
    if not m:
        sys.exit("无法在 Steam manifest 中找到 bins_sdk_ubuntu12")
    sdk_zip = os.path.join(workdir, "bins_sdk_ubuntu12.zip")
    download_file(f"https://steamcdn-a.akamaihd.net/client/bins_sdk_ubuntu12.zip.{m.group(1)}",
                  sdk_zip, "bins_sdk_ubuntu12")
    with zipfile.ZipFile(sdk_zip) as z:
        z.extract("linux64/steamclient.so", workdir)
    os.replace(os.path.join(workdir, "linux64", "steamclient.so"), dst)
    for p in (sdk_zip, manifest_path):
        if os.path.exists(p):
            os.remove(p)
    shutil.rmtree(os.path.join(workdir, "linux64"), ignore_errors=True)
    print("  steamclient.so 已更新")


CORE_PREBUILT = {
    "linux": {
        "name": "cs2-slim.tar.gz",
        "url": "https://github.com/cyqmq/cs2-slim-replica/releases/latest/download/cs2-slim.tar.gz",
        "tree": "slim",
    },
    "win64": {
        "name": "cs2-slim-win.zip",
        "url": "https://github.com/cyqmq/cs2-slim-replica/releases/latest/download/cs2-slim-win.zip",
        "tree": "slim-win",
    },
}


def _update_start_scripts(platform, tree):
    """用主仓库最新的启动脚本覆盖精简树内的启动脚本（含网络优化参数）。"""
    try:
        if platform == "linux":
            url = "https://raw.githubusercontent.com/cyqmq/cs2-slim-replica/main/core/deploy/linux/start_server.sh"
            dst = os.path.join(tree, "start_server.sh")
        else:
            url = "https://raw.githubusercontent.com/cyqmq/cs2-slim-replica/main/core/deploy/windows/start_server.bat"
            dst = os.path.join(tree, "start_server.bat")
        url = gh_proxy_url(url)
        tmp = dst + ".new"
        urllib.request.urlretrieve(url, tmp)
        os.replace(tmp, dst)
        print("  已更新启动脚本（含 VPN/TUN 网络优化参数）")
    except Exception as e:
        print(f"  WARN: 更新启动脚本失败: {e}")


def _patch_gameinfo_for_addon(tree, addon, label="Addon"):
    """在 game/csgo/gameinfo.gi 的 SearchPaths 中加入 Game <addon>。

    用于需要引擎优先加载自定义 GameDLL 的独立框架：
      - Metamod:Source  -> csgo/addons/metamod
      - SwiftlyS2        -> csgo/addons/swiftlys2
      - ModSharp        -> sharp
    """
    gi = os.path.join(tree, "game", "csgo", "gameinfo.gi")
    if not os.path.exists(gi):
        print(f"  WARN: 未找到 {gi}，无法自动打 {label} 补丁")
        return

    def _line_has_addon(ln):
        stripped = ln.lstrip()
        if not stripped.startswith("Game"):
            return False
        rest = stripped[4:].lstrip().split("//")[0].strip()
        return rest == addon

    with open(gi, encoding="utf-8", errors="replace") as f:
        lines = f.readlines()
    if any(_line_has_addon(ln) for ln in lines):
        print(f"  {label}: gameinfo.gi 已包含 {addon}，跳过补丁")
        return
    new_lines = []
    inserted = False
    for ln in lines:
        new_lines.append(ln)
        stripped = ln.lstrip()
        if stripped.startswith("Game_LowViolence"):
            indent = ln[: len(ln) - len(stripped)]
            new_lines.append(f"{indent}Game\t{addon}\n")
            inserted = True
    if not inserted:
        print(f"  WARN: gameinfo.gi 中未找到 Game_LowViolence 行，请手动添加 Game {addon}")
        return
    with open(gi, "w", encoding="utf-8", newline="") as f:
        f.writelines(new_lines)
    print(f"  {label}: 已在 gameinfo.gi 中添加 Game {addon}")


def _expand_feature_deps(features, reg_feat):
    """递归展开功能依赖（如 css -> metamod,metamod），依赖前置。"""
    expanded = []
    seen = set()

    def add(f):
        if f in seen:
            return
        seen.add(f)
        meta = reg_feat.get("features", {}).get(f)
        for dep in (meta or {}).get("requires") or []:
            add(dep)
        expanded.append(f)

    for f in features:
        add(f)
    return expanded


# ---------------------------------------------------------------------------
# 子命令实现
# ---------------------------------------------------------------------------
def cmd_init(args, cfg):
    src = os.path.join(CLI_DIR, "slim.yaml.example")
    dst = args.output
    if not dst.endswith((".yaml", ".yml", ".json")):
        dst = os.path.join(dst, "slim.yaml")
    os.makedirs(os.path.dirname(dst) or ".", exist_ok=True)
    if dst.lower().endswith(".json"):
        # 输出真正的 JSON 模板（load_config 对 .json 走 json.loads）
        template = {
            "platform": "win64",
            "maps": ["de_dust2"],
            "features": [],
            "workdir": "./cs2-build",
            "server": {
                "hostname": "SlimTest",
                "maxplayers": 12,
                "port": 27015,
                "insecure": True,
                "sv_pure": 0,
                "sv_cheats": 1,
            },
        }
        with open(dst, "w", encoding="utf-8") as f:
            json.dump(template, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print(f"配置模板已生成: {dst}")
    else:
        shutil.copy2(src, dst)
        print(f"配置模板已生成: {dst}")
    print("编辑后运行: python cs2slim.py download --config <path>")


def cmd_download(args, cfg):
    platform = cfg.get("platform") or args.platform or "win64"
    if platform not in PLATFORM_DEPOT:
        sys.exit(f"不支持的平台: {platform} (可选 linux/win64)")
    binary_depot, binary_filelist_name = PLATFORM_DEPOT[platform]

    workdir = os.path.abspath(cfg.get("workdir") or "./cs2-build")
    os.makedirs(workdir, exist_ok=True)

    core_shared = os.path.join(CORE_DIR, "filelists", "filelist_2347770.txt")
    core_binary = os.path.join(CORE_DIR, "filelists", binary_filelist_name)
    if not (os.path.exists(core_shared) and os.path.exists(core_binary)):
        sys.exit(f"核心 filelist 缺失: {core_shared} 或 {core_binary}")

    combined = build_combined_filelist(core_shared, cfg, cfg.get("registry_base"))
    combined_path = os.path.join(workdir, "filelist_2347770_combined.txt")
    with open(combined_path, "w", encoding="utf-8") as f:
        f.write("\n".join(combined) + "\n")
    print(f"组合 filelist: {combined_path} ({len(combined)} 行)")

    depot_tool = cfg.get("depot_tool") or args.depot_tool
    if depot_tool and not os.path.exists(depot_tool):
        sys.exit(f"depot_tool 不存在: {depot_tool}")
    jobs = [
        ("2347770", combined_path),
        (binary_depot, core_binary),
    ]
    if depot_tool:
        for depot, filelist in jobs:
            cmd = [depot_tool, "-app", "730", "-depot", depot,
                   "-dir", os.path.join(workdir, "depot", depot),
                   "-filelist", filelist]
            print(">>", " ".join(cmd))
            r = subprocess.run(cmd, cwd=workdir)
            if r.returncode != 0:
                sys.exit(f"DepotDownloader 失败 (exit {r.returncode})")
        print("下载完成。下一步: python cs2slim.py extract --config <path>")
    else:
        tool_name = "DepotDownloader" if platform == "linux" else "DepotDownloader.exe"
        print("未提供 depot_tool，请手动执行以下命令（或编辑 slim.yaml 设置 depot_tool）:")
        for depot, filelist in jobs:
            cmd = [tool_name, "-app", "730", "-depot", depot,
                   "-dir", os.path.join(workdir, "depot", depot),
                   "-filelist", filelist]
            print("  " + " ".join(cmd))


def cmd_extract(args, cfg):
    workdir = os.path.abspath(cfg.get("workdir") or "./cs2-build")
    depot = os.path.join(workdir, "depot", "2347770")
    for sub, out in [("game/csgo", os.path.join(workdir, "loose", "game", "csgo")),
                     ("game/core", os.path.join(workdir, "loose", "game", "core"))]:
        dirvpk = os.path.join(depot, sub, "pak01_dir.vpk")
        if not os.path.exists(dirvpk):
            sys.exit(f"缺少 {dirvpk}，请先 download")
        print(f"提取 {sub} ...")
        r = subprocess.run([sys.executable, os.path.join(SCRIPTS_DIR, "extract_vpk.py"),
                           "--dir-vpk", dirvpk,
                           "--archives-dir", os.path.dirname(dirvpk),
                           "--output", out])
        if r.returncode != 0:
            sys.exit(f"提取失败: {sub}")
    print("提取完成。下一步: python cs2slim.py build --config <path>")


def cmd_build(args, cfg):
    workdir = os.path.abspath(cfg.get("workdir") or "./cs2-build")
    platform = cfg.get("platform") or "win64"
    maps = resolve_maps(cfg)
    extra = [m for m in maps if m != "de_dust2"]

    # 前置检查：depot 缺失时给出友好提示，而不是 Python traceback
    depot_shared = os.path.join(workdir, "depot", "2347770")
    depot_bin = os.path.join(workdir, "depot", PLATFORM_DEPOT[platform][0])
    missing = [d for d in (depot_shared, depot_bin) if not os.path.isdir(d)]
    if missing:
        sys.exit(
            "缺少 depot 目录:\n  " + "\n  ".join(missing)
            + "\n请先运行: python cs2slim.py download --config <path>"
        )

    print(f"组装平台 {platform}，地图: {maps}，额外: {extra or '无'}")
    r = subprocess.run([sys.executable, os.path.join(SCRIPTS_DIR, "rebuild_slim.py"),
                     "--base-dir", workdir,
                     "--maps", ",".join(extra),
                     "--platforms", platform])
    if r.returncode != 0:
        sys.exit("组装失败")
    # source 模式生成的启动脚本是旧版，用主仓库最新脚本覆盖（含菜单/端口/link-manager 支持）
    tree = os.path.join(workdir, "slim-win" if platform == "win64" else "slim")
    _update_start_scripts(platform, tree)
    print("组装完成。下一步: python cs2slim.py package --config <path> 或 run 启动")


def cmd_package(args, cfg):
    platform = cfg.get("platform") or "win64"
    workdir = os.path.abspath(cfg.get("workdir") or "./cs2-build")
    tree = os.path.join(workdir, "slim-win" if platform == "win64" else "slim")
    if not os.path.exists(tree):
        sys.exit(f"精简树不存在: {tree}，请先 build")
    # 完整性检查：核心二进制存在才允许打包（避免打包空/残缺树）
    bin_rel = BIN_DIR[platform]
    if not os.path.exists(os.path.join(tree, bin_rel)):
        sys.exit(f"精简树不完整（缺少 {bin_rel}），请重新 build")

    fmt = args.format
    ext = "zip" if fmt == "zip" else "tar.gz"
    out = os.path.join(workdir, f"cs2-slim-{platform}.{ext}")
    if os.path.exists(out):
        os.remove(out)
    if fmt == "zip":
        # 用 Python zipfile 生成标准 ZIP（Linux 的 GNU tar -a 对 .zip 会产出无效文件）
        _make_zip(tree, out)
        print(f"打包完成: {out} ({os.path.getsize(out)/1024/1024/1024:.2f} GB)")
        return
    # Linux tar.gz 需保留 shell 脚本可执行位。
    # Windows 自带 bsdtar 会把 .sh 记成 666（丢失执行位），部署后 ./setup.sh 会 Permission denied；
    # 因此优先用 Git Bash GNU tar（记录 MSYS chmod 的 755），Linux 上直接使用系统 GNU tar。
    git_bash = r"C:\Program Files\Git\bin\bash.exe"
    if os.path.exists(git_bash):
        # Git Bash 的 tar 会把 `C:/...` 当作远程主机，必须用相对路径（subprocess 已设 cwd=workdir）
        cmd = [git_bash, "-c", f"tar -czf '{os.path.basename(out)}' -C '{os.path.basename(tree)}' ."]
    else:
        cmd = ["tar", "-czf", out, "-C", tree, "."]
    print(">>", " ".join(cmd))
    r = subprocess.run(cmd, cwd=workdir)
    if r.returncode != 0:
        sys.exit("打包失败")
    print(f"打包完成: {out} ({os.path.getsize(out)/1024/1024/1024:.2f} GB)")


def cmd_run(args, cfg):
    platform = cfg.get("platform") or "win64"
    workdir = os.path.abspath(cfg.get("workdir") or "./cs2-build")
    # build 实际输出在 <workdir>/slim 或 <workdir>/slim-win 下
    tree = os.path.join(workdir, "slim-win" if platform == "win64" else "slim")
    exe = os.path.join(tree, BIN_DIR[platform])
    if not os.path.exists(exe):
        sys.exit(f"可执行文件不存在: {exe}，请先 build")
    srv = cfg.get("server") or {}
    # 端口优先级与启动脚本一致: SERVER_PORT > CS2_PORT > 配置 > 27015
    port = (os.environ.get("SERVER_PORT")
            or os.environ.get("CS2_PORT")
            or srv.get("port")
            or 27015)
    params = [
        exe, "-dedicated", "+map", args.map,
        "+hostname", srv.get("hostname") or "SlimTest",
        "-maxplayers", str(srv.get("maxplayers") or 12),
        "-port", str(port),
        "-insecure", "-condebug", "+game_type", "0", "+game_mode", "0",
        "+sv_pure", str(srv.get("sv_pure") or 0),
        "+sv_cheats", str(srv.get("sv_cheats") or 1),
        "+sv_maxrate", "0", "+sv_minrate", "100000",
        "+sv_maxupdaterate", "128", "+sv_maxcmdrate", "128",
        "+net_maxroutable", "1200",
    ]
    # ---------- 网络模式 ----------
    # CS2_NET_MODE: 1(局域网) | 2(局域网+绑定0.0.0.0, 默认) | 3(公开, 需 GSLT)
    #  1 = +sv_lan 1（不绑 -ip）；2 = +sv_lan 1 -ip 0.0.0.0；
    #  3 = +sv_lan 0 + GSLT(+sv_setsteamaccount)，无 GSLT 回退档2。
    #      警告: 本精简服务端非认证/可能违规，公开绑定 GSLT 可能导致该账号被 GSLT 服务封禁。
    # GSLT 来源优先: CS2_GSLT > GSLT > CS2LM_GSLT
    net_mode = os.environ.get("CS2_NET_MODE", "2")
    if net_mode == "1":
        sv_lan, bind_ip, net_args = 1, [], []
    elif net_mode == "3":
        gslt = (os.environ.get("CS2_GSLT")
                or os.environ.get("GSLT")
                or os.environ.get("CS2LM_GSLT"))
        if gslt:
            sv_lan, bind_ip, net_args = 0, [], ["+sv_setsteamaccount", gslt]
        else:
            print(">> WARN: CS2_NET_MODE=3 无 GSLT（CS2_GSLT/GSLT/CS2LM_GSLT），回退档2")
            sv_lan, bind_ip, net_args = 1, ["-ip", "0.0.0.0"], []
    else:
        if net_mode != "2":
            print(f">> WARN: 未知 CS2_NET_MODE='{net_mode}'，回退档2")
        sv_lan, bind_ip, net_args = 1, ["-ip", "0.0.0.0"], []
    # -ip 插到 -port 前；+sv_lan 插到 +sv_maxrate 前；net_args 追加末尾
    if bind_ip:
        pi = params.index("-port")
        params[pi:pi] = bind_ip
    params[params.index("+sv_maxrate") : params.index("+sv_maxrate")] = ["+sv_lan", str(sv_lan)]
    params += net_args
    print(">>", " ".join(params))
    print(f"服务端启动中 (工作目录 {workdir})。日志: game/csgo/console.log")
    if platform == "win64":
        subprocess.run(params, cwd=workdir)
    else:
        os.execv(exe, params)


# ---------------------------------------------------------------------------
# 一键全流程: download + extract + build (+package)
# ---------------------------------------------------------------------------
def cmd_all(args, cfg):
    if not (cfg.get("depot_tool") or args.depot_tool):
        sys.exit("一键模式需要 depot_tool（slim.yaml 设置 或 --depot-tool 指定）")
    print("=" * 60)
    print(">>> [1/4] 下载 depot（按配置组合 filelist）")
    cmd_download(args, cfg)
    print("=" * 60)
    print(">>> [2/4] 提取 loose files")
    cmd_extract(args, cfg)
    print("=" * 60)
    print(">>> [3/4] 组装精简树")
    cmd_build(args, cfg)
    if getattr(args, "package", False):
        print("=" * 60)
        print(">>> [4/4] 打包")
        cmd_package(args, cfg)
    else:
        print("=" * 60)
        platform = cfg.get("platform") or "win64"
        print("一键完成! 精简树已就绪:")
        if platform == "linux":
            print("  启动: bash <workdir>/slim/start_server.sh")
        else:
            print("  启动: <workdir>/slim-win/start_server.bat")
        print("  打包: python cs2slim.py package --config <path> --format zip")


# ---------------------------------------------------------------------------
# 预构建模式: 直接拉取 GitHub Release 包并自动拼装
# ---------------------------------------------------------------------------
def cmd_prebuilt(args, cfg):
    platform = cfg.get("platform") or "win64"
    if platform not in CORE_PREBUILT:
        sys.exit(f"不支持的平台: {platform} (可选 linux/win64)")
    workdir = os.path.abspath(cfg.get("workdir") or "./cs2-build")
    os.makedirs(workdir, exist_ok=True)

    core = CORE_PREBUILT[platform]
    tree = os.path.join(workdir, core["tree"])

    if args.dry_run:
        print("[dry-run] 预构建模式计划:")
        print(f"  核心包: {core['url']}")
        print(f"  解压到: {tree}")
        reg_maps = load_registry("maps.json", cfg.get("registry_base"))
        for m in resolve_maps(cfg):
            if m == "de_dust2":
                continue
            meta = reg_maps.get("maps", {}).get(m)
            if meta is None:
                print(f"  WARN: 未知地图组件 {m}，跳过")
                continue
            url = meta.get("prebuilt_url") or ""
            print(f"  地图 {m}: {url or '（暂无预构建包）'}")
        reg_feat = load_registry("features.json", cfg.get("registry_base"))
        features = _expand_feature_deps(parse_csv(cfg.get("features") or []), reg_feat)
        for f in features:
            meta = reg_feat.get("features", {}).get(f)
            if meta is None:
                print(f"  WARN: 未知功能组件 {f}，跳过")
                continue
            url = meta.get("prebuilt_url") or ""
            print(f"  功能 {f}: {url or '（暂无预构建包）'}")
        return

    # 1. 核心包
    core_path = os.path.join(workdir, core["name"])
    if not os.path.exists(core_path):
        download_file(core["url"], core_path, f"核心精简包 {core['name']}")

    # 2. 解压核心包
    if os.path.exists(tree):
        shutil.rmtree(tree)
    os.makedirs(tree, exist_ok=True)
    print(f"解压核心包到 {tree} ...")
    extract_archive(core_path, tree)
    # 确保 steamclient.so 有效（缺失/损坏时自动从 Steam SDK 包补下）
    if platform == "linux":
        ensure_steamclient(tree, workdir)
    _update_start_scripts(platform, tree)
    # 修复执行权限（面板场景默认只给 start.sh 权限）
    if platform == "linux":
        cs2_bin = os.path.join(tree, "game", "bin", "linuxsteamrt64", "cs2")
        if os.path.exists(cs2_bin):
            os.chmod(cs2_bin, 0o755)
        start_sh = os.path.join(tree, "start_server.sh")
        if os.path.exists(start_sh):
            os.chmod(start_sh, 0o755)

    # 3. 地图组件
    maps = resolve_maps(cfg)
    reg_maps = load_registry("maps.json", cfg.get("registry_base"))
    for m in maps:
        if m == "de_dust2":
            continue
        meta = reg_maps.get("maps", {}).get(m)
        if meta is None:
            print(f"  WARN: 未知地图组件 {m}，跳过")
            continue
        url = meta.get("prebuilt_url") or ""
        if not url:
            print(f"  WARN: 地图 {m} 暂无预构建包（可用 source 模式: cs2slim.py all），跳过")
            continue
        mzip = os.path.join(workdir, f"{m}.zip")
        if not os.path.exists(mzip):
            download_file(url, mzip, f"地图 {m}")
        print(f"  拼装地图 {m} ...")
        extract_archive(mzip, tree)

    # 4. 功能组件
    features = parse_csv(cfg.get("features") or [])
    reg_feat = load_registry("features.json", cfg.get("registry_base"))
    features = _expand_feature_deps(features, reg_feat)
    for f in features:
        meta = reg_feat.get("features", {}).get(f)
        if meta is None:
            print(f"  WARN: 未知功能组件 {f}，跳过")
            continue
        url = meta.get("prebuilt_url") or ""
        if not url:
            print(f"  WARN: 功能 {f} 暂无预构建包，跳过")
            continue
        fzip = os.path.join(workdir, f"{f}-pack.zip")
        if not os.path.exists(fzip):
            download_file(url, fzip, f"功能 {f}")
        print(f"  拼装功能 {f} ...")
        extract_archive(fzip, tree)
    # 功能后置补丁（独立框架需要修改 gameinfo.gi 加载自定义 GameDLL）
    if any(f in ("metamod", "metamod-win") for f in features):
        _patch_gameinfo_for_addon(tree, "csgo/addons/metamod", "Metamod")
    if any(f in ("swiftly", "swiftly-win") for f in features):
        _patch_gameinfo_for_addon(tree, "csgo/addons/swiftlys2", "SwiftlyS2")
    if any(f in ("modsharp", "modsharp-win") for f in features):
        _patch_gameinfo_for_addon(tree, "sharp", "ModSharp")

    # 5. 报告
    print()
    print("预构建模式完成!")
    if platform == "linux":
        print(f"  启动: bash {tree}/start_server.sh")
    else:
        print(f"  启动: {tree}/start_server.bat")
    print(f"  提示: 地图/功能包已缓存到 {workdir}，重复执行可复用。")


# ---------------------------------------------------------------------------
# 主入口
# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="cs2slim - CS2 精简服务端配置驱动 CLI")
    ap.add_argument("--config", help="配置文件 (slim.yaml / slim.json)")
    ap.add_argument("--platform", choices=["linux", "win64"], help="目标平台")
    ap.add_argument("--maps", help="地图列表, 逗号分隔, 如 de_dust2,de_mirage")
    ap.add_argument("--features", help="功能列表, 逗号分隔, 如 bots")
    ap.add_argument("--depot-tool", help="DepotDownloader 可执行文件路径")
    sub = ap.add_subparsers(dest="command", required=True)

    # 通用选项（同时挂在顶层和每个子命令，便于 `cs2slim.py download --config slim.yaml`）
    def add_common(p):
        p.add_argument("--config", help="配置文件 (slim.yaml / slim.json)")
        p.add_argument("--platform", choices=["linux", "win64"], help="目标平台")
        p.add_argument("--maps", help="地图列表, 逗号分隔, 如 de_dust2,de_mirage")
        p.add_argument("--features", help="功能列表, 逗号分隔, 如 bots")
        p.add_argument("--depot-tool", help="DepotDownloader 可执行文件路径")

    p_init = sub.add_parser("init", help="生成配置模板")
    p_init.add_argument("--output", default=".", help="输出目录或文件路径")
    add_common(p_init)
    p_init.set_defaults(func=cmd_init)

    p_dl = sub.add_parser("download", help="按配置下载 depot")
    add_common(p_dl)
    p_dl.set_defaults(func=cmd_download)

    p_ex = sub.add_parser("extract", help="提取 loose files")
    add_common(p_ex)
    p_ex.set_defaults(func=cmd_extract)

    p_bd = sub.add_parser("build", help="组装精简树")
    add_common(p_bd)
    p_bd.set_defaults(func=cmd_build)

    p_pk = sub.add_parser("package", help="打包")
    p_pk.add_argument("--format", choices=["zip", "tar.gz"], default="tar.gz")
    add_common(p_pk)
    p_pk.set_defaults(func=cmd_package)

    p_run = sub.add_parser("run", help="启动服务端")
    p_run.add_argument("--map", default="de_dust2")
    add_common(p_run)
    p_run.set_defaults(func=cmd_run)

    p_all = sub.add_parser("all", help="一键全流程: download + extract + build (+package)")
    p_all.add_argument("--package", action="store_true", help="完成后打包")
    p_all.add_argument("--format", choices=["zip", "tar.gz"], default="tar.gz")
    add_common(p_all)
    p_all.set_defaults(func=cmd_all)

    p_pb = sub.add_parser("prebuilt", help="预构建模式: 直接拉取 Release 包自动拼装")
    p_pb.add_argument("--dry-run", action="store_true", help="只打印下载计划, 不下载")
    add_common(p_pb)
    p_pb.set_defaults(func=cmd_prebuilt)

    args = ap.parse_args()

    # 配置驱动：--config 优先，命令行参数覆盖/补充
    # 子命令上的 --config 覆盖顶层 --config（顶层在前、子命令在后）
    cfg = {}
    config_path = getattr(args, "config", None)
    if config_path:
        cfg = load_config(config_path)
    if getattr(args, "platform", None):
        cfg["platform"] = args.platform
    if getattr(args, "maps", None):
        cfg["maps"] = args.maps
    if getattr(args, "features", None):
        cfg["features"] = args.features

    args.func(args, cfg)


if __name__ == "__main__":
    main()