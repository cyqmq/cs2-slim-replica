# CS2 精简专用服务端 · 复刻指南

> 目标：将原版 72.3GB 的 CS2 专用服务器精简到 **2.5GB（解压后）**，单地图（de_dust2）可用，-insecure 模式运行。
> 本指南记录完整过程、关键命令、踩坑点与注意事项，供复刻参考。

---

## 一、核心思路

CS2 服务端体积主要由 `game/csgo/pak01_dir.vpk` 及其 **506 个编号数据块**（pak01_000~505）构成（约 53GB）。
其中 **44GB 是纯客户端纹理、4.4GB 音频、其余为全景图/贴纸/UI**，服务器运行根本不需要。

但引擎的 `gameinfo.gi` 会自动挂载 `csgo/` 下所有 `pak*_dir.vpk`，一旦挂载 `pak01_dir.vpk`，
就会索引全部编号包，启动时读取实体/模型/数据时不断触发"缺包 FATAL"。

**关键方案：**
1. 只下载"含服务端必需内容"的编号包；
2. 从这些包中**提取服务器真正需要的文件（模型/物理/材质/数据/脚本）为 loose files**（仅 557MB）；
3. **移走 `pak01_dir.vpk` 和所有编号包**，让引擎不再挂载；
4. loose files 按原路径放入 `csgo/` 目录，引擎优先加载 loose files；
5. 保留地图 VPK + prefabs + 服务端二进制，启动即用。

---

## 二、环境与磁盘预算

- Debian 12，x86_64，磁盘 **20GB**（原版 72GB 装不下，必须精简）
- 需要能访问 GitHub 与 Steam CDN

---

## 三、工具准备

| 工具 | 用途 | 获取 |
|------|------|------|
| DepotDownloader 3.4.0 | Steam depot 下载 | GitHub `SteamRE/DepotDownloader` releases，选 `DepotDownloader-linux-x64.zip`（自包含，无需 .NET） |
| Source2Viewer-CLI 20.0 | VPK 分析/提取 | GitHub `ValveResourceFormat/ValveResourceFormat` releases，选 `cli-linux-x64.zip` |
| Python 3 | VPK 解析脚本 | 本指南附带脚本 |

```bash
mkdir -p /workspace/tools/depotdownloader
cd /workspace/tools/depotdownloader
curl -L -o dd.zip https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_3.4.0/DepotDownloader-linux-x64.zip
unzip -o dd.zip && chmod +x DepotDownloader
```

Source2Viewer-CLI 若提示缺 libicu，可用 `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` 运行，或 `apt install libicu72`。

---

## 四、资产分析

### 4.1 拉取 depot manifest（不下载内容）

```bash
./DepotDownloader -app 730 -depot 2347770 -manifest-only -dir /tmp/manifests
./DepotDownloader -app 730 -depot 2347773 -manifest-only -dir /tmp/manifests
```

关键发现：
- **2347770（共享内容）：65GB，2989 个文件**
  - `game/csgo/` 64.4GB（其中 pak01 编号包约 53GB、maps 10.2GB、shaders/panorama 等）
  - `game/core/` 684MB（引擎核心，含 6 个小编号包）
- **2347773（Linux 服务端二进制）：7.2GB，135 个文件**
  - `game/bin/linuxsteamrt64/`（服务端 .so，238MB）
  - `game/csgo/bin/`（122MB）
  - `game/csgo_community_addons/`（6 张社区图，6.86GB，**可整体排除**）
- **App 730 还有 731、2347774 等 depot（csgo_lv 低暴力内容）**，下载时务必用 `-depot` 显式指定，否则会把 1.1GB 多余内容也拉下来。

### 4.2 解析 pak01_dir.vpk（Python）

自行实现 VPK v2 目录解析：签名 `0x55aa1234`，版本 u32=2，树大小 u32；
v2 头部后 16 字节为各 MD5 段大小；树从偏移 32 开始。
条目格式：`CRC(u32) + preload(u16) + archiveIndex(u16) + offset(u32) + length(u32) + terminator(u16)`。
注意：Valve 用**一个空格目录名表示根目录**（如 `" /gamemodes.txt"`），提取时要规范化路径。

