[CmdletBinding()]
param(
    [string]$OutFile = "",
    [string]$RepoDir = "C:\RadioBot",
    [string]$OEM = "C:\OEM"
)

#Requires -Version 5.1

<#
.SYNOPSIS
    Builds a RadioBot Windows installer from the local build output, without
    downloading or extracting a previous official release.

.DESCRIPTION
    The script assembles a payload directory that mirrors the layout of the
    original installer: built binaries at the root, language files under
    langsrc\, plugins under Plugins\, data files under trivia\, sam_scripts\,
    DJ Package\, etc. It generates the language database, downloads current
    versions of bundled third-party tools, and then compiles the NSIS installer.

    No previous RadioBot release is downloaded. Optional project-specific extras
    (trivia databases, SAM scripts, DJ Package files, license texts, client.pem
    and client.exe) can be provided by placing them in windows-oem\extras with
    the same directory layout the installer expects.
#>

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$OutputDir    = "$RepoDir\v5\Output"
$PayloadDir   = "$RepoDir\payload"
$ArtifactsDir = "$RepoDir\artifacts"
$ExtrasDir    = "$OEM\extras"
$SevenZip     = "C:\Program Files\7-Zip\7z.exe"
$MakeNsis     = "C:\Program Files (x86)\NSIS\makensis.exe"
$NsisFile     = "$OEM\RadioBot.nsi"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$ts $msg"
}

function Invoke-WithRetry {
    param([scriptblock]$Command, [int]$MaxAttempts = 3)
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try {
            & $Command
            return
        } catch {
            Write-Log "Attempt $i of $MaxAttempts failed: $_"
            if ($i -eq $MaxAttempts) { throw }
            Start-Sleep -Seconds 5
        }
    }
}

function Ensure-Tools() {
    if (-not (Test-Path $MakeNsis)) {
        Write-Log "NSIS not found, installing via Chocolatey..."
        $choco = "C:\ProgramData\chocolatey\bin\choco.exe"
        & $choco install -y nsis --no-progress
        if ($LASTEXITCODE -ne 0) { throw "Failed to install NSIS" }
    }
    if (-not (Test-Path $SevenZip)) {
        Write-Log "7-Zip not found, installing via Chocolatey..."
        $choco = "C:\ProgramData\chocolatey\bin\choco.exe"
        & $choco install -y 7zip --no-progress
        if ($LASTEXITCODE -ne 0) { throw "Failed to install 7-Zip" }
    }
}

