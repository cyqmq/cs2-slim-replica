# cs2-slim 环境变量说明

本文件汇总 cs2-slim 相关脚本使用的全部环境变量，按「安装/构建」与「运行/启动」分类说明。

> 简幻欢 / Pterodactyl 等面板通常在面板的「启动参数 / 环境变量」配置里填写这些变量，脚本会自动读取。

---

## 一、安装 / 构建变量（`scripts/get-cs2slim.sh`）

| 变量 | 默认值 | 说明 |
|---|---|---|
| `CS2_MODE` | `source` | 构建模式：`source`（从 depot 构建）或 `prebuilt`（直接拉取 Release 包拼装，推荐） |
| `CS2_MAPS` | `de_dust2` | 逗号分隔的地图列表，如 `de_dust2,de_mirage` |
| `CS2_FEATURES` | 空 | 逗号分隔的选配功能列表，如 `metamod,css,link-manager` |
| `CS2_WORKDIR` | `$HOME/cs2-slim-build` | 工作目录（下载、解压、拼装都在这里） |
| `CS2_PACKAGE` | `0` | `1` = 完成后打包 tar.gz |
| `CS2_DRY_RUN` | `0` | `1` = 只生成配置不下载（预览效果） |
| `CS2_GH_PROXY` | 空 | GitHub 加速代理前缀（如 `https://ghproxy.com`），用于仓库 / Release 下载 |
| `CS2_PANEL` | `0` | `1` = 面板模式（简幻欢 / Pterodactyl 等）：完成后在 `$HOME` 生成 `start.sh` |

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
| `CS2LM_WEB_TOKEN` | 空（随机生成） | Web 访问 token。设置后使用该固定 token；未设置则随机生成 16 位十六进制写入服务器根目录 `web_token.txt` |

**示例**：

```bash
# Linux 面板 / 本地：启用 Web 并指定 token
CS2LM_WEB=1 CS2LM_WEB_TOKEN=my-secret bash start_server.sh

# Windows
set CS2LM_WEB=1
set CS2LM_WEB_TOKEN=my-secret
start_server.bat
```

启用后访问：`http://<服务器IP>:<端口>/?token=<TOKEN>`（端口 = 上述端口变量的最终值）。

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
| `CS2LM_WEB` | `0` | 启用插件管理 Web | 运行 |
| `CS2LM_WEB_TOKEN` | 空（随机） | Web token | 运行 |
| `CS2_SLIM_DIR` | `$HOME/cs2-slim-build/slim` | 精简树路径 | 面板启动 |