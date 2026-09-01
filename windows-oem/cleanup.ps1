#Requires -RunAsAdministrator
# Post-setup cleanup script for the RadioBot Windows build VM.
# Run this from an elevated PowerShell session to free disk space after
# setup has completed.

$ErrorActionPreference = "Continue"
$ProgressPreference = 'SilentlyContinue'

function Write-Log($Message) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$ts $Message"
    Write-Host $line
}

function Get-FreeSpaceGB {
    $free = (Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace
    return [math]::Round($free / 1GB, 2)
}

$vcpkgDir = "C:\vcpkg"

Write-Log "Starting post-setup cleanup. Free space before: $(Get-FreeSpaceGB) GB"

# Remove vcpkg intermediate build artifacts. Keep installed and cache.
@("$vcpkgDir\buildtrees", "$vcpkgDir\packages") | ForEach-Object {
    if (Test-Path $_) {
        try {
            Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Removed $_"
        } catch {
            Write-Log "Could not remove $_ : $_"
        }
    }
}

# Remove installer files from Temp that are no longer needed, but keep setup log.
$TempDir = "C:\Temp"
@("vs_buildtools.exe", "Win32OpenSSL.exe") | ForEach-Object {
    $file = Join-Path $TempDir $_
    if (Test-Path $file) {
        try {
            Remove-Item $file -Force -ErrorAction SilentlyContinue
            Write-Log "Removed $file"
        } catch {
            Write-Log "Could not remove $file : $_"
        }
    }
}

Write-Log "Post-setup cleanup complete. Free space after: $(Get-FreeSpaceGB) GB"
