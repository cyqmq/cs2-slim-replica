# cs2-slim 环境变量说明

本文件汇总 cs2-slim 相关脚本使用的全部环境变量，按「安装/构建」与「运行/启动」分类说明。

> 简幻欢 / Pterodactyl 等面板通常在面板的「启动参数 / 环境变量」配置里填写这些变量，脚本会自动读取。
>
> **简幻欢面板启动命令固定为 `bash start.sh`、无法在面板配置环境变量时**：所有运行/启动变量（端口、网络模式、服务器密码、插件管理 Web、GSLT 等）已内嵌到 `$HOME/start.sh` 顶部的 **「★ 运行 / 启动配置区」**，直接编辑该区域即可生效（环境变量仍优先于配置区默认值）。重新运行一键脚本会覆盖 `start.sh`，自定义配置前请先备份。

---

## 一、安装 / 构建变量（`scripts/get-cs2slim.sh`）

| 变量 | 默认值 | 说明 |
|---|---|---|
| `CS2_MODE` | `source` | 构建模式：`source`（从 depot 构建）或 `prebuilt`（直接拉取 Release 包拼装，推荐） |
| `CS2_MAPS` | `de_dust2` | 逗号分隔的地图列表，如 `de_dust2,de_mirage` |
| `CS2_FEATURES` | 空 | 逗号分隔的选配功能列表，如 `metamod,css,link-manager` |
| `CS2_WORKDIR` | `$HOME/cs2-slim-build` | 工作目录（下载、解压、拼装都在这里） |
| `CS2_PACKAGE` | `0` | `1` = 完成后打包 tar.gz |
| `CS2_DRY_RUN` | `0` | `1` = 只生成配置不下载（预览效果）。**非面板模式不会生成 / 覆盖 `start.sh`；面板模式（`CS2_PANEL=1`）会生成 `$HOME/start.sh` 预览版** |
| `CS2_GH_PROXY` | 空 | GitHub 加速代理前缀（如 `https://ghproxy.com`），用于仓库 / Release 下载 |
| `CS2_PANEL` | `0` | `1` = 面板模式（简幻欢 / Pterodactyl 等）：完成后在 `$HOME` 生成 `start.sh`；**`CS2_DRY_RUN=1` 时也会生成 `start.sh` 预览**（供面板先配置启动命令） |

**示例**（prebuilt 一键安装 + 地图 + 功能）：

```bash
export CS2_MODE=prebuilt CS2_MAPS=de_dust2,de_mirage CS2_FEATURES=metamod,css,link-manager
curl -fsSL https://raw.githubusercontent.com/cyqmq/cs2-slim-replica/main/scripts/get-cs2slim.sh | bash
```

> ⚠️ 注意：`curl ... | bash` 时变量要先用 `export` 导出，写在 curl 前面不会传给 bash。

---

## 二、端口变量（启动脚本通用）

优先级：**`SERVER_PORT`（面板注入）> `CS2_PORT`（用户指定）> `27015`（默认）**

| 变量 | 默认值 | 说明 |
|---|---|---|
| `SERVER_PORT` | 未设置 | 面板注入的端口（简幻欢等分配随机端口）。**优先级最高**，设置后会顶掉 `CS2_PORT` |
| `CS2_PORT` | `27015` | 用户手动指定的端口。本地场景想换端口时设置，面板场景无需设置 |

**示例**：

```bash
# 本地 Linux：指定端口 28000
CS2_PORT=28000 bash start_server.sh

# 面板：面板会自动注入 SERVER_PORT，无需手动设置；即使同时设置了 CS2_PORT，也以 SERVER_PORT 为准
```

**Windows**（`start_server.bat`）：

```bat
:: 本地 Windows：指定端口 28000
set CS2_PORT=28000
start_server.bat
```

---

## 三、插件管理 Web 变量（link-manager 功能）

