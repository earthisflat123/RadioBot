#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    WinForms GUI wizard for building RadioBot natively on Windows.

.DESCRIPTION
    A step-by-step wizard that can clone the RadioBot repository, set up the
    build environment, build the binaries, and package the installer without
    Docker, Samba, or an SSH key.

.EXAMPLE
    .\build-windows-native-wizard.ps1
    .\build-windows-native-wizard.ps1 -RepoDir C:\RadioBot
#>

param(
    [string]$RepoDir = '',
    [string]$Branch = 'master'
)

$ErrorActionPreference = 'Stop'

Import-Module -Force "$PSScriptRoot\windows-oem\native-build-core.psm1"

if (-not (Test-Administrator)) {
    throw 'This script must be run as Administrator.'
}

Initialize-NativeBuildLog

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:CurrentStep = 0
$script:StepCommands = $null
$script:RepoDir = $RepoDir
$script:Branch = $Branch
$script:OEM = ''
$script:RunningProcess = $null
$script:UseDepsArchive = $false

$form = New-Object System.Windows.Forms.Form
$form.Text = 'RadioBot Native Windows Build Wizard'
$form.Size = New-Object System.Drawing.Size(900, 650)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Microsoft Sans Serif', 10)

$btnBack = New-Object System.Windows.Forms.Button
$btnBack.Text = '< Back'
$btnBack.Size = New-Object System.Drawing.Size(100, 30)
$btnBack.Location = New-Object System.Drawing.Point(550, 580)
$btnBack.Enabled = $false
$form.Controls.Add($btnBack)

$btnNext = New-Object System.Windows.Forms.Button
$btnNext.Text = 'Next >'
$btnNext.Size = New-Object System.Drawing.Size(100, 30)
$btnNext.Location = New-Object System.Drawing.Point(660, 580)
$form.Controls.Add($btnNext)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = 'Cancel'
$btnCancel.Size = New-Object System.Drawing.Size(100, 30)
$btnCancel.Location = New-Object System.Drawing.Point(770, 580)
$form.Controls.Add($btnCancel)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Style = 'Marquee'
$progress.MarqueeAnimationSpeed = 30
$progress.Size = New-Object System.Drawing.Size(860, 20)
$progress.Location = New-Object System.Drawing.Point(15, 545)
$progress.Visible = $false
$form.Controls.Add($progress)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ScrollBars = 'Vertical'
$logBox.ReadOnly = $true
$logBox.Size = New-Object System.Drawing.Size(860, 200)
$logBox.Location = New-Object System.Drawing.Point(15, 335)
$logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$form.Controls.Add($logBox)

$header = New-Object System.Windows.Forms.Label
$header.Text = 'Welcome to the RadioBot native build wizard'
$header.Font = New-Object System.Drawing.Font('Microsoft Sans Serif', 12, [System.Drawing.FontStyle]::Bold)
$header.Size = New-Object System.Drawing.Size(860, 30)
$header.Location = New-Object System.Drawing.Point(15, 15)
$form.Controls.Add($header)

$pages = @()

# --- Page 0: Repository / Clone ---
$page0 = New-Object System.Windows.Forms.Panel
$page0.Size = New-Object System.Drawing.Size(860, 285)
$page0.Location = New-Object System.Drawing.Point(15, 45)
$page0.Visible = $true

$lblRepo = New-Object System.Windows.Forms.Label
$lblRepo.Text = 'Select the repository to build:'
$lblRepo.AutoSize = $false
$lblRepo.Size = New-Object System.Drawing.Size(400, 20)
$lblRepo.Location = New-Object System.Drawing.Point(10, 10)
$page0.Controls.Add($lblRepo)

$rbFork = New-Object System.Windows.Forms.RadioButton
$rbFork.Text = 'earthisflat123/RadioBot (recommended fork)'
$rbFork.Location = New-Object System.Drawing.Point(10, 35)
$rbFork.Size = New-Object System.Drawing.Size(500, 20)
$rbFork.Checked = $true
$page0.Controls.Add($rbFork)

$rbUpstream = New-Object System.Windows.Forms.RadioButton
$rbUpstream.Text = 'DriftSolutions/RadioBot (upstream)'
$rbUpstream.Location = New-Object System.Drawing.Point(10, 60)
$rbUpstream.Size = New-Object System.Drawing.Size(500, 20)
$page0.Controls.Add($rbUpstream)

