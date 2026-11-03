# CS2 精简专用服务端（主仓库）

将原版约 **72.3GB** 的 CS2 专用服务器精简到 **~1.7GB（Linux）/ ~1.9GB（Windows）**（解压后，单地图 de_dust2 实测可用；体积随 CS2 更新略有浮动，最新实测见 `DEVELOP.md`）。

本仓库是**纯自动构建仓库**（CS2 精简服务端构建管线）：配方（`core/filelists`）、组件目录（`registry/`，含预构建版本）、启动脚本（`core/deploy`）、GitHub Actions（检测 CS2 更新 + 重建 + 发布 Release）。**CLI 与一键安装脚本已迁移到 [cs2slim-cli](https://github.com/cyqmq/cs2slim-cli)**，本仓库不再包含 `cs2slim.py` / `get-cs2slim.sh`。

## 一键安装

> 💡 不想手写命令？**在线生成一键安装指令**：<https://cyqmq.github.io/cs2-slim-scripts/>（选择地图/功能/模式，自动生成 Linux / Windows 命令）

### Linux (curl | bash)

> ⚠️ **重要**：管道右侧的 `bash` 收不到 `VAR=值 curl ... | bash` 里的变量（变量只传给 `curl`）。请**先用 `export`**。

```bash
# 默认: de_dust2 精简服务端（source 模式，首次约 1.5GB 下载）
curl -fsSL https://raw.githubusercontent.com/cyqmq/cs2slim-cli/main/scripts/get-cs2slim.sh | bash

# 更快: 预构建模式（直接拉 Release 包拼装，核心包约 1.1GB）
export CS2_MODE=prebuilt CS2_MAPS=de_dust2,de_mirage CS2_FEATURES=bots
curl -fsSL https://raw.githubusercontent.com/cyqmq/cs2slim-cli/main/scripts/get-cs2slim.sh | bash

# 国内网络受限: 加 GitHub 加速代理
export CS2_GH_PROXY=https://ghproxy.com CS2_MODE=prebuilt
curl -fsSL https://raw.githubusercontent.com/cyqmq/cs2slim-cli/main/scripts/get-cs2slim.sh | bash

# 面板模式（简幻欢 / Pterodactyl）: 自动生成 $HOME/start.sh（首次启动会自动安装）
export CS2_MODE=prebuilt CS2_PANEL=1
curl -fsSL https://raw.githubusercontent.com/cyqmq/cs2slim-cli/main/scripts/get-cs2slim.sh | bash
```

### Windows (irm | iex)

```powershell
# 默认: de_dust2 精简服务端（source 模式）
irm https://raw.githubusercontent.com/cyqmq/cs2slim-cli/main/scripts/get-cs2slim.ps1 | iex

# 更快: 预构建模式（选配地图 + 人机）
$env:CS2_MODE='prebuilt'; $env:CS2_MAPS='de_dust2,de_mirage'; $env:CS2_FEATURES='bots'
irm https://raw.githubusercontent.com/cyqmq/cs2slim-cli/main/scripts/get-cs2slim.ps1 | iex
```

### 环境变量

| 变量 | 说明 | 默认 |
|------|------|------|
| `CS2_MODE` | `source`（从 depot 构建）或 `prebuilt`（拉取 Release 包拼装） | source |
| `CS2_MAPS` | 逗号分隔地图（如 `de_dust2,de_mirage`） | de_dust2 |
| `CS2_FEATURES` | 逗号分隔功能（如 `bots`） | (空) |
| `CS2_WORKDIR` | 工作目录 | `~/cs2-slim-build` |
| `CS2_PACKAGE` | 1=完成后打包（仅 source 模式） | 0 |
| `CS2_DRY_RUN` | 1=只生成配置/预览下载计划，不下载内容包（仍会获取主仓库脚本供面板模板回退；`CS2_PANEL=1` 时会生成 `start.sh` 预览） | 0 |
| `CS2_GH_PROXY` | GitHub 加速代理前缀（如 `https://ghproxy.com`） | (空) |
| `CS2_PANEL` | 1=面板模式：生成/覆盖 `$HOME/start.sh`（dry-run 也生成预览） | 0 |

> 📄 完整环境变量说明（含运行/启动变量：`SERVER_PORT`、`CS2_PORT`、`CS2_NET_MODE`、`CS2_GSLT`、`CS2_PASSWORD`、`CS2LM_WEB`、`CS2LM_WEB_TOKEN` 等，含端口优先级与示例）见 **[`VARIABLES.md`](VARIABLES.md)**。

## 启动服务端

```bash
# 普通模式（首次交互启动会弹出一次性菜单，15 秒无输入默认完整启动）
bash ~/cs2-slim-build/slim/start_server.sh

# 面板模式（面板启动命令填: bash start.sh；首次启动会自动安装）
bash ~/start.sh
```

**一次性菜单**：选择后 CS2 前台运行，日志正常显示；菜单不会反复出现。再次打开菜单用 `bash start_server.sh menu`（面板场景可在 `start.sh` 顶部加 `export CS2LM_MENU=1`，或在面板环境变量配置 `CS2LM_MENU=1`）。跳过菜单用 `bash start_server.sh auto` 或 `CS2LM_AUTO=1`（面板自动重启推荐）。

**子命令**：`menu`（显示菜单）/ `auto`（跳过菜单完整启动）/ `web`（只启动插件管理 Web）/ `token`（查看 token）/ `webstop`（停止 Web）。

首次启动会自动链接 `steamclient.so` 到 `~/.steam/sdk64/` 并创建 V8 符号链接；若出现 `Failed to load module '...steamclient.so'`，重跑一键脚本（prebuilt 会自动校验/补下）或参考指南 7.1 节诊断。

## 自动检测 CS2 更新与重建

本仓库内置 GitHub Actions 自动检测与重建工作流（**无需配置任何 secret**）：

- **Detect CS2 Update**：每 4 小时运行一次，用 SteamCMD 获取 CS2 最新 buildid，
  与 `state/buildid.json` 对比；检测到更新时自动提交状态并触发重建。
- **Rebuild Slim Packages**：检测到更新后自动执行：
  1. 在本仓库创建新版本 Release（版本号自动递增，如 v1.3.0）；
  2. 并行重建 Linux（`cs2-slim.tar.gz`）与 Windows（`cs2-slim-win.zip`）核心包；
  3. 上传资产并标记为 Latest。

工作流文件：`.github/workflows/detect-cs2-update.yml`、`.github/workflows/rebuild-slim.yml`
辅助脚本位于 `scripts/updater/`（buildid 解析 / 工具下载 / 磁盘清理）。

首次运行只记录 buildid 不触发重建；之后每次 CS2 更新都会自动发布新版核心包。

## 相关仓库

| 仓库 | 角色 |
|------|------|
| [cs2-slim-replica](https://github.com/cyqmq/cs2-slim-replica)（本仓库） | 构建仓库：配方 + 组件目录 + 自动构建管线（发布精简包） |
| [cs2slim-cli](https://github.com/cyqmq/cs2slim-cli) | 用户侧工具：CLI + 一键安装脚本（含版本自检 / upgrade） |
| [cs2-slim-maps](https://github.com/cyqmq/cs2-slim-maps) | 选配地图（de_mirage / de_inferno / …） |
| [cs2-slim-features](https://github.com/cyqmq/cs2-slim-features) | 选配功能（bots 人机 / Metamod / CounterStrikeSharp / Swiftly / Plugify / ModSharp 等） |

## 更多文档

- **纯手动复刻指南**（不依赖本仓库脚本，仅用 DepotDownloader + Source2Viewer-CLI 从 depot 手动拼装，Linux）: [`core/CS2_SLIM_GUIDE.md`](core/CS2_SLIM_GUIDE.md)
- **精简树结构全解析**（目录结构图、制作工具、精简原理与必须项）: [`core/CS2_SLIM_TREE_GUIDE.md`](core/CS2_SLIM_TREE_GUIDE.md)
- **地图复刻指南**（手动添加竞技地图：下载地图 VPK + prefabs、放入精简树、启动与踩坑）: [`core/CS2_SLIM_MAPS_GUIDE.md`](core/CS2_SLIM_MAPS_GUIDE.md)
- **开发 / CLI / 架构文档**（CLI 子命令、配置驱动、仓库结构、实测记录）: [`DEVELOP.md`](DEVELOP.md)