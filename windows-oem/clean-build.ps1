#Requires -Version 5.1

<#
.SYNOPSIS
    Cleans RadioBot Windows build artifacts.

.DESCRIPTION
    Removes the build output tree, installer payload, built installers, and
    restores the original solution file so the next build is truly clean.
    Run this from inside the VM (or any Windows build environment) before a
    fresh build.
#>

$ErrorActionPreference = "Stop"

$RepoDir = "C:\RadioBot"

$paths = @(
    "$RepoDir\v5\Output",
    "$RepoDir\payload-official",
    "$RepoDir\artifacts",
    "$RepoDir\ConfigWizard\Release",
    "$RepoDir\ConfigWizard\Debug",
    "$RepoDir\RadioBot-setup.exe",
    "$RepoDir\RadioBot-setup-new.exe",
    "$RepoDir\RadioBot-setup-new2.exe",
    "$RepoDir\RadioBot-setup-new3.exe",
    "$RepoDir\RadioBot-setup-test.exe",
    "$RepoDir\official-orig",
    "$RepoDir\official-orig2"
)

foreach ($p in $paths) {
    if (Test-Path $p) {
        Write-Host "Removing $p ..."
        Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Restore original solution if the orig file is present.
$sln = "$RepoDir\IRCBot\IRCBot.sln"
$slnOrig = "$RepoDir\IRCBot\IRCBot.sln.orig"
if (Test-Path $slnOrig) {
    Copy-Item -Path $slnOrig -Destination $sln -Force
    Write-Host "Restored original $sln"
}

Write-Host "Clean complete."