$rbOther = New-Object System.Windows.Forms.RadioButton
$rbOther.Text = 'Other repository:'
$rbOther.Location = New-Object System.Drawing.Point(10, 85)
$rbOther.Size = New-Object System.Drawing.Size(130, 20)
$page0.Controls.Add($rbOther)

$txtOtherUrl = New-Object System.Windows.Forms.TextBox
$txtOtherUrl.Size = New-Object System.Drawing.Size(700, 20)
$txtOtherUrl.Location = New-Object System.Drawing.Point(150, 85)
$txtOtherUrl.Enabled = $false
$page0.Controls.Add($txtOtherUrl)

$rbOther.Add_CheckedChanged({ $txtOtherUrl.Enabled = $rbOther.Checked })

$rbLocal = New-Object System.Windows.Forms.RadioButton
$rbLocal.Text = 'I already have a local clone'
$rbLocal.Location = New-Object System.Drawing.Point(10, 115)
$rbLocal.Size = New-Object System.Drawing.Size(200, 20)
$page0.Controls.Add($rbLocal)

$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Text = 'Local / clone path:'
$lblPath.AutoSize = $false
$lblPath.Size = New-Object System.Drawing.Size(130, 20)
$lblPath.Location = New-Object System.Drawing.Point(10, 145)
$page0.Controls.Add($lblPath)

$txtRepoDir = New-Object System.Windows.Forms.TextBox
$txtRepoDir.Text = 'C:\RadioBot'
$txtRepoDir.Size = New-Object System.Drawing.Size(600, 20)
$txtRepoDir.Location = New-Object System.Drawing.Point(150, 145)
$page0.Controls.Add($txtRepoDir)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = 'Browse...'
$btnBrowse.Size = New-Object System.Drawing.Size(90, 23)
$btnBrowse.Location = New-Object System.Drawing.Point(760, 143)
$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Select the RadioBot repository folder'
    if ($dlg.ShowDialog() -eq 'OK') {
        $txtRepoDir.Text = $dlg.SelectedPath
    }
})
$page0.Controls.Add($btnBrowse)

$lblBranch = New-Object System.Windows.Forms.Label
$lblBranch.Text = 'Branch to clone:'
$lblBranch.AutoSize = $false
$lblBranch.Size = New-Object System.Drawing.Size(130, 20)
$lblBranch.Location = New-Object System.Drawing.Point(10, 175)
$page0.Controls.Add($lblBranch)

$txtBranch = New-Object System.Windows.Forms.TextBox
$txtBranch.Text = $script:Branch
$txtBranch.Size = New-Object System.Drawing.Size(700, 20)
$txtBranch.Location = New-Object System.Drawing.Point(150, 175)
$page0.Controls.Add($txtBranch)

$chkUseArchive = New-Object System.Windows.Forms.CheckBox
$chkUseArchive.Text = 'Use radiobot-windows-deps.7z dependency archive if it exists in the repo root (skips vcpkg builds)'
$chkUseArchive.Location = New-Object System.Drawing.Point(10, 205)
$chkUseArchive.Size = New-Object System.Drawing.Size(800, 20)
$chkUseArchive.Checked = $true
$page0.Controls.Add($chkUseArchive)

$lblArchive = New-Object System.Windows.Forms.Label
$lblArchive.Text = 'Archive path:'
$lblArchive.AutoSize = $false
$lblArchive.Size = New-Object System.Drawing.Size(100, 20)
$lblArchive.Location = New-Object System.Drawing.Point(10, 235)
$page0.Controls.Add($lblArchive)

$txtArchivePath = New-Object System.Windows.Forms.TextBox
$txtArchivePath.Size = New-Object System.Drawing.Size(650, 20)
$txtArchivePath.Location = New-Object System.Drawing.Point(100, 235)
$page0.Controls.Add($txtArchivePath)

$btnBrowseArchive = New-Object System.Windows.Forms.Button
$btnBrowseArchive.Text = 'Browse...'
$btnBrowseArchive.Size = New-Object System.Drawing.Size(90, 23)
$btnBrowseArchive.Location = New-Object System.Drawing.Point(760, 233)
$btnBrowseArchive.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = '7z archive (*.7z)|*.7z'
    if ($dlg.ShowDialog() -eq 'OK') {
        $txtArchivePath.Text = $dlg.FileName
    }
})
$page0.Controls.Add($btnBrowseArchive)

