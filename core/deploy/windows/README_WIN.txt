CS2 精简专用服务端 - Windows 版 (de_dust2)
===========================================

- 体积: 解压后约 1.9GB (原版 72.3GB)
- 单地图: de_dust2
- 运行模式: -insecure (无 VAC)

依赖
----
- Windows 10/11 或 Windows Server 2016+ (x64)
- 无需安装 Steam。本包已在 game\bin\win64\ 内置:
    steamclient64.dll
    tier0_s64.dll
    vstdlib_s64.dll
  服务端启动时会从可执行文件所在目录加载这三个 DLL 并初始化 Steamworks。

启动
----
双击 start_server.bat, 或命令行:
    start_server.bat

日志: -condebug 会在 game\csgo\ 目录生成 console.log

客户端连接
----------
- Steam 启动项添加 -insecure
- 控制台: connect 服务器IP:27015
- 服务器已设置 +sv_pure 0, +sv_cheats 1

验证启动
----------
- console.log 出现以下行即成功:
    [Server] SV:  12 player server started
    [Server] CSource2Server::GameServerSteamAPIActivated()
    [Networking] Network socket 'server' opened on port 27015
- 测试日志中确认输出:
    [Server] SV:  Connection to Steam servers successful.
    [Server] SV:  VAC secure mode disabled.

注意事项
----------
- 启动过程中的 "Failed loading resource ... (ERROR_FILEOPEN)" 是外观类物品
  (钥匙扣/纪念品/小鸡等) 的缺失警告, 属预期行为, 不影响服务器运行。
- 地图光照纹理 (lightmaps .vtex) 因排除规则未提取, 服务端会回退到错误纹理,
  不影响服务器逻辑 (客户端实际游玩时由客户端从地图 VPK 渲染)。
- 若提示缺某 pak01_NNN.vpk, 说明该文件未提取到 loose files, 需补充对应编号包。
- Windows 版与 Linux 版共用同一份 loose files (depot 2347770),
  验证了精简法跨平台通用。

历史
----
- 2026-10-06 实测: Windows Server 2022 上启动成功, 达到指南"最终验证"全部标准。