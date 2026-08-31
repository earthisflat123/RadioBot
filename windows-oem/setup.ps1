#Requires -RunAsAdministrator

param(
    [string]$RepoSrc = "",
    [string]$RepoDst = "C:\RadioBot",
    [switch]$UseDepsArchive
)

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# NOTE: C:\OEM is copied into the Windows install image by dockur/windows,
# it is not a live share. Write the detailed log to the host shared drive so
# it can be tailed from the host in real time.

$OEM = "C:\OEM"
$TempDir = "C:\Temp"
$LogFile = "$TempDir\setup.log"
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

function Write-Log($Message) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$ts $Message"
    Write-Output $line
    Add-Content -Path $LogFile -Value $line
}

function Find-AndMap-SharedDrive {
    # dockur/windows exposes the host bind mount as a Samba share at
    # \\host.lan\Data. It is sometimes exposed as C:\Users\builder\Desktop\Shared
    # or as a drive letter Z:. We prefer Z: for consistency, but we only trust a
    # path if it actually contains the RadioBot source (look for vcpkg.json).
    $shareRoot = $null

    # Try the Desktop/Shared shortcut first if it has the source.
    $desktopShared = "C:\Users\builder\Desktop\Shared"
    if (Test-Path "$desktopShared\vcpkg.json") {
        $shareRoot = $desktopShared
        Write-Log "Found shared source at $desktopShared"
    }

    # If Z: is already mapped and has the source, use it.
    if (-not $shareRoot -and (Test-Path "Z:\vcpkg.json")) {
        $shareRoot = "Z:\"
        Write-Log "Found shared source at Z:\"
    }

    # Map \\host.lan\Data to Z: and verify it has the source.
    if (-not $shareRoot) {
        Write-Log "Trying to map Z: to \\host.lan\Data..."
        try {
            & cmd /c "net use Z: \\host.lan\Data /y" 2>&1 | ForEach-Object { Write-Log "net use: $_" }
            if (Test-Path "Z:\vcpkg.json") {
                $shareRoot = "Z:\"
                Write-Log "Mapped Z: to host share successfully"
            }
        } catch {
            Write-Log "Could not map Z: drive: $_"
        }
    }

    # Last resort: use the UNC path directly if it has the source.
    $unc = "\\host.lan\Data"
    if (-not $shareRoot -and (Test-Path "$unc\vcpkg.json")) {
        $shareRoot = $unc
        Write-Log "Found shared source at $unc"
    }

    return $shareRoot
}

# Resolve the host shared folder early. Everything else (source copy, vcpkg
# manifest, and the log) depends on having a working share.
if ([string]::IsNullOrEmpty($RepoSrc) -or -not (Test-Path $RepoSrc)) {
    $found = Find-AndMap-SharedDrive
    if ($found) {
        $RepoSrc = $found
    } else {
        throw "Could not locate the host shared folder. The build cannot continue."
    }
}