分类统计（csgo/pak01）：
```
textures       44GB   ← 纯客户端，排除
sounds         4.4GB  ← 纯客户端，排除
models/physics 583MB  ← 服务器需要（碰撞/命中盒）
data/config    165MB  ← 服务器必需（items_game、脚本、gameevents）
materials      99MB   ← 材质（含表面属性，保留）
panorama/UI    几十MB ← 排除
```

---

## 五、下载精简集合

### 5.1 生成 filelist（包含模式）

DepotDownloader 3.x 的 `-filelist` 是**包含语义**：
- 普通行 = 精确路径
- `regex:` 前缀 = .NET 正则（可用负向断言做排除）

下载集合（约 7GB）：
- `pak01_dir.vpk` + 含 `data-config`/`soundevents` 内容的编号包（约 51 个）
- 7 张竞技地图 VPK + `maps/prefabs/`（**必须！缺 prefab 会导致地图加载失败并回退 Idle**）
- cfg、gameinfo.gi、steam.inf 等散文件
- 服务端二进制（2347773 的 `game/bin/linuxsteamrt64` + `game/csgo/bin`）

```bash
./DepotDownloader -app 730 -depot 2347770 -dir /workspace/cs2 -filelist main.txt
./DepotDownloader -app 730 -depot 2347773 -dir /workspace/cs2 -filelist bin.txt
```

### 5.2 迭代补包

启动时若报 `FATAL ERROR: Error reading from loaded packed store ".../pak01_NNN.vpk"`，
说明该包含服务器启动必需文件。从 console.log 提取包号，下载后重启，直到无 FATAL。

```bash
echo "game/csgo/pak01_$N.vpk" > iter.txt
./DepotDownloader -app 730 -depot 2347770 -dir /workspace/cs2 -filelist iter.txt
```

> 实测补了约 26 个额外包（003/064/140/305/335/358/386/407/473...）。这是"含必需文件的混合包"，
> 里面大部分是纹理，但 VPK 按包分发无法只取文件，所以用下一节的提取方案只保留精华。

---

## 六、提取 loose files（核心步骤）

**原理**：Source 2 文件系统优先级 `loose files > addon VPK > game VPK`。
把服务器需要的文件从编号包中提取到 `csgo/` 对应路径，之后移走 `pak01_dir.vpk`，
引擎就从 loose files 加载，不再触碰编号包。

筛选规则（提取约 557MB / 19345 文件）：
- **排除**：`*.vtex_c/*.vtex/*.vsnd_c/*.vsnd`（纹理/音频）、`panorama/`、`stickers/`、`patches/`、`sprays/`、`shaders/`
- **保留**：`models/`、`materials/`、`particles/`、`resource/`、`scripts/`、`weapons/`、`characters/`、`soundevents/` 等

提取后用 `mv` 将 `csgo/pak01_*.vpk` 全部移出（例如备份到 `/workspace/cs2_pak_backup`），
确认 `csgo/` 下不再有任何 `*.vpk`。

> 这一步之后，补包循环从根源消失。

---

## 七、启动配置与踩坑

### 7.1 steamclient.so（64 位）

CS2 服务端需要 64 位 `steamclient.so`，放在 `/root/.steam/sdk64/steamclient.so`。
从 SteamCMD 官方包获取（`linux64/steamclient.so`）：
```bash
mkdir -p /root/.steam/sdk64
ln -sf /workspace/tools/steamcmd/linux64/steamclient.so /root/.steam/sdk64/steamclient.so
```

### 7.2 V8 库符号链接（关键坑）

CS2 启动时会在 `game/csgo/bin/linuxsteamrt64/` 下找 `libv8.so` 等 V8 库，
但它们实际在 `game/bin/linuxsteamrt64/`。必须做符号链接：
```bash
cd /workspace/cs2/game/csgo/bin/linuxsteamrt64
for f in libv8.so libv8system.so libv8_icui18n.so libv8_icuuc.so libv8_libbase.so libv8_libcpp.so libv8_libplatform.so libv8_zlib.so; do
  ln -sf /workspace/cs2/game/bin/linuxsteamrt64/$f $f
done
```

### 7.3 启动参数

```bash
./game/bin/linuxsteamrt64/cs2 \
  -dedicated +map de_dust2 +hostname "SlimTest" \
  -maxplayers 12 -ip 0.0.0.0 -port 27015 \
  -insecure -condebug +game_type 0 +game_mode 0 \
  +sv_pure 0 +sv_cheats 1
```

