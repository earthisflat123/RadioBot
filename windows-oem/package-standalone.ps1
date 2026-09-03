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
    The script creates a fresh payload directory from C:\RadioBot\v5\Output,
    generates the English language database with langdump, downloads current
    versions of the bundled third-party tools (ffmpeg, yt-dlp, qstat), creates
    the required data directories, and then compiles an NSIS installer.

    No previous RadioBot release is downloaded or referenced. Optional
    project-specific extras (trivia databases, sam_scripts, DJ Package, .pal
    files) can be provided by placing them in windows-oem\extras; otherwise
    empty directories are created for them.
#>

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$OutputDir   = "$RepoDir\v5\Output"
$PayloadDir  = "$RepoDir\payload"
$ArtifactsDir = "$RepoDir\artifacts"
$ExtrasDir   = "$OEM\extras"
$SevenZip    = "C:\Program Files\7-Zip\7z.exe"
$MakeNsis    = "C:\Program Files (x86)\NSIS\makensis.exe"
$NsisFile    = "$OEM\RadioBot.nsi"

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
        Write-Log "langdump.exe not found; skipping language database generation."
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

function Install-ToolFromUrl() {
    param(
        [string]$Name,
        [string]$Url,
        [string]$Destination,
        [string]$ZipInternalPath = $null
    )
    Write-Log "Downloading $Name from $Url..."
    $tempFile = Join-Path $env:TEMP ([System.IO.Path]::GetFileName($Url))
    $tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
    try {
        Invoke-WebRequest -Uri $Url -OutFile $tempFile -UseBasicParsing -UserAgent "Mozilla/5.0" -MaximumRedirection 5
        if (-not (Test-Path $tempFile)) { throw "Downloaded file not found" }
        if ($tempFile -match '\.(zip|7z)$') {
            New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
            & $SevenZip x "$tempFile" -o"$tempDir" -y
            if ($LASTEXITCODE -ne 0) { throw "7-Zip extraction failed for $Name" }
            $found = Get-ChildItem -Path $tempDir -Recurse -File -Filter (Split-Path -Leaf $Destination) | Select-Object -First 1
            if (-not $found) {
                if ($ZipInternalPath) {
                    $pattern = $ZipInternalPath -replace '^\*?\\', '' -replace '\\', '\'
                    $found = Get-ChildItem -Path $tempDir -Recurse -File | Where-Object { $_.FullName -like "*$pattern" } | Select-Object -First 1
                }
            }
            if (-not $found) {
                Write-Log "Could not locate $Destination in $tempFile; $Name may not be available in the package."
                return
            }
            Copy-Item $found.FullName (Join-Path $PayloadDir $Destination) -Force
            Write-Log "Installed $Name -> $Destination"
        } else {
            Copy-Item $tempFile (Join-Path $PayloadDir $Destination) -Force
            Write-Log "Installed $Name -> $Destination"
        }
    } finally {
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Install-ExternalTools() {
    $tools = @(
        @{ Name = 'yt-dlp'; Url = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_x86.exe'; Destination = 'yt-dlp.exe' },
        @{ Name = 'ffmpeg'; Url = 'https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win32-gpl.zip'; Destination = 'ffmpeg.exe'; ZipInternalPath = 'bin\ffmpeg.exe' },
        @{ Name = 'qstat'; Url = 'https://nyov.github.io/qstat-svn/downloads/qstat-2.11-win32.zip'; Destination = 'qstat.exe'; ZipInternalPath = 'win32\qstat.exe' }
    )
    foreach ($t in $tools) {
        try {
            Invoke-WithRetry -Command {
                Install-ToolFromUrl -Name $t.Name -Url $t.Url -Destination $t.Destination -ZipInternalPath $t.ZipInternalPath
            }
        } catch {
            Write-Log "WARNING: Could not install $($t.Name): $_"
        }
    }
}

function Copy-OptionalExtras() {
    if (-not (Test-Path $ExtrasDir)) { return }
    Write-Log "Copying project extras from $ExtrasDir..."
    & C:\Windows\System32\robocopy.exe "$ExtrasDir" "$PayloadDir" /E /COPY:DAT /MT:4 /R:2 /W:2 /NDL /NFL
    if ($LASTEXITCODE -ge 8) { throw "robocopy extras failed" }
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
    if (Test-Path $SrcIcon) { Copy-Item $SrcIcon "$PayloadDir\shoutirc.ico" -Force }

    # Generate or carry over the language database.
    Invoke-LangDump
    Write-Output "__PROGRESS__ 2 5"

    # Download current versions of third-party tools.
    Install-ExternalTools
    Write-Output "__PROGRESS__ 3 5"

    # Create required data directories; extras from windows-oem\extras are
    # overlaid on top if present.
    @('langsrc\el_GR', 'trivia', 'sam_scripts', 'DJ Package') | ForEach-Object {
        New-Item -ItemType Directory -Force -Path (Join-Path $PayloadDir $_) | Out-Null
    }
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
