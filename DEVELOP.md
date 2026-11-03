# CS2 精简服务端 · 构建仓库文档

本仓库是 **纯自动构建仓库**：产出 CS2 精简服务端 Release 包。用户侧 CLI / 一键脚本见 [cs2slim-cli](https://github.com/cyqmq/cs2slim-cli)。

## 多仓库架构

| 仓库 | 角色 |
|------|------|
| [cs2-slim-replica](https://github.com/cyqmq/cs2-slim-replica)（本仓库） | 构建仓库：核心配方 + 组件注册表（权威）+ 自动构建管线 |
| [cs2slim-cli](https://github.com/cyqmq/cs2slim-cli) | 用户侧工具：CLI + 一键安装脚本（含版本自检 / upgrade） |
| [cs2-slim-maps](https://github.com/cyqmq/cs2-slim-maps) | 地图组件（de_mirage / de_inferno / … 选配） |
| [cs2-slim-features](https://github.com/cyqmq/cs2-slim-features) | 功能组件（bots 人机等选配） |

```
构建仓库 (cs2-slim-replica)
├── core/               # 核心配方
│   ├── CS2_SLIM_GUIDE.md
│   ├── CS2_SLIM_TREE_GUIDE.md
│   ├── CS2_SLIM_MAPS_GUIDE.md
│   ├── filelists/      # 三个 depot 的核心下载清单
│   └── deploy/         # linux/windows 启动脚本
├── registry/           # 组件注册表 (core.json / maps.json / features.json)
├── state/              # buildid 版本源
├── scripts/            # 构建管线脚本
│   ├── extract_vpk.py
│   ├── rebuild_slim.py
│   └── updater/        # 检测 CS2 更新 / 清理 depot
└── .github/workflows/  # detect-cs2-update / rebuild-slim（发布 Release）
```

## 仓库内容

- `core/CS2_SLIM_GUIDE.md` — 完整复刻指南（含 Linux 与 Windows 双平台适配）
- `core/filelists/` — DepotDownloader 精准下载清单
  - `filelist_2347770.txt` — 共享内容（csgo 编号包 + core + de_dust2 + prefabs）
  - `filelist_2347773.txt` — Linux 服务端二进制
  - `filelist_2347771.txt` — Windows 服务端二进制
- `registry/` — 组件注册表（权威来源）：
  - `core.json` — 核心精简包版本 / 下载地址（Linux / Win64）
  - `maps.json` — 地图组件 + `release_version`（cs2-slim-maps 最新 Release）
  - `features.json` — 功能组件 + `release_version`（cs2-slim-features 最新 Release）
- `scripts/extract_vpk.py` — VPK v2 分层树解析 + loose files 提取
- `scripts/rebuild_slim.py` — 一键组装双平台精简树（支持 `--base-dir` / `--maps`）
- `scripts/updater/` — CS2 更新检测与 depot 清理
- `.github/workflows/` — 自动检测 CS2 更新并重建、发布 Release（通过 cs2slim-cli 的 CLI 执行）

## 构建流程（GitHub Actions）

1. `detect-cs2-update.yml`：定时检测 Steam 上的 CS2 最新 buildid，与 `state/buildid.json` 对比。
2. `rebuild-slim.yml`：检出 `cs2slim-cli`，用其 CLI（`--registry-base` 指向本仓库权威 registry）执行 download / extract / build / package，产出 Linux `tar.gz` 与 Windows `zip` 并挂到 Release。

> 注意：`cs2slim-cli` 需先发布，rebuild-slim 工作流才能检出其代码。

## CLI 使用

CLI 已迁移到 [cs2slim-cli](https://github.com/cyqmq/cs2slim-cli)。本仓库不再包含 `cs2slim.py`。如需命令行安装 / 升级，请使用 cs2slim-cli。
