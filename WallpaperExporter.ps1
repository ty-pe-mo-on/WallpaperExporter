# WallpaperExporter - extract only the main artwork images from
# Wallpaper Engine (Steam) wallpapers into one flat folder.
#
# Usage:
#   Double-click WallpaperExporter.exe, or run:
#     powershell -File WallpaperExporter.ps1 [-NoPause] [-NoPrompt]
#
# What counts as "main artwork":
#   Each wallpaper is unpacked and its scene.json / material jsons are read to
#   learn which textures the wallpaper really references. Layers that cover the
#   full frame (roughly 16:9 or 9:16, long side >= 1920) are kept; masks, depth
#   maps, normal maps, tiny assets and unreferenced leftovers are dropped.
#   If no layer passes that test, the largest referenced image is kept so every
#   wallpaper always yields at least one picture.
#
# Paths are auto-detected. You can override any of them in WallpaperExporter.ini
# (same folder as this script/exe):
#   [Paths]
#   Workshop=C:\...\steamapps\workshop\content\431960
#   Repkg=C:\...\RePKG.exe
#   Output=D:\...\wallpaper
#
# RePKG (MIT license, https://github.com/notscuffed/repkg) does the actual
# unpacking. If it is not found it is downloaded automatically.

param([switch]$NoPause, [switch]$NoPrompt)

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Continue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

$scriptDir = $null
if ($PSScriptRoot) {
    $scriptDir = $PSScriptRoot
} elseif ($ScriptRoot) {
    # ps2exe sets $ScriptRoot to the compiled exe's own folder
    $scriptDir = $ScriptRoot
} elseif ($PSCommandPath) {
    $scriptDir = Split-Path -Parent $PSCommandPath
} else {
    try {
        $scriptDir = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
    } catch {
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
}
$appDir = Join-Path $env:LOCALAPPDATA 'WallpaperExporter'
$logDir = Join-Path $appDir 'logs'
$idFile = Join-Path $appDir 'exported_ids.txt'
$repkgToolDir = Join-Path $appDir 'tools'

# initialize log directory early so header/errors are recorded too
foreach ($d in @($appDir, $logDir)) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
$script:logFile = Join-Path $logDir ("run_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".log")
Get-ChildItem $logDir -Filter 'run_*.log' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -Skip 10 |
    Remove-Item -Force -ErrorAction SilentlyContinue

# ---------------- console / log helpers ----------------
function Log([string]$msg) {
    Write-Host $msg
    if ($script:logFile) {
        Add-Content -LiteralPath $script:logFile -Value $msg -Encoding UTF8 -ErrorAction SilentlyContinue
    }
}

# ---------------- ini support ----------------
function Get-IniValue([string]$iniPath, [string]$section, [string]$key) {
    if (-not (Test-Path -LiteralPath $iniPath)) { return $null }
    $current = ''
    foreach ($line in (Get-Content $iniPath -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $t = $line.Trim()
        if ($t -match '^\[(.+)\]$') { $current = $Matches[1].Trim(); continue }
        if ($current -eq $section -and $t -match '^([^=]+)=(.*)$') {
            if ($Matches[1].Trim() -ieq $key) {
                $v = $Matches[2].Trim()
                if ($v) { return $v }
                return $null
            }
        }
    }
    return $null
}

$iniPath = Join-Path $scriptDir 'WallpaperExporter.ini'

# ---------------- path auto-detection ----------------
function Find-WorkshopDir {
    # ini override is handled by caller
    $roots = @()
    foreach ($reg in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
        try {
            $p = (Get-ItemProperty -Path $reg -ErrorAction SilentlyContinue)
            if ($p) {
                if ($p.SteamPath)   { $roots += $p.SteamPath }
                if ($p.InstallPath) { $roots += $p.InstallPath }
            }
        } catch {}
    }
    foreach ($root in ($roots | Select-Object -Unique)) {
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        $libs = @($root)
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw -Encoding UTF8), '"path"\s*"([^"]+)"')) {
                $libs += ($m.Groups[1].Value -replace '\\\\', '\')
            }
        }
        foreach ($lib in ($libs | Select-Object -Unique)) {
            $cand = Join-Path $lib 'steamapps\workshop\content\431960'
            if (Test-Path -LiteralPath $cand) {
                $hasContent = @(Get-ChildItem $cand -Directory -ErrorAction SilentlyContinue).Count
                if ($hasContent -gt 0) { return $cand }
            }
        }
    }
    return $null
}

