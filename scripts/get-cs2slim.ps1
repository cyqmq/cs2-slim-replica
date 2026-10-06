# cs2slim 一键安装脚本 (Windows)
#
# 用法:
#   irm https://raw.githubusercontent.com/cyqmq/cs2-slim-replica/main/scripts/get-cs2slim.ps1 | iex
#
# 环境变量（可选，先设置再执行）:
#   $env:CS2_MAPS     逗号分隔地图列表, 默认 de_dust2
#   $env:CS2_FEATURES  逗号分隔功能列表, 默认空
#   $env:CS2_WORKDIR  工作目录, 默认 $HOME\cs2-slim-build
#   $env:CS2_PACKAGE  '1'=完成后打包 zip
#
# 示例:
#   $env:CS2_MAPS = 'de_dust2,de_mirage'; $env:CS2_FEATURES = 'bots'
#   irm https://raw.githubusercontent.com/cyqmq/cs2-slim-replica/main/scripts/get-cs2slim.ps1 | iex
#
$ErrorActionPreference = 'Stop'

$Maps = if ($env:CS2_MAPS) { $env:CS2_MAPS } else { 'de_dust2' }
$Features = if ($env:CS2_FEATURES) { $env:CS2_FEATURES } else { '' }
$Workdir = if ($env:CS2_WORKDIR) { $env:CS2_WORKDIR } else { Join-Path $HOME 'cs2-slim-build' }
$Package = if ($env:CS2_PACKAGE -eq '1') { $true } else { $false }
$DryRun = if ($env:CS2_DRY_RUN -eq '1') { $true } else { $false }
$RepoUrl = 'https://github.com/cyqmq/cs2-slim-replica.git'
$DDUrl = 'https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_3.4.0/DepotDownloader-win-x64.zip'
$SteamManifestUrl = 'https://client-update.akamai.steamstatic.com/steam_client_win32'

Write-Host "== cs2slim 一键安装 (Windows) =="
$FeaturesDisplay = if ($Features) { $Features } else { '无' }
Write-Host "地图: $Maps / 功能: $FeaturesDisplay / 工作目录: $Workdir"

# --- 检查 Python ---
$PyExe = $null
foreach ($cmd in @('python', 'py', 'python3')) {
  $c = Get-Command $cmd -ErrorAction SilentlyContinue
  if ($c -and $c.Source -and (Test-Path $c.Source)) { $PyExe = $c.Source; break }
}
if (-not $PyExe) {
  # 常见安装路径兜底 (LOCALAPPDATA\Programs\Python\Python*\python.exe)
  $found = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Programs\Python') -Filter python.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($found) { $PyExe = $found.FullName }
}
if (-not $PyExe) { throw '需要 Python 3 (python 或 py)，或手动将 python 加入 PATH' }

New-Item -ItemType Directory -Force -Path "$Workdir\tools" | Out-Null

# --- 1. DepotDownloader ---
$DDDir = "$Workdir\tools\depotdownloader"
$DDExe = "$DDDir\DepotDownloader.exe"
if ($DryRun) {
  Write-Host '[1/5] (dry-run) 跳过 DepotDownloader 下载'
} else {
  if (-not (Test-Path $DDExe)) {
    Write-Host '[1/5] 下载 DepotDownloader ...'
    New-Item -ItemType Directory -Force -Path $DDDir | Out-Null
    $ddZip = "$DDDir\dd.zip"
    Invoke-WebRequest -Uri $DDUrl -OutFile $ddZip
    Expand-Archive -Path $ddZip -DestinationPath $DDDir -Force
    Remove-Item -Force $ddZip
  }
}

# --- 2. steamclient DLL (Steam 客户端更新包) ---
$SCDir = "$Workdir\tools\steamclient64_win"
if ($DryRun) {
  Write-Host '[2/5] (dry-run) 跳过 steamclient DLL 下载'
} else {
  if (-not (Test-Path "$SCDir\steamclient64.dll")) {
    Write-Host '[2/5] 获取 Steam 客户端更新包 (steamclient DLL) ...'
    New-Item -ItemType Directory -Force -Path $SCDir | Out-Null
    $manifest = "$Workdir\tools\steam_client_win32"
    Invoke-WebRequest -Uri $SteamManifestUrl -OutFile $manifest
    $m = Select-String -Path $manifest -Pattern 'bins_win32\.zip\.([0-9a-f]+)' | Select-Object -First 1
    if (-not $m) { throw '无法在 Steam 客户端 manifest 中找到 bins_win32.zip' }
    $sha = $m.Matches[0].Groups[1].Value
    $binZip = "$Workdir\tools\bins_win32.zip"
    Invoke-WebRequest -Uri "https://steamcdn-a.akamaihd.net/client/bins_win32.zip.$sha" -OutFile $binZip
    $binDir = "$Workdir\tools\bins_win32"
    Expand-Archive -Path $binZip -DestinationPath $binDir -Force
    Copy-Item "$binDir\steamclient64.dll", "$binDir\tier0_s64.dll", "$binDir\vstdlib_s64.dll" $SCDir
    Remove-Item -Recurse -Force $binDir
    Remove-Item -Force $binZip
  }
}

# --- 3. 获取主仓库 ---
$RepoDir = "$Workdir\repo"
if (-not (Test-Path "$RepoDir\.git")) {
  Write-Host '[3/5] 获取主仓库 ...'
  if (Get-Command git -ErrorAction SilentlyContinue) {
    git clone --depth 1 $RepoUrl $RepoDir
  } else {
    New-Item -ItemType Directory -Force -Path $RepoDir | Out-Null
    $tar = "$Workdir\repo.tar.gz"
    Invoke-WebRequest -Uri 'https://github.com/cyqmq/cs2-slim-replica/archive/refs/heads/main.tar.gz' -OutFile $tar
    tar -xzf $tar -C $RepoDir --strip-components=1
    Remove-Item -Force $tar
  }
}

# --- 4. 生成配置 ---
$Cfg = "$Workdir\slim.yaml"
@"
platform: win64
maps: [$Maps]
features: [$Features]
workdir: $Workdir
depot_tool: $DDExe
"@ | Set-Content -Path $Cfg -Encoding UTF8
Write-Host "[4/5] 配置已生成: $Cfg"

# --- 5. 一键执行 download + extract + build (+package) ---
$CliArgs = @("$RepoDir\cs2slim.py", 'all', '--config', $Cfg)
if ($Package) { $CliArgs += '--package' }
if ($DryRun) {
  Write-Host '[5/5] (dry-run) 跳过一键执行'
  Write-Host "将执行: $PyExe $($CliArgs -join ' ')"
} else {
  Write-Host '[5/5] 开始下载/提取/组装 (首次约 1.7GB 下载, 请耐心等待) ...'
  & $PyExe @CliArgs
  if ($LASTEXITCODE -ne 0) { throw "cs2slim all 失败 (exit $LASTEXITCODE)" }
}

if ($DryRun) {
  Write-Host ''
  Write-Host '(dry-run 结束: 未下载/未构建。重新执行并设置 CS2_DRY_RUN=0 即开始真实构建。)'
} else {
  Write-Host ''
  Write-Host '=============================================='
  Write-Host '✅ 完成! 启动服务端:'
  Write-Host "  $Workdir\slim-win\start_server.bat"
  if ($Package) { Write-Host "  安装包: $Workdir\cs2-slim-win.zip" }
  Write-Host '=============================================='
}