function Find-LangDump() {
    $candidates = @(
        "$OutputDir\langdump.exe",
        "$RepoDir\Common\langdump\Release\langdump.exe",
        "$RepoDir\Common\langdump\Debug\langdump.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

function Invoke-LangDump() {
    $langDump = Find-LangDump
    if (-not $langDump) {
        Write-Log "langdump.exe not found; language database will be missing."
        return
    }
    Write-Log "Generating language database with $langDump..."
    New-Item -ItemType Directory -Force -Path "$PayloadDir\langsrc\en_US" | Out-Null
    New-Item -ItemType Directory -Force -Path "$PayloadDir\langsrc\el_GR" | Out-Null
    Push-Location $PayloadDir
    try {
        & $langDump -d "$RepoDir" -o "$PayloadDir\langsrc\en_US\lang.ldb"
        if ($LASTEXITCODE -ne 0) { throw "langdump failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
    if (Test-Path "$PayloadDir\langsrc\en_US\lang.ldb") {
        Write-Log "Generated $PayloadDir\langsrc\en_US\lang.ldb"
    }
}

function Install-FileFromUrl() {
    param(
        [string]$Name,
        [string]$Url,
        [string]$Destination
    )
    Write-Log "Downloading $Name from $Url..."
    $tempFile = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
    try {
        Invoke-WebRequest -Uri $Url -OutFile $tempFile -UseBasicParsing -UserAgent "Mozilla/5.0" -MaximumRedirection 5
        if (-not (Test-Path $tempFile)) { throw "Downloaded file not found" }
        Copy-Item $tempFile (Join-Path $PayloadDir $Destination) -Force
        Write-Log "Installed $Name -> $Destination"
    } finally {
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
    }
}

function Install-FilesFromZip() {
    param(
        [string]$Name,
        [string]$Url,
        [array]$Files
    )
    Write-Log "Downloading $Name from $Url..."
    $tempFile = Join-Path $env:TEMP "$Name.zip"
    $tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
    try {
        Invoke-WebRequest -Uri $Url -OutFile $tempFile -UseBasicParsing -UserAgent "Mozilla/5.0" -MaximumRedirection 5
        if (-not (Test-Path $tempFile)) { throw "Downloaded file not found" }
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
        & $SevenZip x "$tempFile" -o"$tempDir" -y
        if ($LASTEXITCODE -ne 0) { throw "7-Zip extraction failed for $Name" }

        foreach ($f in $Files) {
            $pattern = '*\' + $f.InternalPath
            $found = Get-ChildItem -Path $tempDir -Recurse -File | Where-Object { $_.FullName -like $pattern } | Select-Object -First 1
            if (-not $found) {
                Write-Log "Could not locate $($f.InternalPath) in $Name archive; skipping."
                continue
            }
            Copy-Item $found.FullName (Join-Path $PayloadDir $f.Destination) -Force
            Write-Log "Installed $Name file -> $($f.Destination)"
        }
    } finally {
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Install-ExternalTools() {
    try {
        Invoke-WithRetry -Command {
            Install-FileFromUrl -Name 'yt-dlp' -Url 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_x86.exe' -Destination 'yt-dlp.exe'
        }
    } catch {
        Write-Log "WARNING: Could not install yt-dlp: $_"
    }

    try {
        Invoke-WithRetry -Command {
            Install-FilesFromZip -Name 'ffmpeg' -Url 'https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win32-gpl.zip' -Files @(
                @{ InternalPath = 'bin\ffmpeg.exe'; Destination = 'ffmpeg.exe' },
                @{ InternalPath = 'bin\ffprobe.exe'; Destination = 'ffprobe.exe' }
            )
        }
    } catch {
        Write-Log "WARNING: Could not install ffmpeg/ffprobe: $_"
    }

    # Official qstat Windows binary from SourceForge. SourceForge redirects to a
    # mirror; the /download suffix triggers the redirect.
    try {
        Invoke-WithRetry -Command {
            Install-FilesFromZip -Name 'qstat' -Url 'https://sourceforge.net/projects/qstat/files/qstat-2.11-win32.zip/download' -Files @(
                @{ InternalPath = 'win32\qstat.exe'; Destination = 'qstat.exe' }
            )
        }
    } catch {
        Write-Log "WARNING: Could not install qstat: $_"
    }
}

function Copy-OptionalExtras() {
    if (-not (Test-Path $ExtrasDir)) { return }
    Write-Log "Copying project extras from $ExtrasDir..."
    & C:\Windows\System32\robocopy.exe "$ExtrasDir" "$PayloadDir" /E /COPY:DAT /MT:4 /R:2 /W:2 /NDL /NFL
    if ($LASTEXITCODE -ge 8) { throw "robocopy extras failed" }
}

function Copy-Licenses() {
    # The build output may already contain a Licenses folder from vcpkg/runtime
    # artifacts. If not, create an empty one; extras can fill it in.
    if (Test-Path "$OutputDir\Licenses") {
        Write-Log "Copying Licenses from build output..."
        & C:\Windows\System32\robocopy.exe "$OutputDir\Licenses" "$PayloadDir\Licenses" /E /COPY:DAT /MT:4 /R:2 /W:2 /NDL /NFL
        if ($LASTEXITCODE -ge 8) { Write-Log "WARNING: robocopy Licenses from build output failed" }
    }
    if (-not (Test-Path "$PayloadDir\Licenses")) {
        New-Item -ItemType Directory -Force -Path "$PayloadDir\Licenses" | Out-Null
    }
}

function Build-Payload() {
    # Start with the freshly built output tree.
    if (Test-Path $PayloadDir) {
        Write-Log "Removing stale payload directory $PayloadDir..."
        Remove-Item $PayloadDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $PayloadDir | Out-Null

    Write-Log "Copying build output from $OutputDir..."
    if (-not (Test-Path $OutputDir)) { throw "Build output not found at $OutputDir" }
    & C:\Windows\System32\robocopy.exe "$OutputDir" "$PayloadDir" /E /COPY:DAT /MT:4 /R:2 /W:2 /NDL /NFL
    if ($LASTEXITCODE -ge 8) { throw "robocopy build output failed" }
    Write-Output "__PROGRESS__ 1 5"

    # Copy runtime config and icon files.
    $IrcbotText = "$RepoDir\ircbot.text"
    $IrcbotPem  = "$RepoDir\ircbot.pem"
    $ClientPem  = "$RepoDir\Client3\client.pem"
    if (Test-Path $IrcbotText) { Copy-Item $IrcbotText $PayloadDir -Force }
    if (Test-Path $IrcbotPem)  { Copy-Item $IrcbotPem  $PayloadDir -Force }
    if (Test-Path $ClientPem)  { Copy-Item $ClientPem  $PayloadDir -Force }

    $SrcIcon = "$RepoDir\client\ca.ico"
    if (Test-Path $SrcIcon) {
        Copy-Item $SrcIcon "$PayloadDir\shoutirc.ico" -Force
    }

    # Generate language database.
    Invoke-LangDump
    Write-Output "__PROGRESS__ 2 5"

    # Download current versions of bundled third-party tools.
    Install-ExternalTools
    Write-Output "__PROGRESS__ 3 5"

    # Create the directory layout found in the original installer.
    @('DJ Package', 'Licenses', 'langsrc\el_GR', 'sam_scripts', 'trivia') | ForEach-Object {
        New-Item -ItemType Directory -Force -Path (Join-Path $PayloadDir $_) | Out-Null
    }

    # DJ Package gets its own copy of the icon, matching the original layout.
    if (Test-Path "$PayloadDir\shoutirc.ico") {
        Copy-Item "$PayloadDir\shoutirc.ico" "$PayloadDir\DJ Package\shoutirc.ico" -Force
    }

    Copy-Licenses

    # Add helper batch file from the repo.
    $UpdateLang = "$OEM\update-lang.bat"
    if (Test-Path $UpdateLang) {
        Copy-Item $UpdateLang "$PayloadDir\update-lang.bat" -Force
    } elseif (Test-Path "$RepoDir\windows-oem\update-lang.bat") {
        Copy-Item "$RepoDir\windows-oem\update-lang.bat" "$PayloadDir\update-lang.bat" -Force
    }

    # Extras from windows-oem\extras are overlaid last so they can provide any
    # project-specific files the build process cannot produce (trivia, SAM
    # scripts, DJ Package files, client.pem, client.exe, license texts, etc.).
    Copy-OptionalExtras
    Write-Output "__PROGRESS__ 4 5"
}

function Build-Installer() {
    if ([string]::IsNullOrWhiteSpace($OutFile)) {
        $OutFile = "$ArtifactsDir\RadioBot-setup.exe"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $OutFile -Parent) | Out-Null

    if (-not (Test-Path $NsisFile)) {
        $RepoNsi = "$RepoDir\windows-oem\RadioBot.nsi"
        if (Test-Path $RepoNsi) {
            $NsisFile = $RepoNsi
        } else {
            throw "RadioBot.nsi not found"
        }
    }

    Write-Log "Building installer with makensis..."
    & $MakeNsis "/DPAYLOADDIR=$PayloadDir" "/DOUTFILE=$OutFile" $NsisFile
    if ($LASTEXITCODE -ne 0) { throw "makensis failed" }

    if (Test-Path $OutFile) {
        Write-Log "Installer built: $OutFile"
        $size = (Get-Item $OutFile).Length / 1MB
        Write-Log "Size: $size MB"
    } else {
        throw "Installer output not found"
    }
    Write-Output "__PROGRESS__ 5 5"
}

# --- Main ---
Write-Output "__PROGRESS_TOTAL__ 5"
Ensure-Tools
Build-Payload
Build-Installer
Write-Output "__PROGRESS_DONE__"
