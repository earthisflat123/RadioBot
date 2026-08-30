#Requires -RunAsAdministrator

# Manual SSH-enable helper for the RadioBot Windows build VM.
# Run this from an elevated PowerShell inside the VM if the automated setup
# did not yet enable OpenSSH and you need remote access for inspection.

$ErrorActionPreference = "Stop"

$pubKey = "C:\OEM\id_rsa.pub"
if (-not (Test-Path $pubKey)) {
    # The repo is shared as a shortcut on the builder's Desktop and possibly as Z:\
    $altKeys = @(
        "C:\Users\builder\Desktop\Shared\windows-oem\id_rsa.pub",
        "Z:\windows-oem\id_rsa.pub"
    )
    foreach ($alt in $altKeys) {
        if (Test-Path $alt) {
            $pubKey = $alt
            break
        }
    }
}

if (-not (Test-Path $pubKey)) {
    throw "Could not find id_rsa.pub. Run ./prepare-windows-build.sh on the host first."
}

Write-Host "Using public key: $pubKey"

$cap = Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
if ($cap.State -ne 'Installed') {
    Write-Host "Installing OpenSSH server..."
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
} else {
    Write-Host "OpenSSH server already installed."
}

$sshd = Get-Service -Name sshd -ErrorAction SilentlyContinue
if ($sshd) {
    Start-Service sshd
    Set-Service -Name sshd -StartupType Automatic
}

if (-not (Get-NetFirewallRule -Name "OpenSSH-Server" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name "OpenSSH-Server" -DisplayName "OpenSSH Server" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}

$sshDir = "C:\Users\builder\.ssh"
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
Copy-Item $pubKey "$sshDir\authorized_keys" -Force

$adminKeys = "$env:ProgramData\ssh\administrators_authorized_keys"
New-Item -ItemType Directory -Force -Path "$env:ProgramData\ssh" | Out-Null
Copy-Item $pubKey $adminKeys -Force

Write-Host "SSH enabled. Connect from the host with:"
Write-Host "  ssh -p 2222 -i ~/.ssh/radiobot_windows_builder -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null builder@localhost"