function Find-Repkg {
    $candidates = @(
        (Join-Path $scriptDir 'RePKG.exe'),
        (Join-Path $repkgToolDir 'RePKG.exe'),
        (Join-Path $env:USERPROFILE 'Downloads\RePKG.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    $fromPath = Get-Command 'RePKG.exe' -ErrorAction SilentlyContinue
    if ($fromPath) { return $fromPath.Source }
    return $null
}

function Get-RepkgFromGithub {
    Log "RePKG.exe not found - downloading from GitHub (notscuffed/repkg, MIT license)..."
    try {
        $rel = Invoke-RestMethod 'https://api.github.com/repos/notscuffed/repkg/releases/latest' -TimeoutSec 30 -UseBasicParsing
        $asset = $rel.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1
        if (-not $asset) { throw 'no zip asset in latest release' }
        $zip = Join-Path $env:TEMP $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing -TimeoutSec 300
        New-Item -ItemType Directory -Path $repkgToolDir -Force | Out-Null
        Expand-Archive -Path $zip -DestinationPath $repkgToolDir -Force
        $exe = Get-ChildItem $repkgToolDir -Recurse -Filter 'RePKG.exe' -File | Select-Object -First 1
        if ($exe) {
            Log ("  downloaded OK -> " + $exe.FullName)
            return $exe.FullName
        }
        throw 'RePKG.exe not found inside the downloaded zip'
    } catch {
        Log ("  [WARN] auto-download failed: " + $_.Exception.Message)
        Log "  Please download RePKG manually from https://github.com/notscuffed/repkg/releases"
        Log ("  and place RePKG.exe next to this program or in " + $repkgToolDir)
        return $null
    }
}

function Set-IniOutput([string]$path) {
    try {
        $lines = @()
        if (Test-Path -LiteralPath $iniPath) { $lines = @(Get-Content $iniPath -Encoding UTF8 -ErrorAction SilentlyContinue) }
        $out = @()
        $found = $false
        $inSection = $false
        foreach ($line in $lines) {
            if ($line -match '^\s*\[') { $inSection = ($line -match '^\s*\[Paths\]\s*$') }
            if ($inSection -and $line -match '^\s*Output\s*=') {
                $out += ("Output=" + $path)
                $found = $true
            } else {
                $out += $line
            }
        }
        if (-not $found) {
            if (-not ($out -contains '[Paths]')) { $out += '[Paths]' }
            $out += ("Output=" + $path)
        }
        $out | Set-Content -LiteralPath $iniPath -Encoding UTF8
    } catch {
        # read-only location: keep the in-memory choice for this run only
    }
}

function Pick-OutputFolder([string]$defaultPath) {
    # 1) try a native folder picker dialog
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $defaultPath)) {
            New-Item -ItemType Directory -Path $defaultPath -Force | Out-Null
        }
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Select output folder for wallpaper images / 选择壁纸图片输出文件夹'
        $dlg.SelectedPath = $defaultPath
        $dlg.ShowNewFolderButton = $true
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $chosen = $dlg.SelectedPath
            if ($chosen) { return $chosen }
        }
    } catch {
        # dialog unavailable (e.g. non-STA thread) -> fall through to console prompt
    }
    # 2) console fallback
    Write-Host ''
    Write-Host ('Default output: ' + $defaultPath)
    $ans = Read-Host 'Enter an output folder, or press Enter to use the default'
    if ($ans -and $ans.Trim()) { return $ans.Trim() }
    return $defaultPath
}

function Resolve-Paths {
    $workshop = Get-IniValue $iniPath 'Paths' 'Workshop'
    if (-not $workshop) { $workshop = Find-WorkshopDir }

    $repkg = Get-IniValue $iniPath 'Paths' 'Repkg'
    if (-not $repkg -or -not (Test-Path -LiteralPath $repkg)) { $repkg = Find-Repkg }
    if (-not $repkg) { $repkg = Get-RepkgFromGithub }

    $output = Get-IniValue $iniPath 'Paths' 'Output'
    if (-not $output) {
        $pics = [Environment]::GetFolderPath('MyPictures')
        if ([string]::IsNullOrWhiteSpace($pics)) { $pics = Join-Path $env:USERPROFILE 'Pictures' }
        $default = Join-Path $pics 'wallpaper'
        if ($NoPrompt) {
            $output = $default
        } else {
            $output = Pick-OutputFolder $default
            Set-IniOutput $output
        }
    }

    return @{ Workshop = $workshop; Repkg = $repkg; Output = $output }
}

# ---------------- main ----------------
$paths = Resolve-Paths
$src   = $paths.Workshop
$repkg = $paths.Repkg
$dst   = $paths.Output

Log "============================================"
Log " WallpaperExporter - Wallpaper Engine main art extractor"
Log " Workshop dir : $src"
Log " RePKG        : $repkg"
Log " Output dir   : $dst"
Log "============================================"

