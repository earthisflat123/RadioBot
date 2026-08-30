#Requires -RunAsAdministrator

param(
    [string]$RepoSrc = "C:\Users\builder\Desktop\Shared",
    [string]$RepoDst = "C:\RadioBot",
    [switch]$UseDepsArchive
)

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# NOTE: Do not use Start-Transcript here. The install.bat wrapper already
# redirects all output to C:\OEM\setup.log, and using Start-Transcript on the
# same file while cmd.exe holds it open for redirection causes a file-lock
# error on some runs.

# Temp directory and log file (write here to avoid file-lock with install.bat)
$TempDir = "C:\Temp"
$LogFile = "$TempDir\setup.log"
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

function Write-Log($Message) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$ts $Message"
    Write-Output $line
    Add-Content -Path $LogFile -Value $line
}

function Invoke-WithRetry {
    param([scriptblock]$Command, [int]$MaxAttempts = 3)
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try {
            & $Command
            return
        } catch {
            Write-Log "Attempt $i failed: $_"
            if ($i -eq $MaxAttempts) { throw }
            Start-Sleep -Seconds 10
        }
    }
}

function Install-OpenSSHServer() {
    try {
        $cap = Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
        if ($cap.State -ne 'Installed') {
            Write-Log "Installing OpenSSH server..."
            Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
        } else {
            Write-Log "OpenSSH server already installed."
        }
        $sshd = Get-Service -Name sshd -ErrorAction SilentlyContinue
        if (-not $sshd) {
            Write-Log "sshd service not found after install."
            return
        }
        Start-Service sshd -ErrorAction SilentlyContinue
        Set-Service -Name sshd -StartupType Automatic
        if (-not (Get-NetFirewallRule -Name "OpenSSH-Server" -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -Name "OpenSSH-Server" -DisplayName "OpenSSH Server" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
        }
        Write-Log "OpenSSH server is running."
    } catch {
        Write-Log "OpenSSH setup failed: $_"
    }
}

function Add-HostSSHPublicKey($OemDir) {
    $sshDir = "C:\Users\builder\.ssh"
    $authKeys = "$sshDir\authorized_keys"
    $pubKey = "$OemDir\id_rsa.pub"
    if (-not (Test-Path $pubKey)) { return }
    Write-Log "Adding host SSH public key..."
    New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
    Copy-Item $pubKey $authKeys -Force
    try {
        $acl = Get-Acl $sshDir
        $acl.SetAccessRuleProtection($true, $false)
        $acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("builder", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
        # sshd (running as SYSTEM) must be able to read the key, and administrators may need access.
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("NT AUTHORITY\SYSTEM", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Administrators", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")))
        Set-Acl $sshDir $acl
        Set-Acl $authKeys (Get-Acl $sshDir)
    } catch {
        Write-Log "Could not tighten SSH ACLs: $_"
    }

    # Windows OpenSSH defaults to __PROGRAMDATA__/ssh/administrators_authorized_keys
    # for members of the administrators group, so the key must also be there.
    $adminKeys = "$env:ProgramData\ssh\administrators_authorized_keys"
    try {
        Copy-Item $pubKey $adminKeys -Force
        $adminAcl = Get-Acl $adminKeys
        $adminAcl.SetAccessRuleProtection($true, $false)
        $adminAcl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("NT AUTHORITY\SYSTEM", "FullControl", "Allow")))
        $adminAcl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Administrators", "ReadAndExecute", "Allow")))
        Set-Acl $adminKeys $adminAcl
        Write-Log "Updated administrators authorized keys."
    } catch {
        Write-Log "Could not update administrators authorized keys: $_"
    }
}

# Archive use is strictly opt-in. Default is a fresh install from scratch.
# Opt-in can be triggered by:
# - Passing -UseDepsArchive to this script
# - Setting the environment variable USE_RADIOSBOT_DEPS_ARCHIVE=1
# - Placing a file named USE_RADIOSBOT_DEPS_ARCHIVE in C:\OEM or in the root of the shared drive (RepoSrc)
if (-not $UseDepsArchive) {
    if ($env:USE_RADIOSBOT_DEPS_ARCHIVE -eq '1') {
        $UseDepsArchive = $true
    }
    elseif (Test-Path "C:\OEM\USE_RADIOSBOT_DEPS_ARCHIVE") {
        $UseDepsArchive = $true
    }
    elseif (Test-Path "$RepoSrc\USE_RADIOSBOT_DEPS_ARCHIVE") {
        $UseDepsArchive = $true
    }
}

Write-Log "=== Starting RadioBot Windows build environment setup ==="
if ($UseDepsArchive) {
    Write-Log "Archive restore mode: dependencies will be extracted from radiobot-windows-deps.7z"
} else {
    Write-Log "Fresh install mode: vcpkg packages and source dependencies will be built from scratch"
}