- `-insecure`：禁用 VAC（服务端必须）
- `sv_pure 0`：关闭客户端文件一致性校验（因为服务端已精简文件）
- 客户端连接也必须加 `-insecure` 启动参数

### 7.4 后台运行注意

- 用后台终端运行且 **timeout=0**（否则 10 分钟会被杀）
- `-condebug` 写 `console.log` 方便排错

---

## 八、最终验证

```
[Server] SV:  12 player server started
[Server] CSource2Server::GameServerSteamAPIActivated()
UDP 27015 监听
```

客户端：Steam 启动项加 `-insecure` → 控制台 `connect 服务器IP:27015`

---

## 九、最终体积

| 项 | 大小 |
|----|------|
| 完整原版 | 72.3GB |
| 7 图精简版（解压） | 4.8GB |
| **沙2单图精简版（解压）** | **2.5GB** |
| 沙2单图压缩包 | **1.7GB** |

---

## 十、下载与部署

下载页面提供：完整包 + 9 个 200MB 分卷（支持 HTTP Range 断点续传、多线程）。

```bash
# Linux 合并分卷
cat cs2-slim.tar.gz.part* > cs2-slim.tar.gz
sha256sum -c sha256sums.txt

# 解压部署
tar -xzf cs2-slim.tar.gz
cd cs2
chmod +x start_server.sh
./start_server.sh
```

---

## 十一、注意事项清单（体检清单）

1. **磁盘**：原版 72GB 无法装入 20GB 环境，必须先用 `-manifest-only` 分析再下载，避免盲目全量。
2. **depot 选择**：始终显式 `-depot 2347770 / 2347773`，否则会拉入 csgo_lv 等多余 depot。
3. **filelist 语义**：3.x 是包含模式；如需排除用 `regex:` 负向断言。
4. **prefabs 必须下载**：`maps/prefabs/` 缺失会导致地图 Spawn 后 `GameServerSteamAPIDeactivated` 回退 Idle。
5. **V8 符号链接**：漏掉会在 `CAppSystemDict` 阶段 SIGTRAP。
6. **steamclient.so**：必须是 64 位，放 `/root/.steam/sdk64/`；32 位会报 `ELFCLASS32` 并 segfault。
7. **后台超时**：服务器用 timeout=0 的后台终端，否则 10 分钟被自动终止。
8. **-validate 不影响精简**：DepotDownloader `-validate` 只校验 filelist 内文件，不会补回被排除的包。
9. **客户端**：连精简服必须 `-insecure` + 服务器 `sv_pure 0`。

---

## 十二、附录：可直接运行的 filelist

已按本指南流程生成两份最终 filelist（基于实测下载集合，77 个 csgo 编号包 + 必需散文件），
复刻者可直接交给 DepotDownloader 使用：

| 文件 | 对应 depot | 内容 |
|------|-----------|------|
| `filelist_2347770.txt` | 2347770（共享内容） | pak01_dir + 77 个编号包 + core 004/005 + de_dust2 + prefabs + cfg/散文件 |
| `filelist_2347773.txt` | 2347773（Linux 二进制） | `game/bin/linuxsteamrt64/` + `game/csgo/bin/`，排除 csgo_community_addons |

使用命令：

```bash
./DepotDownloader -app 730 -depot 2347770 -dir /workspace/cs2 -filelist filelist_2347770.txt
./DepotDownloader -app 730 -depot 2347773 -dir /workspace/cs2 -filelist filelist_2347773.txt
```

> 说明：
> 1. `-filelist` 为包含语义，`regex:` 行是正则。
> 2. 下载完成后，继续按第六节执行"提取 loose files"，再按第七节移走编号包、配置启动。
> 3. 此 filelist 是最小集合；若启动报缺某编号包，按 5.2 节迭代补充即可。

---

## 十三、Windows 精简版适配（实测验证）

> 2026-10-06 实测：Windows Server 2022 上按本方案复刻成功，
> 服务端达到第八节全部验证标准。证明精简法跨平台通用。

### 13.1 与 Linux 版的差异

