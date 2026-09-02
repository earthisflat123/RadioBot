[CmdletBinding()]
param(
    [string]$OutFile = "",
    [string]$RepoDir = "C:\RadioBot",
    [string]$OEM = "C:\OEM"
)

#Requires -Version 5.1

<#
.SYNOPSIS
    Builds a RadioBot Windows installer inside the VM.

.DESCRIPTION
    This script merges the freshly built RadioBot binaries (C:\RadioBot\v5\Output)
    with the official extra files from the original installer payload, then builds
    an NSIS installer named C:\RadioBot\RadioBot-setup.exe.

    The original installer is loaded in this order:
      1. Z:\official-installer.exe     (host-provided or previously cached file)
      2. C:\RadioBot\official-installer.exe (already in the VM)
      3. $env:RADIOSBOT_OFFICIAL_INSTALLER_URL (host-configured URL)
      4. $OfficialUrl                    (default upstream URL)

    When a host shared drive (Z:) is reachable, both the downloaded original
    installer and the final RadioBot-setup.exe are cached there so they survive
    VM recreation. A local copy is always kept for immediate use.

    The NSIS source script is in the same C:\OEM directory (copied from
    windows-oem/RadioBot.nsi) and uses /D command-line defines for the payload
    and output paths.
#>

$ErrorActionPreference = "Stop"

$OutputDir    = "$RepoDir\v5\Output"
$PayloadDir   = "$RepoDir\payload-official"
$LocalInstall = "$RepoDir\official-installer.exe"
$OEMDir       = $OEM
$NsisFile     = "$OEMDir\RadioBot.nsi"
$SevenZip     = "C:\Program Files\7-Zip\7z.exe"
$MakeNsis     = "C:\Program Files (x86)\NSIS\makensis.exe"
$OfficialUrl  = "https://www.shoutirc.com/index.php?mod=Downloads&action=download&id=64"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$ts $msg"
}

