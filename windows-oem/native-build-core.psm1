#Requires -Version 5.1
#Requires -RunAsAdministrator

# Shared core functions for the RadioBot native Windows build wizard.
# Used by both the console script (build-windows-native-console.ps1) and the
# WinForms GUI wizard (build-windows-native-wizard.ps1).

Add-Type -AssemblyName System.Windows.Forms

$script:LogFile = "C:\Temp\radiobot-native-build.log"

$script:DefaultRepositories = @{
    Upstream = 'https://github.com/DriftSolutions/RadioBot.git'
}

$script:DefaultBranch = 'master'

function Initialize-NativeBuildLog {
    New-Item -ItemType Directory -Force -Path (Split-Path $script:LogFile) | Out-Null
    if (Test-Path $script:LogFile) { Remove-Item $script:LogFile -Force }
}

function Write-BuildLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [System.Windows.Forms.TextBox]$TextBox = $null
    )

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$ts $Message"

    if ($TextBox -and (-not $TextBox.IsDisposed)) {
        $TextBox.Invoke([Action]{ $TextBox.AppendText("$line`r`n") })
    } else {
        Write-Host $line
    }

    [System.IO.File]::AppendAllText($script:LogFile, "$line`r`n")
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RepositoryUrl {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Upstream', 'Other')]
        [string]$Choice,

        [string]$CustomUrl = ''
    )

    if ($Choice -eq 'Other') {
        if ([string]::IsNullOrWhiteSpace($CustomUrl)) {
            throw 'A custom repository URL is required when Other is selected.'
        }
        return $CustomUrl
    }
    return $script:DefaultRepositories[$Choice]
}

function Test-GitAvailable {
    return [bool](Get-Command git -ErrorAction SilentlyContinue)
}

function Start-RepoClone {
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$RepoDir,

        [string]$Branch = $script:DefaultBranch
    )

    if (Test-Path "$RepoDir\.git") {
        Write-BuildLog "Repository already exists at $RepoDir; pulling latest $Branch..."
        & git -C $RepoDir fetch --depth 1 origin $Branch
        & git -C $RepoDir reset --hard "origin/$Branch"
        return
    }

    if (Test-Path $RepoDir) {
        throw "Directory $RepoDir already exists and is not a git repository. Remove it or pick a different path."
    }

    Write-BuildLog "Cloning $Url into $RepoDir..."
    & git clone --depth 1 --branch $Branch $Url $RepoDir
    if ($LASTEXITCODE -ne 0) { throw "git clone failed with exit code $LASTEXITCODE" }
}

function Expand-RepoFromZip {
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$RepoDir,

        [string]$Branch = $script:DefaultBranch
    )

    # This is a git-less fallback used by the standalone launcher when git is
    # not installed. It only works for public GitHub repos.
    $zipName = [System.IO.Path]::GetFileName($RepoDir) + ".zip"
    $zipPath = Join-Path $env:TEMP $zipName
    $zipUrl = $Url -replace '\.git$','' -replace '/$',''
    $zipUrl = "$zipUrl/archive/refs/heads/$Branch.zip"

    Write-BuildLog "Downloading $zipUrl..."
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing

    $extractRoot = Join-Path $env:TEMP ([System.IO.Path]::GetFileNameWithoutExtension($zipName))
    if (Test-Path $extractRoot) { Remove-Item $extractRoot -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractRoot -Force

    $unpacked = Get-ChildItem -Path $extractRoot -Directory | Select-Object -First 1
    if (-not $unpacked) { throw "No directory found after extracting archive." }

    if (Test-Path $RepoDir) { Remove-Item $RepoDir -Recurse -Force }
    Move-Item $unpacked.FullName $RepoDir
    Remove-Item $zipPath -Force
    Remove-Item $extractRoot -Force
}

