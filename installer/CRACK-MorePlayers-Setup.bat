<# : batch part, PowerShell reads this block as a comment
@echo off
setlocal
set "MP_SELF=%~f0"
set "MP_ARG=%~1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:MP_SELF); Invoke-Expression $s"
if exist "%~f0.new" (move /y "%~f0.new" "%~f0" >nul & echo. & echo The installer was updated. Run it again to use the new version. & echo. & pause & exit /b)
echo.
pause
exit /b
#>
# ---------------------------------------------------------------------------------------------
# CRACK - More Players (khovanet) installer, no mod manager needed.
# Installs BepInEx 5 + the More Players mod + its Incremental-mode fix into the game folder,
# and can disable,
# re-enable or fully uninstall them. Downloads the exact Thunderstore versions below
# and checks their SHA-256 before touching the game.
# ---------------------------------------------------------------------------------------------
$ErrorActionPreference = 'Stop'
$AppId     = '4312190'
$GameExe   = 'CRACK.exe'
$Packages  = @(
  @{ Name='BepInExPack 5.4.2305'; Url='https://thunderstore.io/package/download/BepInEx/BepInExPack/5.4.2305/';
     Sha='f99b6302b6bdca5bab26f275c261cca448b29bbac34eaa5cbebb42c4246fb244'; Kind='bepinex' },
  @{ Name='More Players 0.5.2';   Url='https://thunderstore.io/package/download/khovanet/More_Players/0.5.2/';
     Sha='385fb4183df5e5d3a58fae57e82a51669898781fa051f09330c739b4a835b487'; Kind='mod' },
  @{ Name='More Players Incremental Fix 0.1.0'; Url='https://github.com/CodyLee117/crack-moreplayers-incrementalfix/releases/download/v0.1.0/crackmods-moreplayers-incrementalfix-0.1.0.zip';
     Sha='e17f9cfa2426d14825d7622224367eceddea5567dc60315da56eefd2b160ed24'; Kind='fix' }
)
$PluginDir = 'BepInEx\plugins\khovanet-More_Players'
$FixDir    = 'BepInEx\plugins\crackmods-moreplayers-incrementalfix'
$SelfUrl   = 'https://raw.githubusercontent.com/CodyLee117/crack-moreplayers-incrementalfix/main/installer/CRACK-MorePlayers-Setup.bat'
$Record    = 'BepInEx\.moreplayers-install.json'

function Say($m, $c='Gray') { Write-Host $m -ForegroundColor $c }

function Find-Game {
  $roots = @()
  foreach ($k in 'HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam') {
    try { $p = (Get-ItemProperty $k -ErrorAction Stop); if ($p.SteamPath) { $roots += $p.SteamPath }; if ($p.InstallPath) { $roots += $p.InstallPath } } catch {}
  }
  $libs = @()
  foreach ($r in ($roots | Select-Object -Unique)) {
    $r = $r -replace '/', '\'
    $libs += $r
    $vdf = Join-Path $r 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
      foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) { $libs += ($m.Groups[1].Value -replace '\\\\', '\') }
    }
  }
  foreach ($l in ($libs | Select-Object -Unique)) {
    $acf = Join-Path $l "steamapps\appmanifest_$AppId.acf"
    if (Test-Path $acf) {
      $dir = [regex]::Match((Get-Content $acf -Raw), '"installdir"\s+"([^"]+)"').Groups[1].Value
      $g = Join-Path $l "steamapps\common\$dir"
      if (Test-Path (Join-Path $g $GameExe)) { return $g }
    }
  }
  return $null
}

function Ask-Game {
  Say "Couldn't find CRACK through Steam." Yellow
  while ($true) {
    $g = Read-Host "Paste the CRACK game folder (the one with $GameExe), or leave empty to quit"
    if (-not $g) { exit 1 }
    $g = $g.Trim('"', ' ')
    if (Test-Path (Join-Path $g $GameExe)) { return $g }
    Say "No $GameExe in that folder." Red
  }
}

function Assert-NotRunning {
  if (Get-Process -Name ($GameExe -replace '\.exe$','') -ErrorAction SilentlyContinue) {
    throw "CRACK is running. Close it and run this again."
  }
}