# Make sure the share actually contains the repo source.
$manifestRoot = $RepoSrc.TrimEnd('\')
if (-not (Test-Path "$manifestRoot\vcpkg.json")) {
    throw "vcpkg.json not found in the repo source at $manifestRoot. The host share may be empty or mapped to the wrong path."
}

# Switch the log to the shared drive so it is visible on the host.
$LogFile = "$RepoSrc\setup-radiobot.log"
Write-Log "=== Starting RadioBot Windows build environment setup ==="
Write-Log "Using host shared source: $RepoSrc"

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

# Archive use is opt-in. Default is a fresh install from scratch. Opt-in can be
# triggered by passing -UseDepsArchive, setting USE_RADIOSBOT_DEPS_ARCHIVE=1, or
# simply making an archive available: setup.ps1 will auto-detect it.
if (-not $UseDepsArchive -and $env:USE_RADIOSBOT_DEPS_ARCHIVE -eq '1') {
    $UseDepsArchive = $true
}

Write-Log "=== Starting RadioBot Windows build environment setup ==="
if ($UseDepsArchive) {
    Write-Log "Archive restore requested: dependencies will be extracted from radiobot-windows-deps.7z if found"
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
$LocalArchivePath = "$RepoSrc\radiobot-windows-deps.7z"
$OEMArchivePath = "$OEM\radiobot-windows-deps.7z"
$DownloadedArchivePath = "$TempDir\radiobot-windows-deps.7z"

function Find-DependencyArchive() {
    $ArchivePath = $null

    # 1. URL in the environment / config: download once and cache in C:\Temp
    $DepsUrl = $env:RADIOSBOT_DEPS_URL
    if ($DepsUrl) {
        Write-Log "Dependency archive URL configured: $DepsUrl"
        if (Test-Path $DownloadedArchivePath) {
            Write-Log "Using previously downloaded archive at $DownloadedArchivePath"
            $ArchivePath = $DownloadedArchivePath
        } else {
            Write-Log "Downloading dependency archive..."
            Invoke-WithRetry { Invoke-WebRequest -Uri $DepsUrl -OutFile $DownloadedArchivePath -UseBasicParsing }
            if (Test-Path $DownloadedArchivePath) {
                $ArchivePath = $DownloadedArchivePath
            }
        }
    }

    # 2. Archive in the repo root / shared drive
    if (-not $ArchivePath -and (Test-Path $LocalArchivePath)) {
        $ArchivePath = $LocalArchivePath
    }

    # 3. Archive staged in C:\OEM
    if (-not $ArchivePath -and (Test-Path $OEMArchivePath)) {
        $ArchivePath = $OEMArchivePath
    }

    return $ArchivePath
}

$ArchivePath = Find-DependencyArchive
if ($UseDepsArchive) {
    if (-not $ArchivePath) {
        throw "Dependency archive was requested but not found. Provide it at $LocalArchivePath, $OEMArchivePath, or set `$env:RADIOSBOT_DEPS_URL`."
    }
} elseif ($ArchivePath) {
    Write-Log "Found dependency archive at $ArchivePath; using it automatically (set -UseDepsArchive explicitly to require one)."
    $UseDepsArchive = $true
}

if ($UseDepsArchive) {
    if (-not $ArchivePath) { throw "Dependency archive path is empty; this should not happen." }
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

    # Use a manifest with a builtin-baseline so package versions are pinned and
    # reproducible across builds. The manifest lives in the repo source tree.
    $manifestRoot = $RepoSrc.TrimEnd('\')
    if (-not (Test-Path "$manifestRoot\vcpkg.json")) {
        throw "vcpkg.json not found in the repo source at $manifestRoot. It is required for pinned package versions."
    }

    # Enable vcpkg binary caching. A local cache under the vcpkg root speeds up
    # repeated installs in the same VM; a cache on the shared drive (Z:) survives
    # VM recreation and is used if it is mounted.
    $binarySources = "clear;files,$vcpkgDir\cache,readwrite"
    if (Test-Path "Z:\") {
        $binarySources += ";files,Z:\vcpkg-cache,readwrite"
    }
    $env:VCPKG_BINARY_SOURCES = $binarySources
    Write-Log "vcpkg binary sources: $binarySources"

    Write-Log "Installing vcpkg packages for $triplet from manifest (this can take a long time the first time)..."
    # Append the full vcpkg output to the log so slow build failures can be
    # diagnosed from the host. Using cmd /c with >> keeps the exit code intact.
    $vcpkgCmd = "`"$vcpkgDir\vcpkg.exe`" install --triplet $triplet --x-manifest-root `"$manifestRoot`" --x-install-root `"$vcpkgDir\installed`" >> `"$LogFile`" 2>&1"
    $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $vcpkgCmd -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) { throw "vcpkg install failed with exit code $($proc.ExitCode)" }
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
        /XD "windows-storage" "windows-oem" ".git" "vcpkg-cache" "artifacts" ".worktree" `
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
