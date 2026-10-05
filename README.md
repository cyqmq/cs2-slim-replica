# CS2 精简专用服务端 · 复刻配方

将原版约 72.3GB 的 CS2 专用服务器精简到 **~1.7GB（Linux）/~1.9GB（Windows）**，单地图 de_dust2 实测可用。

本仓库只包含"配方"（指南 + filelist + 脚本 + 部署模板），**不包含构建产物**（压缩包过大，按指南自行复刻）。

## 内容

- `CS2_SLIM_GUIDE.md` — 完整复刻指南（含 Linux 与 Windows 双平台适配）
- `filelists/` — DepotDownloader 精准下载清单
  - `filelist_2347770.txt` — 共享内容（77 个 csgo 编号包 + core + de_dust2 + prefabs）
  - `filelist_2347773.txt` — Linux 服务端二进制
  - `filelist_2347771.txt` — Windows 服务端二进制
- `scripts/extract_vpk.py` — VPK v2 分层树解析 + loose files 提取
- `scripts/download_chunks.py` — Steam CDN 限速时的 1MB Range 分块下载器
- `deploy/linux/` — Linux 部署/启动脚本（setup.sh + start_server.sh）
- `deploy/windows/` — Windows 启动脚本 + 部署说明

## 快速开始 (Linux)

1. 用 `filelists/filelist_2347770.txt` + `filelists/filelist_2347773.txt` 跑 DepotDownloader 下载两个 depot。
2. `python scripts/extract_vpk.py` 提取 loose files（详见指南第六节）。
3. 按指南第七节组装精简树（移走 `pak01_*.vpk`，保留 `de_dust2.vpk` + prefabs）。
4. 上传到 Linux，运行 `deploy/linux/setup.sh`，再 `deploy/linux/start_server.sh`。

## 快速开始 (Windows)

见指南第十三节：

- 二进制 depot 用 **2347771**。
- 从 Steam 客户端更新包 `bins_win32.zip` 提取 `steamclient64.dll`、`tier0_s64.dll`、`vstdlib_s64.dll`，放入 `game\bin\win64\`。
- V8 DLL 用**复制**而不是符号链接。
- 双击 `deploy/windows/start_server.bat` 启动。

## 实测记录

- 2026-10-06 Linux：精简树 1.69GB / 20,343 文件，包 `cs2-slim.tar.gz` 1.11GB，本地校验（CRC + ELF 依赖）全通过。
- 2026-10-06 Windows（Windows Server 2022 真实运行）：精简树 1.92GB / 20,408 文件，包 `cs2-slim-win.zip` 1.24GB；
  实测日志达到指南"最终验证"全部标准：
  ```
  [Server] SV:  12 player server started
  [Server] CSource2Server::GameServerSteamAPIActivated()
  [Networking] Network socket 'server' opened on port 27015
  ```

## 版本注意

方法跨版本稳定（VPK 格式 / loose-files 优先级 / 内容分类均稳定）；但 **filelist 是版本绑定数据**。
CS2 更新后若启动报缺某 `pak01_NNN.vpk`，按指南 5.2 节"迭代补充"即可。