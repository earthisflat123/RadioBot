#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Console-based native Windows build wizard for RadioBot.

.DESCRIPTION
    Builds RadioBot on a real Windows machine without Docker, Samba, or SSH.
    It can clone the repo, set up the build environment, build the project,
    and package the installer from a simple console menu.

.PARAMETER RepoDir
    Path to an existing RadioBot clone. If not supplied, the wizard will ask.

.EXAMPLE
    .\build-windows-native-console.ps1
    .\build-windows-native-console.ps1 -RepoDir C:\RadioBot
#>

param(
    [string]$RepoDir = "",
    [string]$Branch = "master"
)

$ErrorActionPreference = "Stop"

Import-Module -Force "$PSScriptRoot\windows-oem\native-build-core.psm1"

if (-not (Test-Administrator)) {
    throw "This script must be run as Administrator."
}

Initialize-NativeBuildLog

function Read-RepoSource {
    while ($true) {
        Write-Host ""
        Write-Host "Select the repository to clone/build:"
        Write-Host "  1) earthisflat123/RadioBot (fork with Windows build fixes)"
        Write-Host "  2) DriftSolutions/RadioBot (upstream)"
        Write-Host "  3) Other (enter a custom git URL)"
        Write-Host "  4) I already have a local clone, skip cloning"
        $choice = Read-Host "Enter choice [1-4]"

        switch ($choice) {
            '1' { return 'Fork' }
            '2' { return 'Upstream' }
            '3' {
                $url = Read-Host "Enter the git URL"
                $script:CustomUrl = $url
                return 'Other'
            }
            '4' { return 'Local' }
            default { Write-Host "Invalid choice, try again." }
        }
    }
}

function Read-ClonePath {
    while ($true) {
        $path = Read-Host "Enter the folder to clone/build into [C:\RadioBot]"
        if ([string]::IsNullOrWhiteSpace($path)) { $path = 'C:\RadioBot' }
        if (Test-Path $path) { return $path }
        try {
            New-Item -ItemType Directory -Force -Path $path | Out-Null
            return $path
        } catch {
            Write-Host "Could not create $path : $_"
        }
    }
}

$CustomUrl = ''

if ([string]::IsNullOrWhiteSpace($RepoDir)) {
    $source = Read-RepoSource
    if ($source -ne 'Local') {
        $RepoDir = Read-ClonePath
        $url = Get-RepositoryUrl -Choice $source -CustomUrl $CustomUrl

        $branch = if ([string]::IsNullOrWhiteSpace($Branch)) { 'master' } else { $Branch }
        if (Test-GitAvailable) {
            Start-RepoClone -Url $url -RepoDir $RepoDir -Branch $branch
        } else {
            Write-BuildLog "Git not found; downloading repository as a ZIP archive."
            Expand-RepoFromZip -Url $url -RepoDir $RepoDir -Branch $branch
        }
    } else {
        $RepoDir = Read-ClonePath
        if (-not (Test-Path "$RepoDir\vcpkg.json")) {
            throw "No RadioBot repo detected at $RepoDir (vcpkg.json not found)."
        }
    }
}

$depsArchive = Join-Path $RepoDir 'radiobot-windows-deps.7z'
$useArchive = $false
if (Test-Path $depsArchive) {
    $answer = Read-Host "Found radiobot-windows-deps.7z. Use it to skip long dependency builds? [Y/n]"
    if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^[Yy]') { $useArchive = $true }
}

$OEM = Join-Path $RepoDir 'windows-oem'
$steps = Get-StepCommands -RepoDir $RepoDir -UseDepsArchive:$useArchive

while ($true) {
    Write-Host ""
    Write-Host "Current repo: $RepoDir"
    Write-Host ""
    Write-Host "What do you want to do?"
    Write-Host "  1) Setup build environment"
    Write-Host "  2) Build RadioBot"
    Write-Host "  3) Package installer"
    Write-Host "  4) Run everything (setup + build + package)"
    Write-Host "  5) List built binaries"
    Write-Host "  6) Exit"
    $action = Read-Host "Enter choice [1-6]"

    switch ($action) {
        '1' { $run = @($steps[0]) }
        '2' { $run = @($steps[1]) }
        '3' { $run = @($steps[2]) }
        '4' { $run = $steps }
        '5' {
            $exes = Get-BuiltBinaries -RepoDir $RepoDir
            if ($exes.Count -eq 0) { Write-Host "No built binaries found in $RepoDir\v5\Output" }
            else { $exes | ForEach-Object { Write-Host $_ } }
            continue
        }
        '6' { exit 0 }
        default { Write-Host "Invalid choice."; continue }
    }

    foreach ($step in $run) {
        Write-BuildLog "=== Starting step: $($step.Name) ==="
        Write-BuildLog $step.LogHint

        $proc = Start-Process -FilePath $step.FileName -ArgumentList $step.Arguments -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "Step '$($step.Name)' failed with exit code $($proc.ExitCode). Check $script:LogFile"
        }

        Write-BuildLog "=== Step '$($step.Name)' finished ==="
    }

    $installer = Get-InstallerPath -RepoDir $RepoDir
    if ($installer) {
        Write-BuildLog "Installer is ready: $installer"
    }
}
