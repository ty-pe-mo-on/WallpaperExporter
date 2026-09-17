# WallpaperExporter PowerShell module
# Thin wrapper around WallpaperExporter.ps1 exposing one command:
#   Export-WallpaperImages [-Output <path>] [-Workshop <path>] [-Repkg <path>]

function Export-WallpaperImages {
    [CmdletBinding()]
    param(
        [string]$Output,
        [string]$Workshop,
        [string]$Repkg
    )

    $repoRoot = Split-Path -Parent $PSScriptRoot
    $script = Join-Path $repoRoot 'WallpaperExporter.ps1'
    if (-not (Test-Path -LiteralPath $script)) {
        $script = Join-Path $PSScriptRoot 'WallpaperExporter.ps1'
    }
    if (-not (Test-Path -LiteralPath $script)) {
        throw 'WallpaperExporter.ps1 was not found next to the module. Re-download the release package.'
    }

    $ini = Join-Path $repoRoot 'WallpaperExporter.ini'
    $hadIni = Test-Path -LiteralPath $ini
    $backup = $null

    if ($Output -or $Workshop -or $Repkg) {
        if ($hadIni) {
            $backup = Join-Path $env:TEMP ("WallpaperExporter.ini." + [guid]::NewGuid().ToString('N'))
            Copy-Item -LiteralPath $ini -Destination $backup -Force
        }
        $lines = @('[Paths]')
        if ($Workshop) { $lines += "Workshop=$Workshop" }
        if ($Repkg)    { $lines += "Repkg=$Repkg" }
        if ($Output)   { $lines += "Output=$Output" }
        $lines | Set-Content -LiteralPath $ini -Encoding UTF8
    }

    try {
        & $script -NoPause
    }
    finally {
        if ($Output -or $Workshop -or $Repkg) {
            if ($hadIni -and $backup) {
                Move-Item -LiteralPath $backup -Destination $ini -Force
            }
            elseif (-not $hadIni) {
                Remove-Item -LiteralPath $ini -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Export-ModuleMember -Function Export-WallpaperImages