| 环节 | Linux 版 | Windows 版 |
|------|----------|------------|
| 二进制 depot | 2347773（Linux 64-bit） | **2347771（730 Windows，含 `game/bin/win64/cs2.exe`）** |
| 可执行文件 | `game/bin/linuxsteamrt64/cs2` | `game/bin/win64/cs2.exe` |
| Steam 连接 | `steamclient.so` → `/root/.steam/sdk64/` | `steamclient64.dll` + `tier0_s64.dll` + `vstdlib_s64.dll` → `game\bin\win64\` |
| V8 库 | `game/csgo/bin/linuxsteamrt64/` 符号链接 | `game/csgo/bin/win64/` 复制 7 个 `v8*.dll` |
| 启动脚本 | `start_server.sh` + `setup.sh` | `start_server.bat` |

### 13.2 Windows 二进制下载

创建 `filelist_2347771.txt`（与 2347773 同格式，路径换成 `win64`）：

```
# Depot 2347771 - CS2 Windows server binaries (slim)
# Server binaries + game binaries, exclude csgo_community_addons
regex:^game/bin/win64/
regex:^game/csgo/bin/
```

下载命令：

```bash
./DepotDownloader -app 730 -depot 2347771 -dir /workspace/cs2 -filelist filelist_2347771.txt
```

实测下载约 172MB（解压 543MB），包含 `game/bin/win64/*.dll` 与
`game/csgo/bin/win64/{client,host,matchmaking,server}.dll`。

### 13.3 steamclient 三件套（关键坑）

Windows 服务端从可执行文件所在目录加载 steamclient 相关 DLL。
首次启动若不放置会报：

```
FATAL ERROR: Failed to initialize Steamworks SDK for gameserver.
  Could not determine Steam client install directory.
```

修复：从 Steam 客户端更新包 `bins_win32.zip`（获取方式见 13.4）中提取：

- `steamclient64.dll`
- `tier0_s64.dll`
- `vstdlib_s64.dll`

复制到 `game\bin\win64\`（与 `cs2.exe` 同目录）。实测日志随后变为：

```
[Server] SteamGameServer_Init() OK, logging on to Steam
[Server] SV:  Connection to Steam servers successful.
[Server] SV:  12 player server started
```

### 13.4 Steam 客户端更新包获取

从官方 CDN 获取当前 Windows 客户端 manifest：

```bash
curl -L -o steam_client_win32 https://client-update.akamai.steamstatic.com/steam_client_win32
```

在 manifest 中查找 `bins_win32.zip.<sha>`，然后下载：

```bash
curl -L -o bins_win32.zip \
  https://steamcdn-a.akamaihd.net/client/bins_win32.zip.<sha>
```

> 注意：本机网络对 Steam CDN 单连接约 3MB 限速，大文件需用
> **1MB Range 分块下载再拼接**（`curl -r 0-999999` 逐块请求，
> 拼接脚本见仓库 `scripts/`）。

解压后即可得到 `steamclient64.dll`、`tier0_s64.dll`、`vstdlib_s64.dll`。

### 13.5 组装 Windows 精简树

与 Linux 版完全相同的 loose files（来自 depot 2347770），仅替换：

1. `game/bin/win64/` ← depot 2347771
2. `game/csgo/bin/win64/` ← depot 2347771
3. V8 DLL 复制：
   ```bat
   copy game\bin\win64\v8.dll game\csgo\bin\win64\
   copy game\bin\win64\v8system.dll game\csgo\bin\win64\
   copy game\bin\win64\v8_icui18n.dll game\csgo\bin\win64\
   copy game\bin\win64\v8_icuuc.dll game\csgo\bin\win64\
   copy game\bin\win64\v8_libbase.dll game\csgo\bin\win64\
   copy game\bin\win64\v8_libplatform.dll game\csgo\bin\win64\
   copy game\bin\win64\v8_zlib.dll game\csgo\bin\win64\
   ```
4. steamclient 三件套复制到 `game/bin/win64/`
5. 移除所有 `pak01_*.vpk`，保留 `de_dust2.vpk` + `maps/prefabs/`

### 13.6 启动与验证

`start_server.bat`：

```bat
@echo off
cd /d "%~dp0"
game\bin\win64\cs2.exe -dedicated +map de_dust2 +hostname "SlimTest" \
  -maxplayers 12 -ip 0.0.0.0 -port 27015 \
  -insecure -condebug +game_type 0 +game_mode 0 \
  +sv_pure 0 +sv_cheats 1
```

验证标准（与第八节相同）：

```
[Server] SV:  12 player server started
[Server] CSource2Server::GameServerSteamAPIActivated()
[Networking] Network socket 'server' opened on port 27015
```

实测最终体积：解压 1.92GB（20,408 文件），zip 1.24GB。

### 13.7 Windows 版注意事项

- 无需安装 Steam 客户端（三件套 DLL 已随包内置）。
- 启动时的 `Failed loading resource ... (ERROR_FILEOPEN)` 是外观类物品
  （钥匙扣/纪念品/小鸡等）缺失，非致命，符合精简设计。
- 地图光照纹理 `.vtex` 因排除规则未提取，服务端回退错误纹理，不影响服务器逻辑。
- 若提示缺某 `pak01_NNN.vpk`，与 Linux 版同样按 5.2 节迭代补充。
- 客户端连接仍需 Steam 启动项加 `-insecure`。

---

## 十四、版本更新记录

> 2026-10-06 CS2 更新后，按本方案重建，实测验证方法持久性。

### 14.1 更新内容

- 重新下载三个 depot（**filelist 不变**）：

  | depot | 新 manifest | 日期 |
  |-------|------------|------|
  | 2347770（共享内容） | 7820179980365915207 | 10/05/2026 22:26 |
  | 2347773（Linux 二进制） | 8082014506965878039 | 10/05/2026 21:25 |
  | 2347771（Windows 二进制） | 459013114122940128 | 10/05/2026 21:25 |

- 重新提取 loose files：csgo 19,187 文件 / 514.4MB；core 878 文件 / 36.6MB。
- 重新组装：Linux 1.67GB / 20,210 文件；Windows 1.90GB / 20,261 文件。
- Windows 实测启动成功，`GC Connection established for server version 2000927`。

### 14.2 关键结论

- **filelist 无需改动**：三个 filelist 在新版本上直接可用。
- **编号包自动增删**：DepotDownloader 增量更新会自动删除已不在 manifest 中的本地包
  （本次删除 `pak01_505.vpk`），无需手工干预。
- **方法持久性得到实测验证**：只要按 5.2 节"迭代补充"处理启动时报缺的编号包，
  精简法可以跟随任意 CS2 版本。

---

## 十五、多仓库架构与 cs2slim CLI（可选）

> 为方便按需组合「精简核心 + 地图 + 功能」，配方拆成**多仓库**，并提供配置/参数驱动的入口脚本。

### 15.1 仓库分工

| 仓库 | 角色 |
|------|------|
| cyqmq/cs2-slim-replica | **主仓库**：核心配方（本指南 + filelist + 脚本）+ 入口 CLI cs2slim.py + 组件注册表 |
| cyqmq/cs2-slim-maps | 地图组件：每图一个 ilelist.txt 片段 + 元数据，可选预构建包 |
| cyqmq/cs2-slim-features | 功能组件：bots 人机（服务端 bot 玩法 + 客户端离线练习） |

核心 filelist 已包含全部 prefabs，因此**选配地图只需把地图 VPK**（如 game/csgo/maps/de_mirage.vpk）追加到下载清单。
bots 是引擎内置功能，无需额外 depot 文件，只需 cfg 配置。

### 15.2 CLI 子命令

`ash
python cs2slim.py init                  # 生成 slim.yaml 模板
python cs2slim.py download --config slim.yaml   # 组合 filelist + 调用 DepotDownloader
python cs2slim.py extract  --config slim.yaml   # 提取 loose files
python cs2slim.py build    --config slim.yaml    # 组装精简树（含选配地图）
python cs2slim.py package  --config slim.yaml --format zip
python cs2slim.py run      --config slim.yaml   # 启动服务端
`

### 15.3 配置驱动（推荐）

编辑 slim.yaml：

`yaml
platform: win64            # linux | win64
maps:
  - de_dust2
  - de_mirage            # 选配地图
features:
  - bots                 # 选配功能
workdir: ./cs2-build
depot_tool: C:\path\to\DepotDownloader.exe
`

### 15.4 纯命令行参数

`ash
python cs2slim.py download --platform linux --maps de_dust2,de_mirage --features bots
`

### 15.5 预构建包（可选）

- 地图：从 cs2-slim-maps Release 下载 de_mirage.zip 等，解压到 game/csgo/maps/。
- 功能：从 cs2-slim-features Release 下载 ots-pack.zip，解压后按说明部署 cfg。
