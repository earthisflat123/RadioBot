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

# Capture all console output (including unhandled errors) to a transcript.
$script:WizardTranscript = 'C:\Temp\radiobot-wizard-transcript.log'
if (Test-Path $script:WizardTranscript) { Remove-Item $script:WizardTranscript -Force }
Start-Transcript -Path $script:WizardTranscript -Force -ErrorAction SilentlyContinue | Out-Null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Enable Windows visual styles (modern controls and a working marquee
# progress bar). This must be called before any controls are created.
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

# Global error logging so silent failures are captured.
$script:WizardErrorLog = 'C:\Temp\radiobot-wizard-error.log'
function Write-WizardError($Message) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    try { Add-Content -Path $script:WizardErrorLog -Value "$ts $Message" -ErrorAction SilentlyContinue } catch {}
}

[void][System.Windows.Forms.Application]::add_ThreadException({
    param($sender, $e)
    Write-WizardError "ThreadException: $($e.Exception.Message)`n$($e.Exception.StackTrace)"
    try { [System.Windows.Forms.MessageBox]::Show("Unhandled UI thread exception:`n$($e.Exception.Message)", 'Error', 'OK', 'Error') | Out-Null } catch {}
})

[void][AppDomain]::CurrentDomain.add_UnhandledException({
    param($sender, $e)
    $ex = $e.ExceptionObject
    Write-WizardError "UnhandledException: $($ex.Message)`n$($ex.StackTrace)"
    try { [System.Windows.Forms.MessageBox]::Show("Unhandled exception:`n$($ex.Message)", 'Error', 'OK', 'Error') | Out-Null } catch {}
})

$script:CurrentStep = 0
$script:StepCommands = $null
$script:RepoDir = $RepoDir
$script:Branch = $Branch
$script:OEM = ''
$script:RunningProcess = $null
$script:UseDepsArchive = $false
$script:CurrentStepName = ''
$script:CurrentExitReadCount = 0

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

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ScrollBars = 'Vertical'
$logBox.ReadOnly = $true
$logBox.Size = New-Object System.Drawing.Size(860, 200)
$logBox.Location = New-Object System.Drawing.Point(15, 315)
$logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$form.Controls.Add($logBox)

$lblProgress = New-Object System.Windows.Forms.Label
$lblProgress.Size = New-Object System.Drawing.Size(860, 20)
$lblProgress.Location = New-Object System.Drawing.Point(15, 525)
$lblProgress.Font = New-Object System.Drawing.Font('Consolas', 9)
$lblProgress.Text = ''
$lblProgress.Visible = $false
$form.Controls.Add($lblProgress)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Style = 'Continuous'
$progress.Minimum = 0
$progress.Maximum = 100
$progress.Value = 0
$progress.Size = New-Object System.Drawing.Size(860, 20)
$progress.Location = New-Object System.Drawing.Point(15, 550)
$progress.Visible = $false
$form.Controls.Add($progress)