| 变量 | 默认值 | 说明 |
|---|---|---|
| `CS2LM_WEB` | `0`（关闭） | `1` = 启用插件管理 Web（TCP），与 CS2 UDP 同端口共存。需要已安装 `link-manager` 功能 |
| `CS2LM_WEB_TOKEN` | 空（随机生成） | Web 访问 token。设置后使用该固定 token；**无论是否设置，token 都会写入服务器根目录 `web_token.txt`**（未设置时随机生成 16 位十六进制） |
| `CS2LM_MENU` | 未设置 | `1` = 强制显示启动菜单（即使不是首次启动/没有终端）。面板里设置后每次点「启动」都会弹出菜单 |
| `CS2LM_AUTO` | 未设置 | `1` = 强制跳过菜单，直接完整启动（面板自动重启 / 不想被菜单打扰时设置） |

**示例**：

```bash
# Linux 面板 / 本地：启用 Web 并指定 token（token 仍会写入 web_token.txt）
CS2LM_WEB=1 CS2LM_WEB_TOKEN=my-secret bash start_server.sh

# Linux：强制显示菜单（相当于 bash start_server.sh menu）
CS2LM_MENU=1 bash start_server.sh

# Linux：强制跳过菜单，直接完整启动（面板自动重启推荐）
CS2LM_AUTO=1 bash start_server.sh

# Windows
set CS2LM_WEB=1
set CS2LM_WEB_TOKEN=my-secret
start_server.bat
```

启用后访问：`http://<服务器IP>:<端口>/?token=<TOKEN>`（端口 = 上述端口变量的最终值）。

运行中的 CS2 控制台可随时手动执行 `exec cs2slim_token.cfg` 查看当前 token（启动时已生成在 `game/csgo/cfg/cs2slim_token.cfg`）。

---

## 三·五、启动菜单（一次性交互菜单）

三个启动脚本（Linux 本地 `start_server.sh` / Linux 面板 `start_panel.sh` / Windows `start_server.bat`）内置**一次性交互菜单**：

- **什么时候显示**：仅在「有交互终端 且 首次启动（不存在 `.cs2slim_menu_seen` 标记）」时显示，或通过 `menu` 参数 / `CS2LM_MENU=1` 强制显示。
- **菜单选项**：`1` 完整启动 / `2` 只启动 Web / `3` 只启动 CS2 / `4` 查看 token / `5` 停止 Web / `6` 退出。15 秒无输入默认选 `1`。其中 `1` 是否启动 Web 取决于 `CS2LM_WEB`（默认 `0` 不启动；菜单会按当前配置动态显示，未启用时会提示把配置区 `CS2LM_WEB` 改为 `1`）。
- **选择后**：立即 `exec` CS2 前台运行，控制台正常显示服务端日志（菜单**不会**反复出现挡住日志）。
- **再次打开菜单**：运行 `bash start_server.sh menu`（Windows `start_server.bat menu`）；面板场景可在 `start.sh` 顶部加 `export CS2LM_MENU=1`，或在面板环境变量里配置 `CS2LM_MENU=1`。
- **跳过菜单**：`bash start_server.sh auto`（Windows `start_server.bat auto`）、`CS2LM_AUTO=1`、或非交互终端（无 TTY）都会直接完整启动，适合面板自动重启。

**子命令速查**（Linux `start_server.sh` / 面板 `start.sh`，Windows 同参数）：

| 命令 | 作用 |
|---|---|
| `bash start_server.sh` | 首次交互启动显示菜单；之后直接完整启动 |
| `bash start_server.sh menu` | 强制显示菜单（想再次打开时使用） |
| `bash start_server.sh auto` | 跳过菜单，直接完整启动（面板自动重启推荐） |
| `bash start_server.sh web` | 只启动插件管理 Web（打印 token） |
| `bash start_server.sh token` | 只显示当前 token |
| `bash start_server.sh webstop` | 停止插件管理 Web |

---

## 三·六、网络模式与服务器密码变量（运行）