function Get-Verified($pkg, $tmp) {
  $zip = Join-Path $tmp ($pkg.Kind + '.zip')
  Say "Downloading $($pkg.Name)..."
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $pkg.Url -OutFile $zip -UseBasicParsing
  $h = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
  if ($h -ne $pkg.Sha) { throw "$($pkg.Name): download doesn't match the expected file (sha256 $h). Nothing was changed." }
  $out = Join-Path $tmp $pkg.Kind
  Expand-Archive -LiteralPath $zip -DestinationPath $out -Force
  return $out
}

function Read-Record($game) {
  $p = Join-Path $game $Record
  if (Test-Path $p) { return Get-Content $p -Raw | ConvertFrom-Json }
  return $null
}

function Set-Doorstop($game, [bool]$on) {
  $ini = Join-Path $game 'doorstop_config.ini'
  if (-not (Test-Path $ini)) { throw "BepInEx isn't installed here (no doorstop_config.ini)." }
  $t = Get-Content $ini -Raw
  $t = [regex]::Replace($t, '(?m)^(\s*enabled\s*=\s*)(true|false)', ('${1}' + ($(if ($on) {'true'} else {'false'}))), 1)
  Set-Content -LiteralPath $ini -Value $t -NoNewline -Encoding ASCII
}

function Install($game) {
  Assert-NotRunning
  $tmp = Join-Path $env:TEMP ("moreplayers-" + [guid]::NewGuid())
  New-Item -ItemType Directory $tmp | Out-Null
  try {
    $bep = Get-Verified $Packages[0] $tmp
    $mod = Get-Verified $Packages[1] $tmp
    $fix = Get-Verified $Packages[2] $tmp
    $rec = Read-Record $game
    $weOwnBepInEx = $false
    if ($rec) { $weOwnBepInEx = [bool]$rec.installedBepInEx }
    $hasBepInEx = Test-Path (Join-Path $game 'BepInEx\core\BepInEx.dll')
    if (-not $hasBepInEx -or $weOwnBepInEx) {
      Say "Installing BepInEx 5.4.2305..."
      Copy-Item -Path (Join-Path $bep 'BepInExPack\*') -Destination $game -Recurse -Force
      $weOwnBepInEx = $true
    } else {
      Say "BepInEx is already installed here (not by this installer); leaving it as it is." Yellow
    }
    $dst = Join-Path $game $PluginDir
    New-Item -ItemType Directory $dst -Force | Out-Null
    Copy-Item -Path (Join-Path $mod 'plugins\*') -Destination $dst -Force
    Copy-Item -Path (Join-Path $mod 'manifest.json'), (Join-Path $mod 'README.md') -Destination $dst -Force
    $fdst = Join-Path $game $FixDir
    if (Test-Path $fdst) { Remove-Item $fdst -Recurse -Force }
    New-Item -ItemType Directory $fdst -Force | Out-Null
    Copy-Item -Path (Join-Path $fix 'crackmods-moreplayers-incrementalfix\*') -Destination $fdst -Force
    Set-Doorstop $game $true
    [pscustomobject]@{ installedBepInEx = $weOwnBepInEx; mod = '0.5.2'; fix = '0.1.0'; bepinex = '5.4.2305'; date = (Get-Date).ToString('s') } |
      ConvertTo-Json | Set-Content -LiteralPath (Join-Path $game $Record) -Encoding ASCII
    Say ""
    Say "Installed. Launch CRACK from Steam as usual." Green
    Say "Every player in the lobby needs the same versions of both (More Players 0.5.2 + Incremental Fix 0.1.0);"
    Say "a lobby refuses a player whose versions differ. The config file appears after the first launch:"
    Say "  $game\BepInEx\config\crackmods.moreplayers.cfg"
    Say "Note: CRACK marks modded sessions (no achievements, unranked). Use Disable to play vanilla."
  } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

function Check-Update {
  if ($env:MP_ARG -or $env:MP_NOUPDATE -eq '1') { return }
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $new = (Invoke-WebRequest -Uri $SelfUrl -UseBasicParsing -TimeoutSec 10).Content
    if ($new -is [byte[]]) { $new = [Text.Encoding]::ASCII.GetString($new) }
    $cur = [IO.File]::ReadAllText($env:MP_SELF)
    $norm = { param($x) ($x -replace "`r`n", "`n").TrimEnd() }
    if (-not $new.StartsWith('<# : batch part') -or (& $norm $new) -eq (& $norm $cur)) { return }
    Say 'A newer version of this installer is available.' Yellow
    if ((Read-Host 'Update the installer now? [Y/n]') -match '^(n|no)$') { return }
    [IO.File]::WriteAllText($env:MP_SELF + '.new', ((& $norm $new) -replace "`n", "`r`n") + "`r`n", [Text.Encoding]::ASCII)
    exit 0
  } catch { Say "(Couldn't check for an installer update: $($_.Exception.Message))" DarkGray }
}

