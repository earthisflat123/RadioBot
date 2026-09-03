#Requires -RunAsAdministrator

param(
    [string]$OEM = "C:\OEM"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

function Write-Log($Message) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$ts $Message"
    Write-Host $line
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
        Start-Service -Name sshd -ErrorAction SilentlyContinue
        Set-Service -Name sshd -StartupType 'Automatic' -ErrorAction SilentlyContinue

        # Open port 22 in the firewall.
        $fwRule = Get-NetFirewallRule -Name "OpenSSH-Server" -ErrorAction SilentlyContinue
        if (-not $fwRule) {
            New-NetFirewallRule -Name "OpenSSH-Server" -DisplayName "OpenSSH Server" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
        }
        Write-Log "OpenSSH server is running."
    } catch {
        Write-Log "OpenSSH setup failed: $_"
    }
}

function Add-HostSSHPublicKey {
    param(
        [string]$OemDir = "C:\OEM"
    )
    $pubKey = "$OemDir\id_rsa.pub"
    if (-not (Test-Path $pubKey)) { return }
    Write-Log "Adding host SSH public key..."
    $sshDir = "$env:ProgramData\ssh"
    $authKeys = "$sshDir\administrators_authorized_keys"
    New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
    Copy-Item $pubKey $authKeys -Force

    try {
        $acl = Get-Acl $sshDir
        $acl.SetAccessRuleProtection($true, $false)
        $acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("NT AUTHORITY\SYSTEM", "FullControl", "Allow")))
        $acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Administrators", "FullControl", "Allow")))
        Set-Acl $sshDir $acl
    } catch {
        Write-Log "Could not tighten SSH ACLs: $_"
    }

    try {
        $adminAcl = Get-Acl $authKeys
        $adminAcl.SetAccessRuleProtection($true, $false)
        $adminAcl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("NT AUTHORITY\SYSTEM", "FullControl", "Allow")))
        $adminAcl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Administrators", "ReadAndExecute", "Allow")))
        Set-Acl $authKeys $adminAcl
        Write-Log "Updated administrators authorized keys."
    } catch {
        Write-Log "Could not update administrators authorized keys: $_"
    }
}

Write-Log "Enabling OpenSSH server..."
Install-OpenSSHServer
Add-HostSSHPublicKey -OemDir $OEM
Write-Log "OpenSSH ready. The host can tail setup logs with:"
Write-Log "  ssh -p 2222 -i ~/.ssh/radiobot_windows_builder builder@localhost powershell -Command 'Get-Content -Wait C:\Temp\setup-radiobot.log'"