# 1. Map the host shared drive to Z: if it is not already available, so we can
#    cache the original installer and the final setup on the host.
if (-not (Test-Path "Z:\")) {
    try {
        & cmd /c "net use Z: \\host.lan\Data /y" 2>&1 | Out-Null
    } catch {
        Write-Warning "Could not map Z: drive: $_"
    }
}
$HostRoot = if (Test-Path "Z:\") { "Z:" } else { $null }
$HostInstall = if ($HostRoot) { "$HostRoot\official-installer.exe" } else { $null }
$HostArtifacts = if ($HostRoot) { "$HostRoot\artifacts" } else { $null }
$FallbackArtifacts = "$RepoDir\artifacts"

# 2. Determine the installer output path. Prefer the host shared drive, but
#    always write a local copy as well.
if ([string]::IsNullOrWhiteSpace($OutFile)) {
    $OutFile = "$FallbackArtifacts\RadioBot-setup.exe"
}

# 3. Ensure NSIS is installed.
if (-not (Test-Path $MakeNsis)) {
    Write-Log "NSIS not found, installing via Chocolatey..."
    $choco = "C:\ProgramData\chocolatey\bin\choco.exe"
    & $choco install -y nsis --no-progress
    if ($LASTEXITCODE -ne 0) { throw "Failed to install NSIS" }
}

# 4. Ensure we have the official installer payload.
# Prefer a cached copy on the host shared drive, then a local one, then a
# configured URL, then the default upstream URL.
$needDownload = $true
$InstallerSrc = $LocalInstall
if ($HostInstall -and (Test-Path $HostInstall)) {
    Write-Log "Using host-cached installer $HostInstall"
    Copy-Item $HostInstall $InstallerSrc -Force
    $needDownload = $false
}
if ($needDownload -and (Test-Path $InstallerSrc)) {
    Write-Log "Using existing local installer $InstallerSrc"
    $needDownload = $false
}
if ($needDownload -and $env:RADIOSBOT_OFFICIAL_INSTALLER_URL) {
    Write-Log "Downloading official installer from $env:RADIOSBOT_OFFICIAL_INSTALLER_URL..."
    $downloadTarget = if ($HostInstall) { $HostInstall } else { $InstallerSrc }
    Invoke-WebRequest -Uri $env:RADIOSBOT_OFFICIAL_INSTALLER_URL -OutFile $downloadTarget -UserAgent "Mozilla/5.0"
    if ($HostInstall -and (Test-Path $HostInstall) -and ($downloadTarget -ne $InstallerSrc)) {
        Copy-Item $HostInstall $InstallerSrc -Force
    }
    $needDownload = $false
}
if ($needDownload) {
    Write-Log "Official installer not found, downloading from $OfficialUrl..."
    $downloadTarget = if ($HostInstall) { $HostInstall } else { $InstallerSrc }
    Invoke-WebRequest -Uri $OfficialUrl -OutFile $downloadTarget -UserAgent "Mozilla/5.0"
    if ($HostInstall -and (Test-Path $HostInstall) -and ($downloadTarget -ne $InstallerSrc)) {
        Copy-Item $HostInstall $InstallerSrc -Force
    }
}

# If the cache exists but the local copy is missing, copy it locally.
if ($HostInstall -and (Test-Path $HostInstall) -and -not (Test-Path $InstallerSrc)) {
    Copy-Item $HostInstall $InstallerSrc -Force
}

# Always rebuild the payload from the chosen installer so language files and
# other extras from a newer/different official installer are picked up.
if (Test-Path $PayloadDir) {
    Write-Log "Removing stale payload directory $PayloadDir..."
    Remove-Item $PayloadDir -Recurse -Force
}
Write-Log "Extracting official installer to $PayloadDir..."
New-Item -ItemType Directory -Force -Path $PayloadDir | Out-Null
& $SevenZip x $InstallerSrc -o"$PayloadDir" -y
if ($LASTEXITCODE -ne 0) { throw "Failed to extract official installer" }
$extracted = (Get-ChildItem $PayloadDir -Recurse -File | Measure-Object).Count
Write-Log "Extracted $extracted files to payload directory."
# The 7-Zip extraction also creates a $PLUGINSDIR folder from the installer's
# temp plugin files. It must not be installed to the target directory.
Remove-Item -LiteralPath "$PayloadDir\`$PLUGINSDIR" -Recurse -Force -ErrorAction SilentlyContinue
$afterRemove = (Get-ChildItem $PayloadDir -Recurse -File | Measure-Object).Count
Write-Log "After removing `$PLUGINSDIR: $afterRemove files."

# 3. Overlay the new build output on top of the payload. This preserves all the
#    official extra files (langsrc, trivia, sam_scripts, DJ Package, .pal files,
#    qstat.exe, ffmpeg.exe, yt-dlp.exe, etc.) while replacing the built binaries.
Write-Log "Overlaying build output onto payload..."
$beforeOverlay = (Get-ChildItem $PayloadDir -Recurse -File | Measure-Object).Count
Write-Log "Payload contains $beforeOverlay files before overlay."
& C:\Windows\System32\robocopy.exe $OutputDir $PayloadDir /E /COPY:DAT /MT:4 /R:2 /W:2 /NDL /NFL
$afterOverlay = (Get-ChildItem $PayloadDir -Recurse -File | Measure-Object).Count
Write-Log "Payload contains $afterOverlay files after overlay."
if ($LASTEXITCODE -ge 8) { throw "robocopy overlay failed" }

# 3b. Remove only the temporary NSIS plugin directory that 7-Zip extracts from
#     the official installer. All official extra files (DJ Package, language
#     data, trivia, sam_scripts, legacy tools, etc.) are preserved. The new
#     build output was already overlaid on top, so any files with the same
#     name now contain the freshly built version.
$djPackage = Join-Path $PayloadDir "DJ Package"
if (Test-Path $djPackage) {
    # Remove any old MusicScanner binaries inside the DJ Package that would
    # otherwise be mistaken for the current build's main MusicScanner.exe.
    @("MusicScanner.exe", "MusicScanner2.exe") | ForEach-Object {
        $p = Join-Path $djPackage $_
        if (Test-Path $p) { Remove-Item $p -Force; Write-Log "Pruned DJ Package\$_" }
    }
}

# 4. Ensure the runtime config/language files are at the payload root.
$IrcbotText = "$RepoDir\ircbot.text"
$IrcbotPem  = "$RepoDir\ircbot.pem"
$ClientPem  = "$RepoDir\Client3\client.pem"
if (Test-Path $IrcbotText) { Copy-Item $IrcbotText $PayloadDir -Force }
if (Test-Path $IrcbotPem)  { Copy-Item $IrcbotPem  $PayloadDir -Force }
if (Test-Path $ClientPem)  { Copy-Item $ClientPem  $PayloadDir -Force }

# 5. Copy the icon to the payload root as shoutirc.ico (the installer uses it).
$SrcIcon = "$RepoDir\client\ca.ico"
if (Test-Path $SrcIcon) { Copy-Item $SrcIcon "$PayloadDir\shoutirc.ico" -Force }

# 6. Copy the NSIS source to C:\OEM.
New-Item -ItemType Directory -Force -Path $OEMDir | Out-Null
$RepoOEM = "$RepoDir\windows-oem"
if (Test-Path "$RepoOEM\RadioBot.nsi") { Copy-Item "$RepoOEM\RadioBot.nsi" $OEMDir -Force }

# 7. Ensure the output directory exists.
New-Item -ItemType Directory -Force -Path (Split-Path $OutFile -Parent) | Out-Null

# 8. Build the installer from the template .nsi in C:\OEM.
Write-Log "Building installer with makensis..."
& $MakeNsis "/DPAYLOADDIR=$PayloadDir" "/DOUTFILE=$OutFile" $NsisFile
if ($LASTEXITCODE -ne 0) { throw "makensis failed" }

if (Test-Path $OutFile) {
    Write-Log "Installer built: $OutFile"
    $size = (Get-Item $OutFile).Length / 1MB
    Write-Log "Size: $size MB"

    # Cache the final installer on the host shared drive if available.
    if ($HostArtifacts) {
        New-Item -ItemType Directory -Force -Path $HostArtifacts | Out-Null
        $hostOut = "$HostArtifacts\$(Split-Path -Leaf $OutFile)"
        Copy-Item $OutFile $hostOut -Force
        Write-Log "Cached installer on host shared drive: $hostOut"
    }
} else {
    throw "Installer output not found"
}

# Cache the original installer on the host shared drive if available and not
# already there, so it survives VM recreation.
if ($HostInstall -and (Test-Path $InstallerSrc) -and (-not (Test-Path $HostInstall) -or (Get-Item $HostInstall).Length -ne (Get-Item $InstallerSrc).Length)) {
    Copy-Item $InstallerSrc $HostInstall -Force
    Write-Log "Cached official installer on host shared drive: $HostInstall"
}