# Tail the redirected stdout/stderr files on the UI thread and advance
# the wizard when the monitored child process has exited.
$logTimer = New-Object System.Windows.Forms.Timer
$logTimer.Interval = 100
$logTimer.Add_Tick({
    try {
        if ($form.IsDisposed -or -not $form.IsHandleCreated) { return }
        if (-not $script:RunningProcess) { return }

        # Open readers once the files exist.
        if (-not $script:CurrentOutReader -and (Test-Path $script:CurrentOutFile)) {
            $script:CurrentOutReader = [System.IO.StreamReader]::new(
                [System.IO.File]::Open($script:CurrentOutFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite),
                [System.Text.Encoding]::Default
            )
        }
        if (-not $script:CurrentErrReader -and (Test-Path $script:CurrentErrFile)) {
            $script:CurrentErrReader = [System.IO.StreamReader]::new(
                [System.IO.File]::Open($script:CurrentErrFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite),
                [System.Text.Encoding]::Default
            )
        }

        # Drain available lines.
        if ($script:CurrentOutReader) {
            while ($null -ne ($line = $script:CurrentOutReader.ReadLine())) {
                Append-Log $line
            }
        }
        if ($script:CurrentErrReader) {
            while ($null -ne ($line = $script:CurrentErrReader.ReadLine())) {
                Append-Log "ERR: $line"
            }
        }

        # Update the progress bar and timing label while the step is running.
        if ($script:StepStopwatch -and $script:StepStopwatch.IsRunning) {
            $elapsed = $script:StepStopwatch.Elapsed
            $pct = [int][Math]::Min(99, ($elapsed.TotalSeconds / $script:StepEstimateSeconds) * 100)
            $etaSec = [Math]::Max(0, $script:StepEstimateSeconds - $elapsed.TotalSeconds)
            $eta = [TimeSpan]::FromSeconds($etaSec)
            $progress.Value = $pct
            $lblProgress.Text = ("{0}: {1}% | Elapsed: {2:hh\:mm\:ss} | ETA: {3:hh\:mm\:ss}" -f $script:CurrentStepName, $pct, $elapsed, $eta)
        }

        if ($script:RunningProcess.WaitForExit(0)) {
            # The process has exited. Drain the tee files a few more ticks so
            # that the async OutputDataReceived handlers finish writing, then
            # switch to the next step.
            $script:CurrentExitReadCount++
            if ($script:CurrentExitReadCount -ge 5) {
                if ($script:CurrentOutReader) {
                    while ($null -ne ($line = $script:CurrentOutReader.ReadLine())) { Append-Log $line }
                }
                if ($script:CurrentErrReader) {
                    while ($null -ne ($line = $script:CurrentErrReader.ReadLine())) { Append-Log "ERR: $line" }
                }

                if ($script:CurrentOutReader) { $script:CurrentOutReader.Close(); $script:CurrentOutReader = $null }
                if ($script:CurrentErrReader) { $script:CurrentErrReader.Close(); $script:CurrentErrReader = $null }
                if ($script:CurrentTee) { $script:CurrentTee.Close(); $script:CurrentTee = $null }

                $p = $script:RunningProcess
                $stepName = if ([string]::IsNullOrWhiteSpace($script:CurrentStepName)) { 'Step' } else { $script:CurrentStepName }
                $exitCode = $p.ExitCode
                $script:RunningProcess = $null
                $script:CurrentExitReadCount = 0

                if ($script:StepStopwatch) { $script:StepStopwatch.Stop() }

                if ($exitCode -ne 0) {
                    $progress.Value = 0
                    $lblProgress.Text = ("{0} failed with exit code {1}" -f $stepName, $exitCode)
                    $progress.Visible = $true
                    $lblProgress.Visible = $true
                    Append-Log "ERROR: '$stepName' failed with exit code $exitCode."
                    [System.Windows.Forms.MessageBox]::Show("'$stepName' failed. Check the log for details.", 'Error', 'OK', 'Error') | Out-Null
                } else {
                    $progress.Value = 100
                    $elapsed = if ($script:StepStopwatch) { $script:StepStopwatch.Elapsed } else { [TimeSpan]::Zero }
                    Append-Log ("=== '{0}' finished in {1:hh\:mm\:ss} ===" -f $stepName, $elapsed)
                    $progress.Visible = $false
                    $lblProgress.Visible = $false
                    $current = $script:CurrentStep
                    if ($current -lt 3) {
                        Switch-Page ($current + 1)
                    } else {
                        Show-FinishPage
                    }
                }

                $btnCancel.Enabled = $true
                $btnBack.Enabled = ($script:CurrentStep -gt 0 -and $script:CurrentStep -lt 4)
                $btnNext.Enabled = $true
            }
        }
    } catch {
        Write-WizardError "Timer tick error: $($_.Exception.Message)`n$($_.ScriptStackTrace)"
    }
})
$logTimer.Start()

$header = New-Object System.Windows.Forms.Label
$header.Text = 'Welcome to the RadioBot native build wizard'
$header.Font = New-Object System.Drawing.Font('Microsoft Sans Serif', 12, [System.Drawing.FontStyle]::Bold)
$header.Size = New-Object System.Drawing.Size(860, 30)
$header.Location = New-Object System.Drawing.Point(15, 15)
$form.Controls.Add($header)

$pages = @()