$pages += $page0
$form.Controls.Add($page0)

# --- Page 1-3: Setup/Build/Package ---
$page1 = New-Object System.Windows.Forms.Panel
$page1.Size = New-Object System.Drawing.Size(860, 285)
$page1.Location = New-Object System.Drawing.Point(15, 45)
$page1.Visible = $false

$lblStep = New-Object System.Windows.Forms.Label
$lblStep.Text = 'Ready to set up the build environment.'
$lblStep.Font = New-Object System.Drawing.Font('Microsoft Sans Serif', 11, [System.Drawing.FontStyle]::Bold)
$lblStep.Size = New-Object System.Drawing.Size(860, 30)
$lblStep.Location = New-Object System.Drawing.Point(10, 10)
$page1.Controls.Add($lblStep)

$lblStepDesc = New-Object System.Windows.Forms.Label
$lblStepDesc.Text = 'Click Next to install Chocolatey, Visual Studio Build Tools, vcpkg, DSL, libfaac and libspopc.'
$lblStepDesc.Size = New-Object System.Drawing.Size(840, 40)
$lblStepDesc.Location = New-Object System.Drawing.Point(10, 45)
$page1.Controls.Add($lblStepDesc)

$pages += $page1
$form.Controls.Add($page1)

# --- Page 4: Finish ---
$page4 = New-Object System.Windows.Forms.Panel
$page4.Size = New-Object System.Drawing.Size(860, 285)
$page4.Location = New-Object System.Drawing.Point(15, 45)
$page4.Visible = $false

$lblFinish = New-Object System.Windows.Forms.Label
$lblFinish.Text = 'Build complete'
$lblFinish.Font = New-Object System.Drawing.Font('Microsoft Sans Serif', 12, [System.Drawing.FontStyle]::Bold)
$lblFinish.Size = New-Object System.Drawing.Size(860, 30)
$lblFinish.Location = New-Object System.Drawing.Point(10, 10)
$page4.Controls.Add($lblFinish)

$lblFinishDesc = New-Object System.Windows.Forms.Label
$lblFinishDesc.Text = 'The following binaries were built. Check the ones you want to run, then click Launch.'
$lblFinishDesc.Size = New-Object System.Drawing.Size(840, 20)
$lblFinishDesc.Location = New-Object System.Drawing.Point(10, 45)
$page4.Controls.Add($lblFinishDesc)

$clbBinaries = New-Object System.Windows.Forms.CheckedListBox
$clbBinaries.Size = New-Object System.Drawing.Size(840, 150)
$clbBinaries.Location = New-Object System.Drawing.Point(10, 75)
$page4.Controls.Add($clbBinaries)

$btnLaunch = New-Object System.Windows.Forms.Button
$btnLaunch.Text = 'Launch selected'
$btnLaunch.Size = New-Object System.Drawing.Size(120, 30)
$btnLaunch.Location = New-Object System.Drawing.Point(10, 235)
$btnLaunch.Add_Click({
    foreach ($item in $clbBinaries.CheckedItems) {
        Start-Process -FilePath $item
    }
})
$page4.Controls.Add($btnLaunch)

$btnOpenArtifacts = New-Object System.Windows.Forms.Button
$btnOpenArtifacts.Text = 'Open artifacts folder'
$btnOpenArtifacts.Size = New-Object System.Drawing.Size(140, 30)
$btnOpenArtifacts.Location = New-Object System.Drawing.Point(140, 235)
$btnOpenArtifacts.Add_Click({
    if ($script:RepoDir -and (Test-Path "$script:RepoDir\artifacts")) {
        Start-Process explorer.exe -ArgumentList "$script:RepoDir\artifacts"
    }
})
$page4.Controls.Add($btnOpenArtifacts)

$pages += $page4
$form.Controls.Add($page4)

