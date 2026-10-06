# cs2slim one-click installer (Windows)
#
# Usage:
#   irm https://raw.githubusercontent.com/cyqmq/cs2-slim-replica/main/scripts/get-cs2slim.ps1 | iex
#
# Environment variables (optional, set before running):
#   $env:CS2_MAPS      comma-separated map list, default de_dust2
#   $env:CS2_FEATURES  comma-separated feature list, default empty
#   $env:CS2_WORKDIR   working directory, default $HOME\cs2-slim-build
#   $env:CS2_PACKAGE  '1' = package zip after build
#   $env:CS2_DRY_RUN  '1' = only write config, no download (preview)
#   $env:CS2_MODE     'source' (default, build from depot) | 'prebuilt' (pull Release packages)
#
# Example:
#   $env:CS2_MAPS = 'de_dust2,de_mirage'; $env:CS2_FEATURES = 'bots'
#   irm https://raw.githubusercontent.com/cyqmq/cs2-slim-replica/main/scripts/get-cs2slim.ps1 | iex
#
$ErrorActionPreference = 'Stop'

$Maps = if ($env:CS2_MAPS) { $env:CS2_MAPS } else { 'de_dust2' }
$Features = if ($env:CS2_FEATURES) { $env:CS2_FEATURES } else { '' }
$Workdir = if ($env:CS2_WORKDIR) { $env:CS2_WORKDIR } else { Join-Path $HOME 'cs2-slim-build' }
$Package = if ($env:CS2_PACKAGE -eq '1') { $true } else { $false }
$DryRun = if ($env:CS2_DRY_RUN -eq '1') { $true } else { $false }
$Mode = if ($env:CS2_MODE) { $env:CS2_MODE } else { 'source' }
$RepoUrl = 'https://github.com/cyqmq/cs2-slim-replica.git'
$DDUrl = 'https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_3.4.0/DepotDownloader-win-x64.zip'
$SteamManifestUrl = 'https://client-update.akamai.steamstatic.com/steam_client_win32'

$FeaturesDisplay = if ($Features) { $Features } else { 'none' }
Write-Host "== cs2slim one-click installer (Windows) =="
Write-Host "Mode: $Mode / Maps: $Maps / Features: $FeaturesDisplay / Workdir: $Workdir"

# --- Python detection ---
$PyExe = $null
foreach ($cmd in @('python', 'py', 'python3')) {
  $c = Get-Command $cmd -ErrorAction SilentlyContinue
  if ($c -and $c.Source -and (Test-Path $c.Source)) { $PyExe = $c.Source; break }
}
if (-not $PyExe) {
  # Fallback: common install location (LOCALAPPDATA\Programs\Python\Python*\python.exe)
  $found = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Programs\Python') -Filter python.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($found) { $PyExe = $found.FullName }
}
if (-not $PyExe) { throw 'Python 3 is required (python or py), or add python to PATH' }

New-Item -ItemType Directory -Force -Path "$Workdir\tools" | Out-Null

# --- 1. DepotDownloader ---
$DDDir = "$Workdir\tools\depotdownloader"
$DDExe = "$DDDir\DepotDownloader.exe"
if ($Mode -eq 'prebuilt') {
  Write-Host '[1/5] (prebuilt) skip DepotDownloader download'
} elseif ($DryRun) {
  Write-Host '[1/5] (dry-run) skip DepotDownloader download'
} else {
  if (-not (Test-Path $DDExe)) {
    Write-Host '[1/5] Downloading DepotDownloader ...'
    New-Item -ItemType Directory -Force -Path $DDDir | Out-Null
    $ddZip = "$DDDir\dd.zip"
    Invoke-WebRequest -Uri $DDUrl -OutFile $ddZip
    Expand-Archive -Path $ddZip -DestinationPath $DDDir -Force
    Remove-Item -Force $ddZip
  }
}

# --- 2. steamclient DLLs (Steam client update package) ---
$SCDir = "$Workdir\tools\steamclient64_win"
if ($Mode -eq 'prebuilt') {
  Write-Host '[2/5] (prebuilt) skip steamclient DLL download'
} elseif ($DryRun) {
  Write-Host '[2/5] (dry-run) skip steamclient DLL download'
} else {
  if (-not (Test-Path "$SCDir\steamclient64.dll")) {
    Write-Host '[2/5] Fetching Steam client update package (steamclient DLL) ...'
    New-Item -ItemType Directory -Force -Path $SCDir | Out-Null
    $manifest = "$Workdir\tools\steam_client_win32"
    Invoke-WebRequest -Uri $SteamManifestUrl -OutFile $manifest
    $m = Select-String -Path $manifest -Pattern 'bins_win32\.zip\.([0-9a-f]+)' | Select-Object -First 1
    if (-not $m) { throw 'Unable to find bins_win32.zip in Steam client manifest' }
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

# --- 3. Fetch main repo ---
$RepoDir = "$Workdir\repo"
if (-not (Test-Path "$RepoDir\.git")) {
  Write-Host '[3/5] Fetching main repo ...'
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

# --- 4. Write config ---
$Cfg = "$Workdir\slim.yaml"
@"
platform: win64
maps: [$Maps]
features: [$Features]
workdir: $Workdir
depot_tool: $DDExe
"@ | Set-Content -Path $Cfg -Encoding UTF8
Write-Host "[4/5] Config written: $Cfg"

# --- 5. One-click execution (source: build / prebuilt: pull+assemble) ---
$CliArgs = @()
if ($Mode -eq 'prebuilt') {
  $CliArgs = @("$RepoDir\cs2slim.py", 'prebuilt', '--config', $Cfg)
} else {
  $CliArgs = @("$RepoDir\cs2slim.py", 'all', '--config', $Cfg)
  if ($Package) { $CliArgs += '--package' }
}
if ($DryRun) {
  Write-Host '[5/5] (dry-run) skip one-click execution'
  Write-Host "Would run: $PyExe $($CliArgs -join ' ')"
} else {
  if ($Mode -eq 'prebuilt') {
    Write-Host '[5/5] Pulling prebuilt packages and assembling (core package ~1.2GB download) ...'
  } else {
    Write-Host '[5/5] Downloading/extracting/building (first run ~1.7GB download, please wait) ...'
  }
  & $PyExe @CliArgs
  if ($LASTEXITCODE -ne 0) { throw "cs2slim failed (exit $LASTEXITCODE)" }
}

if ($DryRun) {
  Write-Host ''
  Write-Host '(dry-run finished: nothing downloaded/built. Re-run with CS2_DRY_RUN=0 to start real build.)'
} else {
  Write-Host ''
  Write-Host '=============================================='
  Write-Host 'Done! Start the server:'
  Write-Host "  $Workdir\slim-win\start_server.bat"
  if ($Package) { Write-Host "  Package: $Workdir\cs2-slim-win.zip" }
  Write-Host '=============================================='
}