#Requires -Version 5.1

<#
.SYNOPSIS
    Triggers a RadioBot Windows build inside the VM.

.DESCRIPTION
    This thin wrapper is copied to C:\RadioBot by the VM setup. It invokes the
    full build script that lives in the mounted C:\OEM folder (windows-oem/).
#>

$ErrorActionPreference = "Stop"

$BuildScript = "C:\OEM\build-radiobot.ps1"

if (-not (Test-Path $BuildScript)) {
    throw "OEM build script not found at $BuildScript. Ensure the Windows VM setup has completed and windows-oem/build-radiobot.ps1 exists."
}

& $BuildScript