# --- Page 0: Repository / Clone ---
$page0 = New-Object System.Windows.Forms.Panel
$page0.Size = New-Object System.Drawing.Size(860, 260)
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
$page1.Size = New-Object System.Drawing.Size(860, 110)
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
$page4.Size = New-Object System.Drawing.Size(860, 270)
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
    try {
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

        # Resize and reposition the log and progress controls so short pages
        # do not leave a large empty gap and long pages still have a useful log.
        if ($Index -in 1,2,3) {
            $logBox.Size = New-Object System.Drawing.Size(860, 350)
            $logBox.Location = New-Object System.Drawing.Point(15, 165)
        } else {
            $logBox.Size = New-Object System.Drawing.Size(860, 200)
            $logBox.Location = New-Object System.Drawing.Point(15, 315)
        }

        $lblProgressTop = $logBox.Bottom + 10
        $lblProgress.Location = New-Object System.Drawing.Point(15, $lblProgressTop)
        $progressTop = $lblProgress.Bottom + 5
        $progress.Location = New-Object System.Drawing.Point(15, $progressTop)

        # Hide the progress controls while no step is running; Start-LoggedProcess
        # will re-show them when the next step starts.
        $progress.Visible = $false
        $lblProgress.Visible = $false
        $lblProgress.Text = ''
    } catch {
        Write-WizardError "Switch-Page error: $($_.Exception.Message)`n$($_.ScriptStackTrace)"
        throw
    }
}

function Append-Log {
    param([string]$Line)
    if ($logBox.IsDisposed -or $form.IsDisposed -or -not $form.IsHandleCreated) { return }
    try {
        $action = [Action]{ if (-not $logBox.IsDisposed) { $logBox.AppendText("$Line`r`n") } }
        if ($logBox.InvokeRequired) {
            $logBox.Invoke($action)
        } else {
            $action.Invoke()
        }
    } catch {
        Write-WizardError "Append-Log error: $($_.Exception.Message)"
    }
}

# C# helper that can be attached as a real DataReceivedEventHandler. Windows
# PowerShell 5.1 cannot attach a scriptblock directly, so the handler writes
# each line to a shared file that the UI timer tails.
$teeSource = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

public class ProcessOutputTee : IDisposable {
    private StreamWriter outWriter;
    private StreamWriter errWriter;
    private readonly object l = new object();

    public ProcessOutputTee(string outFile, string errFile) {
        outWriter = new StreamWriter(
            new FileStream(outFile, FileMode.Create, FileAccess.Write, FileShare.ReadWrite),
            Encoding.Default) { AutoFlush = true };
        errWriter = new StreamWriter(
            new FileStream(errFile, FileMode.Create, FileAccess.Write, FileShare.ReadWrite),
            Encoding.Default) { AutoFlush = true };
    }

    public void OnOutput(object sender, DataReceivedEventArgs e) {
        if (e.Data != null) { lock (l) { outWriter.WriteLine(e.Data); } }
    }
    public void OnError(object sender, DataReceivedEventArgs e) {
        if (e.Data != null) { lock (l) { errWriter.WriteLine(e.Data); } }
    }

    public void Close() {
        if (outWriter != null) { outWriter.Close(); }
        if (errWriter != null) { errWriter.Close(); }
    }
    public void Dispose() { Close(); }
}
'@
Add-Type -TypeDefinition $teeSource -ReferencedAssemblies 'System.dll'

function Start-LoggedProcess {
    param(
        [Parameter(Mandatory)]
        $Step
    )

    $progress.Visible = $true
    $lblProgress.Visible = $true
    $btnNext.Enabled = $false
    $btnBack.Enabled = $false
    $btnCancel.Enabled = $false
    Append-Log "=== Starting: $($Step.Name) ==="
    Append-Log $Step.LogHint

    $script:StepStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $script:StepEstimateSeconds = switch ($Step.Name) {
        'Clone'   { 60 }
        'Setup'   { 300 }
        'Build'   { 600 }
        'Package' { 120 }
        default   { 60 }
    }
    $progress.Value = 0
    $eta = [TimeSpan]::FromSeconds($script:StepEstimateSeconds)
    $lblProgress.Text = ("{0}: 0% | Elapsed: 00:00:00 | ETA: {1:hh\:mm\:ss}" -f $Step.Name, $eta)

    $outFile = "C:\Temp\radiobot-wizard-$($Step.Name)-out.log"
    $errFile = "C:\Temp\radiobot-wizard-$($Step.Name)-err.log"
    Remove-Item $outFile -ErrorAction SilentlyContinue
    Remove-Item $errFile -ErrorAction SilentlyContinue

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Step.FileName
    $psi.Arguments = $Step.Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $tee = New-Object ProcessOutputTee -ArgumentList $outFile, $errFile
    $outMethod = $tee.GetType().GetMethod('OnOutput')
    $errMethod = $tee.GetType().GetMethod('OnError')
    $outHandler = [System.Delegate]::CreateDelegate([System.Diagnostics.DataReceivedEventHandler], $tee, $outMethod)
    $errHandler = [System.Delegate]::CreateDelegate([System.Diagnostics.DataReceivedEventHandler], $tee, $errMethod)

    $p = [System.Diagnostics.Process]::Start($psi)
    $p.add_OutputDataReceived($outHandler)
    $p.add_ErrorDataReceived($errHandler)
    $p.BeginOutputReadLine()
    $p.BeginErrorReadLine()

    $script:RunningProcess       = $p
    $script:CurrentTee           = $tee
    $script:CurrentOutFile       = $outFile
    $script:CurrentErrFile       = $errFile
    $script:CurrentOutReader     = $null
    $script:CurrentErrReader     = $null
    $script:CurrentExitReadCount = 0
    $script:CurrentStepName      = $Step.Name
}

