#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Standalone RadioBot Windows setup launcher.

.DESCRIPTION
    This script can be run before the RadioBot repository is cloned. It asks for
    a repository (upstream or a custom URL), clones it, and then launches
    the in-repo native build wizard or console.

.PARAMETER RepoDir
    Folder to clone into. Default is C:\RadioBot.

.PARAMETER RepoUrl
    Git URL to clone. If omitted, the upstream DriftSolutions repository is used.

.PARAMETER Console
    Launch the console wizard instead of the WinForms GUI.

.EXAMPLE
    .\RadioBot-Windows-Setup.ps1
    .\RadioBot-Windows-Setup.ps1 -RepoDir D:\RadioBot -RepoUrl https://github.com/DriftSolutions/RadioBot.git -Console
#>

param(
    [string]$RepoDir = 'C:\RadioBot',
    [string]$RepoUrl = '',
    [string]$Branch = 'master',
    [switch]$Console
)

$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must be run as Administrator.'
}

$DefaultUpstream = 'https://github.com/DriftSolutions/RadioBot.git'
$DefaultBranch = 'master'

function Write-Log($Message) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$ts $Message"
    Write-Host $line
}

function Test-Git {
    return [bool](Get-Command git -ErrorAction SilentlyContinue)
}

function Clone-WithGit($Url, $Path, $Branch) {
    $parent = Split-Path $Path -Parent
    if ($parent -and (-not (Test-Path $parent))) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    if (Test-Path "$Path\.git") {
        Write-Log "Updating existing clone at $Path..."
        & git -C $Path fetch --depth 1 origin $Branch
        & git -C $Path reset --hard "origin/$Branch"
    } else {
        Write-Log "Cloning $Url (branch $Branch) into $Path..."
        & git clone --depth 1 --branch $Branch $Url $Path
    }
    if ($LASTEXITCODE -ne 0) { throw "git clone/update failed" }
}

function Clone-WithZip($Url, $Path, $Branch) {
    $parent = Split-Path $Path -Parent
    if ($parent -and (-not (Test-Path $parent))) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    # Public GitHub zip fallback when git is not installed.
    $base = $Url -replace '\.git$','' -replace '/$',''
    $zipUrl = "$base/archive/refs/heads/$Branch.zip"
    $zipFile = Join-Path $env:TEMP "radiobot-$Branch.zip"

    Write-Log "Git not found; downloading $zipUrl..."
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile -UseBasicParsing

    $extractRoot = Join-Path $env:TEMP 'radiobot-zip-extract'
    if (Test-Path $extractRoot) { Remove-Item $extractRoot -Recurse -Force }
    Expand-Archive -Path $zipFile -DestinationPath $extractRoot -Force

    $unpacked = Get-ChildItem -Path $extractRoot -Directory | Select-Object -First 1
    if (-not $unpacked) { throw 'No directory found after extracting archive.' }

    if (Test-Path $Path) { Remove-Item $Path -Recurse -Force }
    Move-Item $unpacked.FullName $Path
    Remove-Item $zipFile -Force
    Remove-Item $extractRoot -Force
    Write-Log "Extracted to $Path"
}