function Switch-Page {
    param([int]$Index)
    # $page1 is reused for steps 1-3; $page4 is the finish page.
    $page0.Visible = ($Index -eq 0)
    $page1.Visible = ($Index -in 1,2,3)
    $page4.Visible = ($Index -eq 4)
    $script:CurrentStep = $Index
    $btnBack.Enabled = ($Index -gt 0 -and $Index -lt 4)

    if ($Index -eq 0) {
        $btnNext.Text = 'Next >'
        $header.Text = 'Step 1: Repository'
    } elseif ($Index -eq 1) {
        $btnNext.Text = 'Setup >'
        $header.Text = 'Step 2: Setup build environment'
        $lblStep.Text = 'Ready to set up the build environment.'
        $lblStepDesc.Text = 'Click Setup to install Chocolatey, Visual Studio Build Tools, vcpkg, DSL, libfaac and libspopc.'
    } elseif ($Index -eq 2) {
        $btnNext.Text = 'Build >'
        $header.Text = 'Step 3: Build RadioBot'
        $lblStep.Text = 'Ready to build RadioBot.'
        $lblStepDesc.Text = 'Click Build to compile the solution with MSBuild.'
    } elseif ($Index -eq 3) {
        $btnNext.Text = 'Package >'
        $header.Text = 'Step 4: Package installer'
        $lblStep.Text = 'Ready to package the installer.'
        $lblStepDesc.Text = 'Click Package to build RadioBot-setup.exe with NSIS.'
    } elseif ($Index -eq 4) {
        $btnNext.Text = 'Finish'
        $btnNext.Enabled = $false
        $btnBack.Enabled = $false
        $header.Text = 'Step 5: Finish'
    }
}

function Append-Log {
    param([string]$Line)
    if ($logBox.IsDisposed -or $form.IsDisposed -or -not $form.IsHandleCreated) { return }
    $logBox.Invoke([Action]{ if (-not $logBox.IsDisposed) { $logBox.AppendText("$Line`r`n") } })
}

function Start-LoggedProcess {
    param(
        [Parameter(Mandatory)]
        $Step
    )

    $progress.Visible = $true
    $btnNext.Enabled = $false
    $btnBack.Enabled = $false
    $btnCancel.Enabled = $false
    Append-Log "=== Starting: $($Step.Name) ==="
    Append-Log $Step.LogHint

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo.FileName = $Step.FileName
    $p.StartInfo.Arguments = $Step.Arguments
    $p.StartInfo.UseShellExecute = $false
    $p.StartInfo.RedirectStandardOutput = $true
    $p.StartInfo.RedirectStandardError = $true
    $p.StartInfo.CreateNoWindow = $true
    $p.EnableRaisingEvents = $true

    $p.add_OutputDataReceived({
        if ($EventArgs.Data) { Append-Log $EventArgs.Data }
    })
    $p.add_ErrorDataReceived({
        if ($EventArgs.Data) { Append-Log $EventArgs.Data }
    })
    $p.add_Exited({
        # WinForms events run on a thread pool, so UI updates must be
        # marshalled back to the form's UI thread.
        [void]$form.BeginInvoke([Action]{
            if ($form.IsDisposed -or -not $form.IsHandleCreated) { return }

            $progress.Visible = $false
            $btnCancel.Enabled = $true
            $btnBack.Enabled = ($script:CurrentStep -gt 0 -and $script:CurrentStep -lt 4)
            $btnNext.Enabled = $true
            $script:RunningProcess = $null

            if ($p.ExitCode -ne 0) {
                Append-Log "ERROR: '$($Step.Name)' failed with exit code $($p.ExitCode)."
                [System.Windows.Forms.MessageBox]::Show("'$($Step.Name)' failed. Check the log for details.", 'Error', 'OK', 'Error') | Out-Null
            } else {
                Append-Log "=== '$($Step.Name)' finished ==="
                if ($Step.Name -eq 'Clone') {
                    # The repo now exists; re-evaluate dependency archive availability.
                    $archiveDest = Join-Path $script:RepoDir 'radiobot-windows-deps.7z'
                    $customArchive = $txtArchivePath.Text.Trim()
                    if ($chkUseArchive.Checked -and $customArchive -and (Test-Path $customArchive)) {
                        Copy-Item $customArchive $archiveDest -Force
                    }
                    if (Test-Path $archiveDest) {
                        $script:UseDepsArchive = $true
                    }
                    $script:StepCommands = Get-StepCommands -RepoDir $script:RepoDir -UseDepsArchive:$script:UseDepsArchive
                }
                if ($script:CurrentStep -lt 3) {
                    Switch-Page ($script:CurrentStep + 1)
                } else {
                    Show-FinishPage
                }
            }
        })
    })

    $script:RunningProcess = $p
    [void]$p.Start()
    $p.BeginOutputReadLine()
    $p.BeginErrorReadLine()
}