# Enable headless access as early as possible so long-running installs can be
# inspected/debugged from the host without waiting for setup to finish.
Write-Log "Enabling OpenSSH early..."
Install-OpenSSHServer
Add-HostSSHPublicKey -OemDir "C:\OEM"

# 1. Install Chocolatey if missing
$choco = "C:\ProgramData\chocolatey\bin\choco.exe"
if (-not (Test-Path $choco)) {
    Write-Log "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
    $choco = "C:\ProgramData\chocolatey\bin\choco.exe"
}

# 2. Core build tools
Write-Log "Installing git, 7-Zip, CMake, Python..."
& $choco install -y git 7zip cmake python3 --no-progress

# 3. Visual Studio Build Tools 2022 (v143 toolset)
Write-Log "Downloading Visual Studio Build Tools..."
$vsbt = "$TempDir\vs_buildtools.exe"
Invoke-WithRetry { Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vs_buildtools.exe" -OutFile $vsbt }

Write-Log "Installing Visual Studio Build Tools (this may take 15-30 minutes)..."
$vsArgs = @(
    "--quiet", "--wait", "--norestart",
    "--add", "Microsoft.VisualStudio.Workload.MSBuildTools",
    "--add", "Microsoft.VisualStudio.Workload.VCTools",
    "--add", "Microsoft.VisualStudio.Component.Windows10SDK.19041",
    "--add", "Microsoft.VisualStudio.Component.VC.ATL",
    "--add", "Microsoft.VisualStudio.Component.VC.ATLMFC",
    "--includeRecommended"
)
Start-Process -FilePath $vsbt -ArgumentList $vsArgs -NoNewWindow -Wait

$VsMsBuild = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
$maxWait = 45 * 60
$elapsed = 0
while (-not (Test-Path $VsMsBuild) -and $elapsed -lt $maxWait) {
    $installerRunning = Get-Process | Where-Object { $_.Name -match 'vs_setup_bootstrapper|setup|vs_installer' } | Measure-Object
    if ($installerRunning.Count -eq 0 -and -not (Test-Path $VsMsBuild)) {
        throw "Visual Studio Build Tools installer finished but MSBuild was not found."
    }
    Start-Sleep -Seconds 5
    $elapsed += 5
}
if (-not (Test-Path $VsMsBuild)) { throw "Timed out waiting for Visual Studio Build Tools to install." }
Write-Log "Visual Studio Build Tools installed."

# Common paths used by both dependency modes
$OEM = "C:\OEM"
$deps = "C:\deps"

# 4-7. vcpkg + dependencies (fresh) or restore from archive (opt-in)
$vcpkgDir = "C:\vcpkg"
if ($UseDepsArchive) {
    $ArchivePath = "$RepoSrc\radiobot-windows-deps.7z"
    if (-not (Test-Path $ArchivePath)) {
        throw "Dependency archive not found at $ArchivePath. Remove the opt-in marker or environment variable to build from scratch."
    }
    Write-Log "Extracting dependency archive $ArchivePath to C:\..."
    $SevenZip = "C:\Program Files\7-Zip\7z.exe"
    if (-not (Test-Path $SevenZip)) {
        # Fall back to the 7-Zip install that Chocolatey just put on the PATH
        $SevenZip = "7z"
    }
    & $SevenZip x $ArchivePath -oC:\ -y
    if ($LASTEXITCODE -ne 0) { throw "Dependency archive extraction failed with exit code $LASTEXITCODE." }
    if (-not (Test-Path $vcpkgDir)) {
        throw "vcpkg directory not found after archive extraction."
    }
    if (-not (Test-Path "C:\deps")) {
        throw "deps directory not found after archive extraction."
    }
    if (-not (Test-Path "C:\deps\lib\libfaac.lib")) {
        throw "libfaac not found after archive extraction; archive may be incomplete."
    }
    if (-not (Test-Path "$vcpkgDir\installed\x86-windows")) {
        throw "vcpkg installed tree not found after archive extraction."
    }
    Write-Log "Dependency archive restored."
} else {
    # 4. vcpkg
    if (-not (Test-Path $vcpkgDir)) {
        Write-Log "Cloning vcpkg..."
        & "C:\Program Files\Git\bin\git.exe" clone https://github.com/Microsoft/vcpkg.git $vcpkgDir
        & "$vcpkgDir\bootstrap-vcpkg.bat"
    } else {
        Write-Log "vcpkg already present."
    }
    $env:Path = "$env:Path;$vcpkgDir"

    # 5. vcpkg packages (x86 to match the Win32 .vcxproj files)
    $triplet = "x86-windows"
    $packages = @(
        "openssl",
        "sqlite3",
        "libmysql",
        "zlib",
        "curl",
        "protobuf",
        "taglib",
        "libogg",
        "libvorbis",
        "libflac",
        "libsndfile",
        "mp3lame",
        "wxwidgets",
        "opus",
        "soxr",
        "faad2",
        "physfs",
        "pcre",
        "mosquitto",
        "ffmpeg",
        "muparser",
        "lua",
        "glib"
    )

    Write-Log "Installing vcpkg packages for $triplet (this can take a long time)..."
    & "$vcpkgDir\vcpkg.exe" install $packages --triplet $triplet
    Write-Log "vcpkg install finished."

    # 6. Stage vcpkg outputs into C:\deps
    @("include", "lib", "lib\ffmpeg", "lib\opus", "lib\wx", "bin", "drift") | ForEach-Object {
        New-Item -ItemType Directory -Force -Path (Join-Path $deps $_) | Out-Null
    }

    $installed = "$vcpkgDir\installed\$triplet"
    if (Test-Path $installed) {
        Copy-Item -Path "$installed\include\*" -Destination "$deps\include" -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item -Path "$installed\lib\*" -Destination "$deps\lib" -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item -Path "$installed\bin\*" -Destination "$deps\bin" -Recurse -Force -ErrorAction SilentlyContinue

        # vcpkg sometimes puts headers in package-specific sub-folders. Make sure
        # taglib toolkit headers are also reachable from the expected path.
        $taglibToolkit = "$deps\include\taglib\toolkit"
        if (Test-Path "$deps\include\taglib") {
            New-Item -ItemType Directory -Force -Path $taglibToolkit | Out-Null
            Get-ChildItem -Path "$deps\include\taglib" -Filter "*.h" | Where-Object {
                @("tstring.h","tbytevector.h","tbytevectorlist.h","tlist.h","tmap.h","trefcounter.h","unicode.h") -contains $_.Name
            } | ForEach-Object {
                Copy-Item $_.FullName $taglibToolkit -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Build the Drift Standard Library (DSL) required by RadioBot
    if (Test-Path "$OEM\build-dsl.ps1") {
        Write-Log "Building DSL (Drift Standard Library)..."
        & "$OEM\build-dsl.ps1"
        Write-Log "DSL build finished."
    } else {
        Write-Log "DSL build script not found at $OEM\build-dsl.ps1 - DSL will need to be built manually."
    }

    # 7. Prebuilt OpenSSL (the project README recommends slproweb.com)
    Write-Log "Installing prebuilt OpenSSL..."
    $sslUrl = "https://slproweb.com/download/Win32OpenSSL-3_4_1.exe"
    $sslInstaller = "$TempDir\Win32OpenSSL.exe"
    try {
        Invoke-WithRetry { Invoke-WebRequest -Uri $sslUrl -OutFile $sslInstaller }
        & $sslInstaller /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR="C:\deps\OpenSSL-Win32"
        if (Test-Path "C:\deps\OpenSSL-Win32") {
            Copy-Item -Path "C:\deps\OpenSSL-Win32\include\*" -Destination "$deps\include" -Recurse -Force -ErrorAction SilentlyContinue
            Copy-Item -Path "C:\deps\OpenSSL-Win32\lib\*" -Destination "$deps\lib" -Recurse -Force -ErrorAction SilentlyContinue
            Copy-Item -Path "C:\deps\OpenSSL-Win32\bin\*.dll" -Destination "$deps\bin" -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Log "OpenSSL install failed (will continue with vcpkg copy if present): $_"
    }
}

# 8. Copy RadioBot source from the shared folder (Z:) to C:\RadioBot
if (Test-Path $RepoSrc) {
    Write-Log "Copying RadioBot source from $RepoSrc to $RepoDst..."
    New-Item -ItemType Directory -Force -Path $RepoDst | Out-Null
    & "C:\Windows\System32\robocopy.exe" $RepoSrc $RepoDst /MIR `
        /XD "windows-storage" "windows-oem" ".git" `
        /Z /MT:4 /R:3 /W:5 /NDL /NFL
    Write-Log "Source copied."

    # Save a pristine copy of the solution for the build script to prune.
    $Sln = "$RepoDst\IRCBot\IRCBot.sln"
    if (Test-Path $Sln) {
        Copy-Item $Sln "$OEM\IRCBot.sln.orig" -Force
        Write-Log "Saved pristine IRCBot.sln to $OEM\IRCBot.sln.orig."
    }
} else {
    Write-Log "Shared source not found at $RepoSrc. You will need to copy the source manually."
}

# OpenSSH was enabled at the start of this script so long-running steps can be
# monitored via SSH. There is no further action needed here.

Write-Log "=== Setup complete ==="
Write-Log "Connect via:  ssh -p 2222 builder@localhost   (RDP: localhost:3389, web VNC: http://localhost:8006)"

# Copy the log to the shared drive so the host can see progress
$sharedLog = "$RepoSrc\windows-setup.log"
try {
    Copy-Item $LogFile $sharedLog -Force -ErrorAction SilentlyContinue
} catch {
    Write-Log "Could not copy setup log to shared drive: $_"
}
