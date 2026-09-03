[CmdletBinding()]
param(
    [string]$OutFile = "",
    [string]$RepoDir = "C:\RadioBot",
    [string]$OEM = "C:\OEM"
)

#Requires -Version 5.1

<#
.SYNOPSIS
    Wrapper that builds a RadioBot Windows installer from the local build output.

.DESCRIPTION
    This script delegates to windows-oem\package-standalone.ps1, which assembles
    the payload from the build tree, generates the language database, downloads
    current third-party tools, and compiles the NSIS installer. No previous
    RadioBot release is downloaded.
#>

$ErrorActionPreference = "Stop"

$standalone = "$OEM\package-standalone.ps1"
if (-not (Test-Path $standalone)) {
    $standalone = "$RepoDir\windows-oem\package-standalone.ps1"
}
if (-not (Test-Path $standalone)) { throw "package-standalone.ps1 not found" }

& $standalone -OutFile $OutFile -RepoDir $RepoDir -OEM $OEM