if (-not $src -or -not (Test-Path -LiteralPath $src)) {
    Log "[ERROR] Wallpaper Engine workshop folder not found."
    Log "  Is Wallpaper Engine (Steam) installed and have you downloaded wallpapers?"
    Log "  You can set the path manually in WallpaperExporter.ini:"
    Log "    [Paths]"
    Log "    Workshop=C:\...\steamapps\workshop\content\431960"
    if (-not $NoPause) { Write-Host ''; Read-Host 'Press Enter to exit' | Out-Null }
    exit 1
}
if (-not $repkg -or -not (Test-Path -LiteralPath $repkg)) {
    Log "[ERROR] RePKG.exe is not available. See the messages above."
    if (-not $NoPause) { Write-Host ''; Read-Host 'Press Enter to exit' | Out-Null }
    exit 1
}
if (-not (Test-Path -LiteralPath $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$tmp = Join-Path $env:TEMP ('wp_export_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

$script:totalNew = 0
$script:totalSkip = 0
$script:skipWalls = 0
$script:wallpapers = 0
$script:failed = 0

$doneIds = New-Object System.Collections.Generic.HashSet[string]
if (Test-Path -LiteralPath $idFile) {
    Get-Content $idFile -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object {
        $t = $_.Trim(); if ($t) { [void]$doneIds.Add($t) }
    }
}
function Save-DoneId([string]$wid) {
    [void]$doneIds.Add($wid)
    Add-Content -LiteralPath $idFile -Value $wid -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Clean-Title([string]$t) {
    if ([string]::IsNullOrWhiteSpace($t)) { return $null }
    $t = ($t -replace '[\\/:*?"<>|]', ' ' -replace '[\x00-\x1f]', ' ').Trim()
    $t = $t -replace '\.+$', ''
    if ([string]::IsNullOrWhiteSpace($t)) { return $null }
    if ($t.Length -gt 40) { $t = $t.Substring(0, 40).Trim() }
    return $t
}

function Get-ImageInfo([string]$path) {
    try {
        $img = [System.Drawing.Image]::FromFile($path)
        $r = @{ w = $img.Width; h = $img.Height }
        $img.Dispose()
        return $r
    } catch { return $null }
}

function Get-TexRefs([string]$dir) {
    $set = New-Object System.Collections.Generic.HashSet[string]
    $jsons = Get-ChildItem $dir -Recurse -Filter '*.json' -File -ErrorAction SilentlyContinue
    foreach ($j in $jsons) {
        $raw = Get-Content $j.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if (-not $raw) { continue }
        foreach ($m in [regex]::Matches($raw, '"textures"\s*:\s*\[([^\]]*)\]')) {
            foreach ($s in [regex]::Matches($m.Groups[1].Value, '"([^"]+)"')) {
                [void]$set.Add(($s.Groups[1].Value.Trim()).ToLower())
            }
        }
        foreach ($m in [regex]::Matches($raw, '[A-Za-z0-9_\- ]+\.(?:png|tex|jpg|jpeg)')) {
            [void]$set.Add(([IO.Path]::GetFileNameWithoutExtension($m.Value)).Trim().ToLower())
        }
    }
    return $set
}

# ---- main-artwork filter thresholds (keep identical to desktop core rules) ----
#   $minLongSide: drop images whose longest side is shorter than this (tiny assets)
#   $minFullSide: a full-frame layer must have its long side >= this to qualify
$minLongSide = 1024
$minFullSide = 1920

function Select-MainImages([string]$fromDir) {
    $cand = @(Get-ChildItem $fromDir -Recurse -Include *.jpg, *.jpeg, *.png, *.bmp -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\masks\\' })
    $scored = @()
    foreach ($c in $cand) {
        if ($c.BaseName -match '(?i)_depth$') { continue }
        if ($c.BaseName -match '(?i)_normal$') { continue }
        $info = Get-ImageInfo $c.FullName
        if (-not $info) { continue }
        if ([Math]::Max($info.w, $info.h) -lt $minLongSide) { continue }
        $scored += [pscustomobject]@{
            File  = $c
            W     = $info.w
            H     = $info.h
            Area  = ($info.w * $info.h)
            Ratio = if ($info.h -gt 0) { [math]::Round($info.w / $info.h, 3) } else { 0 }
        }
    }
    if ($scored.Count -eq 0) { return @() }

    $refs = Get-TexRefs $fromDir
    $pool = @($scored | Where-Object { $refs.Contains($_.File.BaseName.ToLower()) })
    if ($pool.Count -eq 0) { $pool = $scored }

    $seen = New-Object System.Collections.Generic.HashSet[string]
    $pass = @()
    foreach ($p in $pool) {
        $longSide = [Math]::Max($p.W, $p.H)
        $landscape = ($p.Ratio -ge 1.55 -and $p.Ratio -le 1.95)
        $portrait  = ($p.Ratio -ge 0.50 -and $p.Ratio -le 0.65)
        if (($landscape -or $portrait) -and $longSide -ge $minFullSide) {
            $key = $p.File.FullName.ToLower()
            if ($seen.Add($key)) { $pass += $p }
        }
    }
    if ($pass.Count -eq 0) {
        $best = $null; $bestArea = -1
        foreach ($p in $pool) { if ($p.Area -gt $bestArea) { $bestArea = $p.Area; $best = $p } }
        if ($best) { $pass = @($best) }
    }
    return $pass
}

$existing = @{}
Get-ChildItem $dst -File -ErrorAction SilentlyContinue | ForEach-Object { $existing[$_.Name.ToLower()] = $true }

function Copy-Picked([object[]]$picked, [string]$title) {
    foreach ($p in $picked) {
        $img = $p.File
        $newName = "$title - $($img.Name)"
        if ($existing.ContainsKey($newName.ToLower())) { $script:totalSkip++; continue }
        $n = 2
        $base = [IO.Path]::GetFileNameWithoutExtension($newName)
        $ext  = $img.Extension
        while ($existing.ContainsKey($newName.ToLower())) {
            $newName = "$base _$n$ext"; $n++
        }
        try {
            Copy-Item -LiteralPath $img.FullName -Destination (Join-Path $dst $newName) -ErrorAction Stop
            $existing[$newName.ToLower()] = $true
            $script:totalNew++
        } catch {
            Log ("  [WARN] copy failed: " + $newName)
        }
    }
}

Get-ChildItem $src -Directory | ForEach-Object {
    $id = $_.Name
    try {
        if ($doneIds.Contains($id)) { Log ("= skip (recorded): " + $id); $script:skipWalls++; return }

        $title = $null
        $pj = Join-Path $_.FullName 'project.json'
        if (Test-Path -LiteralPath $pj) {
            try { $title = Clean-Title ((Get-Content $pj -Raw -Encoding UTF8 | ConvertFrom-Json).title) } catch {}
        }
        if (-not $title) { $title = $id }

        $pkg = Join-Path $_.FullName 'scene.pkg'
        if (-not (Test-Path -LiteralPath $pkg)) { $pkg = Join-Path $_.FullName 'project.pkg' }

        if (Test-Path -LiteralPath $pkg) {
            Log ("+ extracting: " + $title)
            $out = Join-Path $tmp $id
            & $repkg extract -c -o $out $pkg > $null 2>&1
            if ($LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath $out)) {
                & $repkg extract -c -o $out $pkg > $null 2>&1
            }
            if (-not (Test-Path -LiteralPath $out)) {
                Log ("  [WARN] repkg failed for $id")
                $script:failed++
                return
            }
            Copy-Picked (Select-MainImages $out) $title
            $script:wallpapers++
            if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force -ErrorAction SilentlyContinue }
        }
        else {
            $loose = Get-ChildItem $_.FullName -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -match '^\.(jpg|jpeg|png|bmp)$' }
            $best = $null; $bestArea = 0
            foreach ($l in $loose) {
                $info = Get-ImageInfo $l.FullName
                if (-not $info) { continue }
                if ([Math]::Max($info.w, $info.h) -lt $minLongSide) { continue }
                $a = $info.w * $info.h
                if ($a -gt $bestArea) { $bestArea = $a; $best = $l }
            }
            if ($best) {
                Copy-Picked @([pscustomobject]@{ File = $best }) $title
            }
            $script:wallpapers++
        }
        Save-DoneId $id
    }
    catch {
        Log ("  [ERROR] wallpaper $id failed: " + $_.Exception.Message)
        $script:failed++
    }
}

if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }

$sw.Stop()
$totalInDst = @(Get-ChildItem $dst -File -ErrorAction SilentlyContinue).Count

Log ""
Log "============================================"
Log (" wallpapers already exported : " + $script:skipWalls)
Log (" wallpapers processed        : " + $script:wallpapers)
Log (" new images copied           : " + $script:totalNew)
Log (" images skipped (existing)   : " + $script:totalSkip)
Log (" failures                    : " + $script:failed)
Log (" images now in output folder : " + $totalInDst)
Log (" elapsed                     : " + [math]::Round($sw.Elapsed.TotalSeconds, 1) + " s")
Log (" Log file     : " + $script:logFile)
Log "============================================"

if (-not $NoPause) {
    Write-Host ''
    Read-Host 'Press Enter to exit' | Out-Null
}