function Show-FinishPage {
    Switch-Page 4
    $clbBinaries.Items.Clear()
    $binaries = Get-BuiltBinaries -RepoDir $script:RepoDir
    foreach ($b in $binaries) { [void]$clbBinaries.Items.Add($b, $false) }
    $installer = Get-InstallerPath -RepoDir $script:RepoDir
    if ($installer) {
        Append-Log "Installer ready: $installer"
    }
}

function Resolve-RepoPage {
    if ($rbLocal.Checked) {
        $script:RepoDir = $txtRepoDir.Text.Trim()
        if (-not (Test-Path "$script:RepoDir\vcpkg.json")) {
            [System.Windows.Forms.MessageBox]::Show("No RadioBot repo detected at $script:RepoDir (vcpkg.json not found).", 'Error', 'OK', 'Error') | Out-Null
            return $false
        }
        $script:OEM = Join-Path $script:RepoDir 'windows-oem'
    } else {
        $source = if ($rbFork.Checked) { 'Fork' } elseif ($rbUpstream.Checked) { 'Upstream' } else { 'Other' }
        $url = Get-RepositoryUrl -Choice $source -CustomUrl $txtOtherUrl.Text.Trim()
        $script:RepoDir = $txtRepoDir.Text.Trim()
        $branch = if ([string]::IsNullOrWhiteSpace($txtBranch.Text)) { 'master' } else { $txtBranch.Text.Trim() }

        # Pre-initialise step commands so the wizard can proceed after clone.
        $script:StepCommands = Get-StepCommands -RepoDir $script:RepoDir -UseDepsArchive:$false

        $progress.Visible = $true
        $btnNext.Enabled = $false
        $btnCancel.Enabled = $false

        $cloneArgs = @('clone', '--depth', '1', '--branch', $branch, $url, $script:RepoDir) -join ' '
        $cloneStep = @{
            Name      = 'Clone'
            FileName  = 'git.exe'
            Arguments = $cloneArgs
            LogHint   = "Cloning $url (branch $branch) into $script:RepoDir..."
        }
        Start-LoggedProcess $cloneStep
        # Switch to build page after clone completes; do not advance immediately.
        return $false
    }

    # Auto-detect or use provided deps archive.
    $archivePath = $txtArchivePath.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($archivePath)) {
        $archivePath = Join-Path $script:RepoDir 'radiobot-windows-deps.7z'
    }
    $script:UseDepsArchive = ($chkUseArchive.Checked -and (Test-Path $archivePath))
    if ($script:UseDepsArchive) {
        # Make sure the archive is at the repo root where setup.ps1 looks for it.
        $dest = Join-Path $script:RepoDir 'radiobot-windows-deps.7z'
        if ($archivePath -ne $dest) {
            Copy-Item $archivePath $dest -Force
        }
    }

    $script:StepCommands = Get-StepCommands -RepoDir $script:RepoDir -UseDepsArchive:$script:UseDepsArchive
    return $true
}

$btnNext.Add_Click({
    if ($script:CurrentStep -eq 0) {
        if (-not (Resolve-RepoPage)) { return }
        Switch-Page 1
    } elseif ($script:CurrentStep -in 1,2,3) {
        $step = $script:StepCommands[$script:CurrentStep - 1]
        Start-LoggedProcess $step
    }
})

$btnBack.Add_Click({
    if ($script:CurrentStep -gt 0 -and $script:CurrentStep -lt 4) {
        Switch-Page ($script:CurrentStep - 1)
    }
})

$btnCancel.Add_Click({
    if ($script:RunningProcess -and -not $script:RunningProcess.HasExited) {
        $script:RunningProcess.Kill()
    }
    $form.Close()
})

$form.Add_FormClosing({
    if ($script:RunningProcess -and -not $script:RunningProcess.HasExited) {
        $script:RunningProcess.Kill()
    }
})

if (-not [string]::IsNullOrWhiteSpace($script:RepoDir)) {
    $txtRepoDir.Text = $script:RepoDir
    if (Test-Path "$script:RepoDir\vcpkg.json") { $rbLocal.Checked = $true }
}

$form.ShowDialog() | Out-Null
