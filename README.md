# CS2 精简专用服务端 · 复刻配方（主仓库）

将原版约 72.3GB 的 CS2 专用服务器精简到 **~1.7GB（Linux）/~1.9GB（Windows）**，单地图 de_dust2 实测可用。

本仓库是**多仓库架构的主仓库**：包含核心配方（指南 + filelist + 脚本 + 部署模板）和配置驱动的入口脚本 `cs2slim.py`。**不包含构建产物**（压缩包过大，按配方自行复刻或下载 GitHub Release 预构建包）。

## 多仓库架构

| 仓库 | 角色 |
|------|------|
| [cs2-slim-replica](https://github.com/cyqmq/cs2-slim-replica)（本仓库） | 主仓库：核心配方 + 入口脚本 + 组件注册表 |
| [cs2-slim-maps](https://github.com/cyqmq/cs2-slim-maps) | 地图组件（de_mirage / de_inferno / … 选配） |
| [cs2-slim-features](https://github.com/cyqmq/cs2-slim-features) | 功能组件（bots 人机等选配） |

```
主仓库 (cs2-slim-replica)
├── cs2slim.py          # 配置/参数驱动的入口 CLI
├── core/               # 核心配方
│   ├── CS2_SLIM_GUIDE.md
│   ├── filelists/      # 三个 depot 的核心下载清单
│   └── deploy/         # linux/windows 启动脚本
├── registry/           # 组件注册表 (maps.json / features.json)
└── scripts/           # 提取/下载/组装脚本
```

## 内容

- `cs2slim.py` — 配置驱动的入口 CLI（子命令：init / download / extract / build / package / run）
- `core/CS2_SLIM_GUIDE.md` — 完整复刻指南（含 Linux 与 Windows 双平台适配）
- `core/filelists/` — DepotDownloader 精准下载清单
  - `filelist_2347770.txt` — 共享内容（csgo 编号包 + core + de_dust2 + prefabs）
  - `filelist_2347773.txt` — Linux 服务端二进制
  - `filelist_2347771.txt` — Windows 服务端二进制
- `scripts/extract_vpk.py` — VPK v2 分层树解析 + loose files 提取
- `scripts/download_chunks.py` — Steam CDN 限速时的 1MB Range 分块下载器
- `scripts/rebuild_slim.py` — 一键组装双平台精简树（支持 `--base-dir` / `--maps`）

## 快速开始（CLI 方式，推荐）

### 1. 生成配置

```bash
python cs2slim.py init
```

编辑生成的 `slim.yaml`：

```yaml
platform: win64            # linux | win64
maps:
  - de_dust2
  - de_mirage             # 选配地图（来自 cs2-slim-maps）
features:
  - bots                  # 选配功能（来自 cs2-slim-features）
workdir: ./cs2-build
```

### 2. 下载 / 提取 / 组装 / 打包

```bash
python cs2slim.py download --config slim.yaml   # 按配置组合 filelist 并调用 DepotDownloader
python cs2slim.py extract  --config slim.yaml   # 提取 loose files
python cs2slim.py build    --config slim.yaml    # 组装精简树（含选配地图）
python cs2slim.py package   --config slim.yaml --format zip
```

### 3. 纯命令行参数（不用配置文件）

```bash
python cs2slim.py download --platform linux --maps de_dust2,de_mirage --features bots
```

## 快速开始（传统方式）

1. 用 `core/filelists/filelist_2347770.txt` + 平台对应二进制清单跑 DepotDownloader 下载 depot。
2. `python scripts/extract_vpk.py` 提取 loose files（详见指南第六节）。
3. 按指南第七节组装精简树（移走 `pak01_*.vpk`，保留 `de_dust2.vpk` + prefabs）。
4. Linux：上传到 Linux，运行 `core/deploy/linux/setup.sh`，再 `core/deploy/linux/start_server.sh`。
5. Windows：见指南第十三节，双击 `core/deploy/windows/start_server.bat` 启动。

## 选配组件用法

- 地图：`slim.yaml` 的 `maps` 列表加 `de_mirage`、`de_inferno` 等，主脚本自动把对应 `filelist.txt` 片段合并进下载清单。
- 人机：`features` 列表加 `bots`，构建后把 `game/csgo/cfg/server_bot.cfg` 部署到服务端（见 cs2-slim-features 仓库）。

## 实测记录

- 2026-10-06 初版：Linux 精简树 1.69GB / 20,343 文件；Windows 精简树 1.92GB / 20,408 文件，Windows Server 2022 真实启动通过。
- 2026-10-06 随 CS2 更新重建（v1.1.0）：
  - 新 manifest：2347770 = 7820179980365915207 / 2347773 = 8082014506965878039 / 2347771 = 459013114122940128（均 10/05/2026）
  - 提取：csgo 19,187 文件 / 514.4MB，core 878 文件 / 36.6MB
  - Linux 精简树 1.67GB / 20,210 文件；Windows 精简树 1.90GB / 20,261 文件
  - Windows 实测启动成功，`GC Connection established for server version 2000927`
  - filelist 无需改动，DepotDownloader 增量更新自动处理编号包增删（如 pak01_505 被移除）
  - 实测日志达到指南"最终验证"全部标准：
  ```
  [Server] SV:  12 player server started
  [Server] CSource2Server::GameServerSteamAPIActivated()
  [Networking] Network socket 'server' opened on port 27015
  ```

## 版本注意

方法跨版本稳定（VPK 格式 / loose-files 优先级 / 内容分类均稳定）；但 **filelist 是版本绑定数据**。
CS2 更新后若启动报缺某 `pak01_NNN.vpk`，按指南 5.2 节"迭代补充"即可。