function Disable($game) { Assert-NotRunning; Set-Doorstop $game $false; Say "Disabled: CRACK starts vanilla (BepInEx won't load). Run Enable to turn it back on." Green }
function Enable($game)  { Assert-NotRunning; Set-Doorstop $game $true;  Say "Enabled: More Players loads on the next launch." Green }

function Uninstall($game) {
  Assert-NotRunning
  $rec = Read-Record $game
  $dst = Join-Path $game $PluginDir
  if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
  $fdst = Join-Path $game $FixDir
  if (Test-Path $fdst) { Remove-Item $fdst -Recurse -Force }
  $cfg = Join-Path $game 'BepInEx\config\crackmods.moreplayers.cfg'
  if (Test-Path $cfg) { Remove-Item $cfg -Force }
  $others = @()
  $plug = Join-Path $game 'BepInEx\plugins'
  if (Test-Path $plug) { $others = @(Get-ChildItem $plug -Force) }
  if ($rec -and $rec.installedBepInEx -and $others.Count -eq 0) {
    foreach ($f in 'winhttp.dll','doorstop_config.ini','.doorstop_version') { $p = Join-Path $game $f; if (Test-Path $p) { Remove-Item $p -Force } }
    Remove-Item (Join-Path $game 'BepInEx') -Recurse -Force
    Say "Uninstalled More Players, its Incremental Fix and BepInEx. The game folder is back to vanilla." Green
  } else {
    $p = Join-Path $game $Record; if (Test-Path $p) { Remove-Item $p -Force }
    if ($others.Count -gt 0) { Say "Uninstalled More Players. BepInEx stays: other mods are in BepInEx\plugins." Green }
    else { Say "Uninstalled More Players. BepInEx was not installed by this tool, so it stays." Green }
  }
  Say "Tip: Steam > CRACK > Properties > Installed Files > Verify integrity also restores vanilla files."
}

# ------------------------------------------------- main -------------------------------------------------
try {
  Say "CRACK - More Players setup (no mod manager)" Cyan
  Check-Update
  $game = if ($env:MP_GAME -and (Test-Path (Join-Path $env:MP_GAME $GameExe))) { $env:MP_GAME } else { Find-Game }
  if (-not $game) { $game = Ask-Game }
  Say "Game folder: $game"
  $rec = Read-Record $game
  $state = if (-not $rec) { 'not installed' } else {
    $ini = Join-Path $game 'doorstop_config.ini'
    if ((Test-Path $ini) -and ((Get-Content $ini -Raw) -match '(?m)^\s*enabled\s*=\s*false')) { "installed $($rec.mod)$(if ($rec.fix) {" + fix $($rec.fix)"}), DISABLED" } else { "installed $($rec.mod)$(if ($rec.fix) {" + fix $($rec.fix)"}), enabled" } }
  Say "Status: $state"
  $choice = $env:MP_ARG
  if (-not $choice) {
    Say ""
    Say "  1) Install / update"
    Say "  2) Disable (play vanilla)"
    Say "  3) Enable"
    Say "  4) Uninstall"
    Say "  Q) Quit"
    $choice = Read-Host "Choose"
  }
  switch -Regex ($choice) {
    '^(1|install)$'   { Install $game }
    '^(2|disable)$'   { Disable $game }
    '^(3|enable)$'    { Enable $game }
    '^(4|uninstall)$' { Uninstall $game }
    default           { Say "Nothing changed." }
  }
} catch {
  Say ("ERROR: " + $_.Exception.Message) Red
  exit 1
}