function Get-StepCommands {
    param(
        [Parameter(Mandatory)]
        [string]$RepoDir,

        [switch]$UseDepsArchive
    )

    $OEM = Join-Path $RepoDir 'windows-oem'

    $setupArgs = @(
        '-ExecutionPolicy', 'Bypass',
        '-NoProfile',
        '-File', "`"$OEM\setup.ps1`"",
        '-Native',
        '-RepoSrc', "`"$RepoDir`"",
        '-RepoDst', "`"$RepoDir`"",
        '-OEM', "`"$OEM`""
    )
    if ($UseDepsArchive) { $setupArgs += '-UseDepsArchive' }

    # Start-Process -ArgumentList passes each element to CreateProcess, so
    # we strip the extra quotes we added for the string form.
    $setupArgList = @(
        '-ExecutionPolicy', 'Bypass',
        '-NoProfile',
        '-File', "$OEM\setup.ps1",
        '-Native',
        '-RepoSrc', $RepoDir,
        '-RepoDst', $RepoDir,
        '-OEM', $OEM
    )
    if ($UseDepsArchive) { $setupArgList += '-UseDepsArchive' }

    $buildArgs = @(
        '-ExecutionPolicy', 'Bypass',
        '-NoProfile',
        '-File', "`"$OEM\build-radiobot.ps1`"",
        '-RepoDir', "`"$RepoDir`"",
        '-OEM', "`"$OEM`""
    )

    $buildArgList = @(
        '-ExecutionPolicy', 'Bypass',
        '-NoProfile',
        '-File', "$OEM\build-radiobot.ps1",
        '-RepoDir', $RepoDir,
        '-OEM', $OEM
    )

    $outFile = Join-Path $RepoDir 'artifacts\RadioBot-setup.exe'
    $packageArgs = @(
        '-ExecutionPolicy', 'Bypass',
        '-NoProfile',
        '-File', "`"$OEM\package-installer.ps1`"",
        '-RepoDir', "`"$RepoDir`"",
        '-OEM', "`"$OEM`"",
        '-OutFile', "`"$outFile`""
    )

    $packageArgList = @(
        '-ExecutionPolicy', 'Bypass',
        '-NoProfile',
        '-File', "$OEM\package-installer.ps1",
        '-RepoDir', $RepoDir,
        '-OEM', $OEM,
        '-OutFile', $outFile
    )

    return @(
        @{
            Name        = 'Setup'
            FileName    = 'powershell.exe'
            Arguments   = $setupArgs -join ' '
            ArgumentList = $setupArgList
            LogHint     = 'Installing build tools and dependencies...'
        },
        @{
            Name        = 'Build'
            FileName    = 'powershell.exe'
            Arguments   = $buildArgs -join ' '
            ArgumentList = $buildArgList
            LogHint     = 'Building RadioBot with MSBuild...'
        },
        @{
            Name        = 'Package'
            FileName    = 'powershell.exe'
            Arguments   = $packageArgs -join ' '
            ArgumentList = $packageArgList
            LogHint     = 'Building RadioBot-setup.exe...'
        }
    )
}

function Get-BuiltBinaries {
    param(
        [Parameter(Mandatory)]
        [string]$RepoDir
    )

    $output = Join-Path $RepoDir 'v5\Output'
    if (-not (Test-Path $output)) { return @() }

    $candidates = @(
        'RadioBot.exe',
        'RadioBot_Shell.exe',
        'AutoDJ.exe',
        'Client3.exe',
        'Client5.exe',
        'ConfigWizard.exe',
        'MusicScanner.exe',
        'MusicScanner2.exe',
        'editusers.exe',
        'mp3sync.exe',
        'langdump.exe',
        'ibctl.exe'
    )

    $found = @()
    foreach ($c in $candidates) {
        $p = Join-Path $output $c
        if (Test-Path $p) { $found += $p }
    }
    return $found
}

function Get-InstallerPath {
    param(
        [Parameter(Mandatory)]
        [string]$RepoDir
    )
    $p = Join-Path $RepoDir 'artifacts\RadioBot-setup.exe'
    if (Test-Path $p) { return $p }
    return $null
}
