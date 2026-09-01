#Requires -RunAsAdministrator
# Create a portable dependency archive of the vcpkg + deps trees so the VM can
# be recreated without rebuilding ffmpeg/etc from scratch.

param(
    [string]$OutDir = "\\host.lan\Data",
    [string]$SevenZip = "C:\Program Files\7-Zip\7z.exe"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

$ArchiveName = "radiobot-windows-deps.7z"
$LogFile = "C:\Temp\package-deps.log"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$ts $msg"
    Write-Host $line
    [System.IO.File]::AppendAllText($LogFile, "$line`r`n")
}

if (-not (Test-Path $SevenZip)) {
    # 7-Zip may be on the PATH after Chocolatey install.
    $SevenZip = "7z"
}

$archive = Join-Path $OutDir $ArchiveName

# If the host share is not available in this session, fall back to a local
# temp path. The host can scp the archive out afterwards.
$useUnc = $true
if (-not (Test-Path $OutDir)) {
    Write-Log "Host share $OutDir is not reachable, falling back to C:\Temp."
    $OutDir = "C:\Temp"
    $archive = Join-Path $OutDir $ArchiveName
    $useUnc = $false
}

if (Test-Path $archive) {
    Write-Log "Removing existing archive $archive"
    Remove-Item $archive -Force
}

Write-Log "Creating dependency archive at $archive ..."

# Archive the vcpkg installed tree and C:\deps. Exclude heavy intermediates that
# are not needed for building RadioBot. We do NOT archive buildtrees, packages,
# downloads, cache, ports, versions or debug libraries.
& $SevenZip a -mx=3 -m0=lzma2 `
    "-xr!vcpkg\.git" `
    "-xr!vcpkg\buildtrees" `
    "-xr!vcpkg\packages" `
    "-xr!vcpkg\downloads" `
    "-xr!vcpkg\cache" `
    "-xr!vcpkg\installed\*\debug" `
    $archive C:\vcpkg C:\deps

if ($LASTEXITCODE -gt 1) { throw "7z archive creation failed with exit code $LASTEXITCODE" }

$size = (Get-Item $archive).Length / 1MB
Write-Log "Archive created: $archive ($([math]::Round($size,2)) MB)"

if (-not $useUnc) {
    Write-Log "Archive is in C:\Temp. Retrieve it with: scp -P 2222 builder@localhost:C:/Temp/$ArchiveName ./"
}
