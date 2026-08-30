#Requires -RunAsAdministrator

# Resume/finish the RadioBot Windows build environment setup.
# This is intended to be run inside the VM if the automated setup failed or
# was interrupted. It copies the latest windows-oem scripts from the shared
# drive and runs setup.ps1 with archive restore.

$ErrorActionPreference = "Stop"

$SharedRoot = "C:\Users\builder\Desktop\Shared"
if (-not (Test-Path $SharedRoot)) {
    throw "Shared drive not found at $SharedRoot. Make sure the host share is mounted."
}

$OEM = "C:\OEM"
$OEMSrc = "$SharedRoot\windows-oem"

Write-Host "Copying latest setup scripts from $OEMSrc to $OEM ..."
New-Item -ItemType Directory -Force -Path $OEM | Out-Null
Copy-Item "$OEMSrc\setup.ps1"    "$OEM\setup.ps1" -Force
Copy-Item "$OEMSrc\build-dsl.ps1" "$OEM\build-dsl.ps1" -Force
Copy-Item "$OEMSrc\build-radiobot.ps1" "$OEM\build-radiobot.ps1" -Force
Copy-Item "$OEMSrc\sln-prune.ps1" "$OEM\sln-prune.ps1" -Force
Copy-Item "$OEMSrc\install.bat"  "$OEM\install.bat" -Force

# Make sure any existing partially populated dependency trees don't conflict
# with the archive restore.
if (Test-Path "C:\vcpkg") {
    Write-Host "Removing partial vcpkg tree..."
    Remove-Item -Recurse -Force "C:\vcpkg" -ErrorAction SilentlyContinue
}
if (Test-Path "C:\deps") {
    Write-Host "Removing partial deps tree..."
    Remove-Item -Recurse -Force "C:\deps" -ErrorAction SilentlyContinue
}
if (Test-Path "C:\libspopc-src") {
    Write-Host "Removing partial libspopc-src..."
    Remove-Item -Recurse -Force "C:\libspopc-src" -ErrorAction SilentlyContinue
}

Write-Host "Starting setup.ps1 with archive restore..."
& powershell -ExecutionPolicy Bypass -NoProfile -File "$OEM\setup.ps1" -RepoSrc $SharedRoot -UseDepsArchive

if ($LASTEXITCODE -ne 0) {
    throw "setup.ps1 exited with code $LASTEXITCODE"
}
Write-Host "Setup finished."