function Show-FinishPage {
    try {
        Switch-Page 4
        $clbBinaries.Items.Clear()
        $binaries = Get-BuiltBinaries -RepoDir $script:RepoDir
        foreach ($b in $binaries) { [void]$clbBinaries.Items.Add($b, $false) }
        $installer = Get-InstallerPath -RepoDir $script:RepoDir
        if ($installer) {
            Append-Log "Installer ready: $installer"
        }
    } catch {
        Write-WizardError "Show-FinishPage error: $($_.Exception.Message)`n$($_.ScriptStackTrace)"
        throw
    }
}

function Resolve-RepoPage {
    try {
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

            $cloneArgs = @('clone', '--depth', '1', '--branch', $branch, $url, $script:RepoDir)
            $cloneStep = @{
                Name         = 'Clone'
                FileName     = 'git.exe'
                Arguments    = $cloneArgs -join ' '
                ArgumentList = $cloneArgs
                LogHint      = "Cloning $url (branch $branch) into $script:RepoDir..."
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
    } catch {
        Write-WizardError "Resolve-RepoPage error: $($_.Exception.Message)`n$($_.ScriptStackTrace)"
        [System.Windows.Forms.MessageBox]::Show("Repository page error: $($_.Exception.Message)", 'Error', 'OK', 'Error') | Out-Null
        return $false
    }
}

$btnNext.Add_Click({
    try {
        if ($script:CurrentStep -eq 0) {
            if (-not (Resolve-RepoPage)) { return }
            Switch-Page 1
        } elseif ($script:CurrentStep -in 1,2,3) {
            $step = $script:StepCommands[$script:CurrentStep - 1]
            Start-LoggedProcess $step
        }
    } catch {
        Write-WizardError "Next button error: $($_.Exception.Message)`n$($_.ScriptStackTrace)"
        [System.Windows.Forms.MessageBox]::Show("Next step error: $($_.Exception.Message)", 'Error', 'OK', 'Error') | Out-Null
    }
})

$btnBack.Add_Click({
    try {
        if ($script:CurrentStep -gt 0 -and $script:CurrentStep -lt 4) {
            Switch-Page ($script:CurrentStep - 1)
        }
    } catch {
        Write-WizardError "Back button error: $($_.Exception.Message)`n$($_.ScriptStackTrace)"
    }
})

$btnCancel.Add_Click({
    try {
        if ($script:RunningProcess -and -not $script:RunningProcess.HasExited) {
            $script:RunningProcess.Kill()
        }
    } catch {
        Write-WizardError "Cancel/Kill error: $($_.Exception.Message)"
    }
    $form.Close()
})

$form.Add_FormClosing({
    try {
        if ($script:RunningProcess -and -not $script:RunningProcess.HasExited) {
            $script:RunningProcess.Kill()
        }
    } catch {
        Write-WizardError "FormClosing/Kill error: $($_.Exception.Message)"
    }
})

if (-not [string]::IsNullOrWhiteSpace($script:RepoDir)) {
    $txtRepoDir.Text = $script:RepoDir
    if (Test-Path "$script:RepoDir\vcpkg.json") { $rbLocal.Checked = $true }
}

try {
    $form.ShowDialog() | Out-Null
} catch {
    Write-WizardError "ShowDialog error: $($_.Exception.Message)`n$($_.ScriptStackTrace)"
    [System.Windows.Forms.MessageBox]::Show("Wizard error: $($_.Exception.Message)", 'Error', 'OK', 'Error') | Out-Null
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