if ([string]::IsNullOrWhiteSpace($RepoUrl)) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'RadioBot Setup Launcher'
    $form.Size = New-Object System.Drawing.Size(600, 260)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false

    $rbUpstream = New-Object System.Windows.Forms.RadioButton
    $rbUpstream.Text = 'DriftSolutions/RadioBot'
    $rbUpstream.Location = New-Object System.Drawing.Point(20, 20)
    $rbUpstream.Size = New-Object System.Drawing.Size(500, 20)
    $rbUpstream.Checked = $true
    $form.Controls.Add($rbUpstream)

    $rbOther = New-Object System.Windows.Forms.RadioButton
    $rbOther.Text = 'Other:'
    $rbOther.Location = New-Object System.Drawing.Point(20, 45)
    $rbOther.Size = New-Object System.Drawing.Size(80, 20)
    $form.Controls.Add($rbOther)

    $txtOther = New-Object System.Windows.Forms.TextBox
    $txtOther.Size = New-Object System.Drawing.Size(460, 20)
    $txtOther.Location = New-Object System.Drawing.Point(110, 45)
    $txtOther.Enabled = $false
    $form.Controls.Add($txtOther)
    $rbOther.Add_CheckedChanged({ $txtOther.Enabled = $rbOther.Checked })

    $lblPath = New-Object System.Windows.Forms.Label
    $lblPath.Text = 'Clone to:'
    $lblPath.Location = New-Object System.Drawing.Point(20, 80)
    $lblPath.Size = New-Object System.Drawing.Size(80, 20)
    $form.Controls.Add($lblPath)

    $txtPath = New-Object System.Windows.Forms.TextBox
    $txtPath.Text = $RepoDir
    $txtPath.Size = New-Object System.Drawing.Size(390, 20)
    $txtPath.Location = New-Object System.Drawing.Point(110, 80)
    $form.Controls.Add($txtPath)

    $btnBrowse = New-Object System.Windows.Forms.Button
    $btnBrowse.Text = 'Browse...'
    $btnBrowse.Location = New-Object System.Drawing.Point(505, 78)
    $btnBrowse.Size = New-Object System.Drawing.Size(90, 23)
    $btnBrowse.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Select the folder to clone RadioBot into'
        if ($dlg.ShowDialog() -eq 'OK') { $txtPath.Text = $dlg.SelectedPath }
    })
    $form.Controls.Add($btnBrowse)

    $lblBranch = New-Object System.Windows.Forms.Label
    $lblBranch.Text = 'Branch:'
    $lblBranch.Location = New-Object System.Drawing.Point(20, 110)
    $lblBranch.Size = New-Object System.Drawing.Size(80, 20)
    $form.Controls.Add($lblBranch)

    $txtBranch = New-Object System.Windows.Forms.TextBox
    $txtBranch.Text = $Branch
    $txtBranch.Size = New-Object System.Drawing.Size(490, 20)
    $txtBranch.Location = New-Object System.Drawing.Point(110, 110)
    $form.Controls.Add($txtBranch)

    $chkConsole = New-Object System.Windows.Forms.CheckBox
    $chkConsole.Text = 'Use console wizard instead of GUI'
    $chkConsole.Location = New-Object System.Drawing.Point(20, 140)
    $chkConsole.Size = New-Object System.Drawing.Size(300, 20)
    $form.Controls.Add($chkConsole)

    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text = 'OK'
    $btnOK.Size = New-Object System.Drawing.Size(100, 30)
    $btnOK.Location = New-Object System.Drawing.Point(380, 175)
    $btnOK.Add_Click({
        if ($rbUpstream.Checked) { $script:RepoUrl = $DefaultUpstream }
        else { $script:RepoUrl = $txtOther.Text.Trim() }
        $script:RepoDir = $txtPath.Text.Trim()
        $script:Branch = $txtBranch.Text.Trim()
        $script:UseConsole = $chkConsole.Checked
        $form.Close()
    })
    $form.Controls.Add($btnOK)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Cancel'
    $btnCancel.Size = New-Object System.Drawing.Size(100, 30)
    $btnCancel.Location = New-Object System.Drawing.Point(490, 175)
    $btnCancel.Add_Click({
        $script:Cancelled = $true
        $form.Close()
    })
    $form.Controls.Add($btnCancel)

    $script:Cancelled = $false
    $form.ShowDialog() | Out-Null

    if ($script:Cancelled) {
        Write-Log 'Setup cancelled by user.'
        exit 0
    }
}

if ([string]::IsNullOrWhiteSpace($RepoUrl)) {
    $RepoUrl = $DefaultUpstream
}

if (Test-Git) {
    Clone-WithGit -Url $RepoUrl -Path $RepoDir -Branch $script:Branch
} else {
    Clone-WithZip -Url $RepoUrl -Path $RepoDir -Branch $script:Branch
}

$target = if ($Console -or $script:UseConsole) {
    Join-Path $RepoDir 'build-windows-native-console.ps1'
} else {
    Join-Path $RepoDir 'build-windows-native-wizard.ps1'
}

Write-Log "Launching $target ..."
& powershell.exe -ExecutionPolicy Bypass -NoProfile -File $target -RepoDir $RepoDir -Branch $script:Branch