| 变量 | 默认值 | 说明 |
|---|---|---|
| `CS2_NET_MODE` | `2` | 服务端网络模式：`1`=局域网（`+sv_lan 1`）、`2`=互联网/外网直连（`+sv_lan 0 -ip 0.0.0.0`，默认，不进公网列表）、`3`=公开（`+sv_lan 0` + GSLT，进 Steam 公网列表） |
| `CS2_GSLT` / `GSLT` / `CS2LM_GSLT` | 空 | 档3 公开所需的 GSLT token。优先级 `CS2_GSLT` > `GSLT` > `CS2LM_GSLT`；档3 无 GSLT 时自动回退档2 |
| `CS2_PASSWORD` | 空 | 服务器进入密码。默认空 = 无密码；非空时启动参数追加 `+sv_password <密码>` |

**警告**：本精简服务端为非认证/可能涉及违规场景。档3 公开绑定 GSLT 可能导致该 Steam 账号的 GSLT 服务被封禁，请自行评估风险。

**面板用户**：以上运行变量已内嵌到 `$HOME/start.sh` 顶部的「★ 运行 / 启动配置区」，直接编辑 `start.sh` 即可（例如把 `export CS2_NET_MODE="${CS2_NET_MODE:-2}"` 里的 `2` 改成 `1`），无需在面板配置环境变量。

**示例**：

```bash
# Linux：档2（默认，外网可直连）+ 设置服务器进入密码
CS2_PASSWORD=abc123 bash start_server.sh

# Linux：档3 公开（需 GSLT）+ 密码
CS2_GSLT=TOKEN CS2_PASSWORD=abc123 CS2_NET_MODE=3 bash start_server.sh

# Windows
set CS2_PASSWORD=abc123
start_server.bat
```

---

## 四、面板启动脚本变量（`start_panel.sh` 额外支持）

| 变量 | 默认值 | 说明 |
|---|---|---|
| `CS2_MAPS` | `de_dust2` | 选配地图，逗号分隔 |
| `CS2_FEATURES` | 空 | 选配功能列表，逗号分隔 |
| `CS2_SLIM_DIR` | `$HOME/cs2-slim-build/slim` | 精简树路径（已安装的精简服务端目录） |

---

## 五、变量速查表

| 变量 | 默认值 | 作用 | 适用场景 |
|---|---|---|---|
| `CS2_MODE` | `source` | 构建模式 | 安装 |
| `CS2_MAPS` | `de_dust2` | 地图列表 | 安装 / 面板启动 |
| `CS2_FEATURES` | 空 | 功能列表 | 安装 / 面板启动 |
| `CS2_WORKDIR` | `$HOME/cs2-slim-build` | 工作目录 | 安装 |
| `CS2_PACKAGE` | `0` | 完成后打包 | 安装 |
| `CS2_DRY_RUN` | `0` | 预览模式 | 安装 |
| `CS2_GH_PROXY` | 空 | GitHub 加速代理 | 安装 |
| `CS2_PANEL` | `0` | 面板模式 | 安装 |
| `SERVER_PORT` | 未设置 | 面板端口（最高优先） | 运行 |
| `CS2_PORT` | `27015` | 用户指定端口 | 运行 |
| `CS2_NET_MODE` | `2` | 网络模式：1=局域网 / 2=互联网直连 / 3=公开(需GSLT) | 运行 |
| `CS2_GSLT` | 空 | 档3 公开所需 GSLT（`CS2_GSLT`>`GSLT`>`CS2LM_GSLT`） | 运行 |
| `CS2_PASSWORD` | 空 | 服务器进入密码（默认无密码） | 运行 |
| `CS2LM_WEB` | `0` | 启用插件管理 Web | 运行 |
| `CS2LM_WEB_TOKEN` | 空（随机） | Web token（固定值，仍会写入 `web_token.txt`） | 运行 |
| `CS2LM_MENU` | 未设置 | `1` = 强制显示启动菜单 | 运行 |
| `CS2LM_AUTO` | 未设置 | `1` = 强制跳过菜单 | 运行 |
| `CS2_SLIM_DIR` | `$HOME/cs2-slim-build/slim` | 精简树路径 | 面板启动 |