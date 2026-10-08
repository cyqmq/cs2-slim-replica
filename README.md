# CS2 精简专用服务端（主仓库）

将原版约 **72.3GB** 的 CS2 专用服务器精简到 **~1.7GB（Linux）/ ~1.9GB（Windows）**（解压后，单地图 de_dust2 实测可用；体积随 CS2 更新略有浮动，最新实测见 `DEVELOP.md`）。

本仓库提供**零依赖一键安装**：自动下载工具、获取配方、下载 depot（或拉取预构建包）并拼装成可直接启动的精简服务端。无需手动安装 SteamCMD / DepotDownloader。

## 一键安装

> 💡 不想手写命令？**在线生成一键安装指令**：<https://cyqmq.github.io/cs2-slim-scripts/>（选择地图/功能/模式，自动生成 Linux / Windows 命令）

### Linux (curl | bash)

> ⚠️ **重要**：管道右侧的 `bash` 收不到 `VAR=值 curl ... | bash` 里的变量（变量只传给 `curl`）。请**先用 `export`**。

```bash
# 默认: de_dust2 精简服务端（source 模式，首次约 1.5GB 下载）
curl -fsSL https://raw.githubusercontent.com/cyqmq/cs2-slim-replica/main/scripts/get-cs2slim.sh | bash

# 更快: 预构建模式（直接拉 Release 包拼装，核心包约 1.1GB）
export CS2_MODE=prebuilt CS2_MAPS=de_dust2,de_mirage CS2_FEATURES=bots
curl -fsSL https://raw.githubusercontent.com/cyqmq/cs2-slim-replica/main/scripts/get-cs2slim.sh | bash

# 国内网络受限: 加 GitHub 加速代理
export CS2_GH_PROXY=https://ghproxy.com CS2_MODE=prebuilt
curl -fsSL https://raw.githubusercontent.com/cyqmq/cs2-slim-replica/main/scripts/get-cs2slim.sh | bash

# 面板模式（简幻欢 / Pterodactyl）: 自动生成 $HOME/start.sh（首次启动会自动安装）
export CS2_MODE=prebuilt CS2_PANEL=1
curl -fsSL https://raw.githubusercontent.com/cyqmq/cs2-slim-replica/main/scripts/get-cs2slim.sh | bash
```

### Windows (irm | iex)

```powershell
# 默认: de_dust2 精简服务端（source 模式）
irm https://raw.githubusercontent.com/cyqmq/cs2-slim-replica/main/scripts/get-cs2slim.ps1 | iex

# 更快: 预构建模式（选配地图 + 人机）
$env:CS2_MODE='prebuilt'; $env:CS2_MAPS='de_dust2,de_mirage'; $env:CS2_FEATURES='bots'
irm https://raw.githubusercontent.com/cyqmq/cs2-slim-replica/main/scripts/get-cs2slim.ps1 | iex
```

### 环境变量

| 变量 | 说明 | 默认 |
|------|------|------|
| `CS2_MODE` | `source`（从 depot 构建）或 `prebuilt`（拉取 Release 包拼装） | source |
| `CS2_MAPS` | 逗号分隔地图（如 `de_dust2,de_mirage`） | de_dust2 |
| `CS2_FEATURES` | 逗号分隔功能（如 `bots`） | (空) |
| `CS2_WORKDIR` | 工作目录 | `~/cs2-slim-build` |
| `CS2_PACKAGE` | 1=完成后打包（仅 source 模式） | 0 |
| `CS2_DRY_RUN` | 1=只生成配置不下载（预览） | 0 |
| `CS2_GH_PROXY` | GitHub 加速代理前缀（如 `https://ghproxy.com`） | (空) |
| `CS2_PANEL` | 1=面板模式：生成/覆盖 `$HOME/start.sh` | 0 |

> 📄 完整环境变量说明（含运行/启动变量：`SERVER_PORT`、`CS2_PORT`、`CS2LM_WEB`、`CS2LM_WEB_TOKEN` 等，含端口优先级与示例）见 **[`VARIABLES.md`](VARIABLES.md)**。

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

## 相关仓库

| 仓库 | 角色 |
|------|------|
| [cs2-slim-replica](https://github.com/cyqmq/cs2-slim-replica)（本仓库） | 主仓库：配方 + 一键脚本 + CLI |
| [cs2-slim-maps](https://github.com/cyqmq/cs2-slim-maps) | 选配地图（de_mirage / de_inferno / …） |
| [cs2-slim-features](https://github.com/cyqmq/cs2-slim-features) | 选配功能（bots 人机等） |

## 更多文档

- **完整复刻指南**（源码构建原理、手动步骤、双平台适配、全部踩坑）: [`core/CS2_SLIM_GUIDE.md`](core/CS2_SLIM_GUIDE.md)
- **开发 / CLI / 架构文档**（CLI 子命令、配置驱动、仓库结构、实测记录）: [`DEVELOP.md`](DEVELOP.md)