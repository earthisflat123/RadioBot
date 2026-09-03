[CmdletBinding()]
param(
    [string]$OutFile = "",
    [string]$RepoDir = "C:\RadioBot",
    [string]$OEM = "C:\OEM",
    [switch]$UseOfficialInstaller
)

#Requires -Version 5.1

<#
.SYNOPSIS
    Builds a RadioBot Windows installer inside the VM or on a native Windows
    build host.

.DESCRIPTION
    By default the script builds a standalone installer from the freshly built
    output tree (C:\RadioBot\v5\Output), generates the language database,
    downloads current versions of bundled third-party tools, and compiles the
    NSIS installer. No previous RadioBot release is downloaded.

    If an existing official installer is provided (cached in the repo root or on
    the host shared drive) and -UseOfficialInstaller is specified, the script
    can still extract that file and overlay the new build output on top of it.
    This is a legacy opt-in for users who already have an installer and want to
    preserve project-specific extras not otherwise available.
#>

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

$LocalInstall = "$RepoDir\official-installer.exe"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$ts $msg"
}

function Find-OfficialInstaller() {
    # Prefer a host-shared or locally cached installer. Do not download one.
    if (-not (Test-Path "Z:\")) {
        try {
            & cmd /c "net use Z: \\host.lan\Data /y" 2>&1 | Out-Null
        } catch {
            Write-Warning "Could not map Z: drive: $_"
        }
    }
    $HostInstall = if (Test-Path "Z:\") { "Z:\official-installer.exe" } else { $null }

    if ($UseOfficialInstaller -and $HostInstall -and (Test-Path $HostInstall)) {
        Write-Log "Using host-cached official installer $HostInstall"
        Copy-Item $HostInstall $LocalInstall -Force
        return $LocalInstall
    }
    if ($UseOfficialInstaller -and (Test-Path $LocalInstall)) {
        Write-Log "Using local official installer $LocalInstall"
        return $LocalInstall
    }
    return $null
}

function Build-FromOfficialInstaller() {
    param([string]$InstallerPath)

    $SevenZip     = "C:\Program Files\7-Zip\7z.exe"
    $MakeNsis     = "C:\Program Files (x86)\NSIS\makensis.exe"
    $PayloadDir   = "$RepoDir\payload-official"
    $NsisFile     = "$OEM\RadioBot.nsi"
    $OutputDir    = "$RepoDir\v5\Output"
    $FallbackArtifacts = "$RepoDir\artifacts"

    if (-not (Test-Path $MakeNsis)) {
        Write-Log "NSIS not found, installing via Chocolatey..."
        $choco = "C:\ProgramData\chocolatey\bin\choco.exe"
        & $choco install -y nsis --no-progress
        if ($LASTEXITCODE -ne 0) { throw "Failed to install NSIS" }
    }
    if (-not (Test-Path $SevenZip)) { throw "7-Zip is required to extract the official installer" }

    Write-Output "__PROGRESS_TOTAL__ 4"

    if (Test-Path $PayloadDir) {
        Write-Log "Removing stale payload directory $PayloadDir..."
        Remove-Item $PayloadDir -Recurse -Force
    }
    Write-Log "Extracting official installer to $PayloadDir..."
    New-Item -ItemType Directory -Force -Path $PayloadDir | Out-Null
    & $SevenZip x $InstallerPath -o"$PayloadDir" -y
    if ($LASTEXITCODE -ne 0) { throw "Failed to extract official installer" }
    Remove-Item -LiteralPath "$PayloadDir\`$PLUGINSDIR" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output "__PROGRESS__ 1 4"

    Write-Log "Overlaying build output onto payload..."
    & C:\Windows\System32\robocopy.exe $OutputDir $PayloadDir /E /COPY:DAT /MT:4 /R:2 /W:2 /NDL /NFL
    if ($LASTEXITCODE -ge 8) { throw "robocopy overlay failed" }
    Write-Output "__PROGRESS__ 2 4"

    $djPackage = Join-Path $PayloadDir "DJ Package"
    if (Test-Path $djPackage) {
        @("MusicScanner.exe", "MusicScanner2.exe") | ForEach-Object {
            $p = Join-Path $djPackage $_
            if (Test-Path $p) { Remove-Item $p -Force; Write-Log "Pruned DJ Package\$_" }
        }
    }

    $IrcbotText = "$RepoDir\ircbot.text"
    $IrcbotPem  = "$RepoDir\ircbot.pem"
    $ClientPem  = "$RepoDir\Client3\client.pem"
    if (Test-Path $IrcbotText) { Copy-Item $IrcbotText $PayloadDir -Force }
    if (Test-Path $IrcbotPem)  { Copy-Item $IrcbotPem  $PayloadDir -Force }
    if (Test-Path $ClientPem)  { Copy-Item $ClientPem  $PayloadDir -Force }

    $SrcIcon = "$RepoDir\client\ca.ico"
    if (Test-Path $SrcIcon) { Copy-Item $SrcIcon "$PayloadDir\shoutirc.ico" -Force }

    if ([string]::IsNullOrWhiteSpace($OutFile)) {
        $OutFile = "$FallbackArtifacts\RadioBot-setup.exe"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $OutFile -Parent) | Out-Null

    if ((Test-Path "$RepoDir\windows-oem\RadioBot.nsi") -and ($RepoDir -ne $OEM)) {
        Copy-Item "$RepoDir\windows-oem\RadioBot.nsi" $OEM -Force
    }

    Write-Log "Building installer with makensis..."
    & $MakeNsis "/DPAYLOADDIR=$PayloadDir" "/DOUTFILE=$OutFile" $NsisFile
    if ($LASTEXITCODE -ne 0) { throw "makensis failed" }
    Write-Output "__PROGRESS__ 3 4"

    if (-not (Test-Path $OutFile)) { throw "Installer output not found" }
    $size = (Get-Item $OutFile).Length / 1MB
    Write-Log "Installer built: $OutFile ($size MB)"

    if (Test-Path "Z:\") {
        $HostArtifacts = "Z:\artifacts"
        New-Item -ItemType Directory -Force -Path $HostArtifacts | Out-Null
        $hostOut = "$HostArtifacts\$(Split-Path -Leaf $OutFile)"
        Copy-Item $OutFile $hostOut -Force
        Write-Log "Cached installer on host shared drive: $hostOut"
    }
    Write-Output "__PROGRESS_DONE__"
}

# --- Main ---
$installer = Find-OfficialInstaller
if ($installer) {
    Build-FromOfficialInstaller -InstallerPath $installer
} else {
    if ($UseOfficialInstaller) {
        Write-Warning "No official installer was found and -UseOfficialInstaller was set. Falling back to standalone packaging."
    }
    $standalone = "$OEM\package-standalone.ps1"
    if (-not (Test-Path $standalone)) {
        # Native builds use the repo's windows-oem directory.
        $standalone = "$RepoDir\windows-oem\package-standalone.ps1"
    }
    if (-not (Test-Path $standalone)) { throw "package-standalone.ps1 not found" }
    & $standalone -OutFile $OutFile -RepoDir $RepoDir -OEM $OEM
}
