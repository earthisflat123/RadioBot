#Requires -Version 5.1

<#
.SYNOPSIS
    Builds RadioBot (Win32 Release) in the Windows VM.

.DESCRIPTION
    This script is designed to run inside the dockur/windows VM. It stages
    dependencies, generates protobuf files, prunes optional projects that
    cannot build with the vcpkg environment, builds the solution with MSBuild,
    and copies the final v5\Output tree to the host shared drive (Z:\artifacts).

    Helper files are expected in $OEM (the mounted windows-oem/ folder):
        - IRCBot.sln.orig          pristine copy of IRCBot\IRCBot.sln
        - Directory.Build.props    global build properties
        - sln-prune.ps1            removes projects from a .sln
        - fix-deps.ps1             creates lib name aliases and copies vcpkg libs
        - build-dsl.ps1            builds the Drift Standard Library (DSL)
#>

param(
    [string]$RepoDir = "C:\RadioBot",
    [string]$OEM = "C:\OEM"
)

$ErrorActionPreference = "Stop"

$env:Path = "C:\Program Files\Git\bin;$env:Path"

$Log = "$OEM\build-radio.log"
$Sln = "$RepoDir\IRCBot\IRCBot.sln"
$SlnDir = "$RepoDir\IRCBot"
$VcpkgRoot = "C:\vcpkg\installed\x86-windows"
$DepsDir = "C:\deps"

Start-Transcript -Path $Log -Force

try {
    # 1. Global build props.
    Copy-Item "$OEM\Directory.Build.props" "$RepoDir\Directory.Build.props" -Force

    # 2. Make compiler/linker find headers, libs, and add_checksum.exe.
    $env:INCLUDE = "$DepsDir\drift;$VcpkgRoot\include;$VcpkgRoot\include\opus;$VcpkgRoot\include\ogg;$DepsDir\include;$env:INCLUDE"
    $env:LIB = "$DepsDir\lib;$VcpkgRoot\lib;$env:LIB"
    $env:PATH = "$RepoDir;$env:PATH"

    # 3. DSL static library. It is built once during VM setup, but if it is
    #    missing (for example a clean incremental build), build it now.
    if (-not (Test-Path "$DepsDir\lib\ibdsl.lib")) {
        if (Test-Path "$OEM\build-dsl.ps1") {
            & $OEM\build-dsl.ps1
        } else {
            throw "DSL (ibdsl.lib) is not built and $OEM\build-dsl.ps1 is missing"
        }
    }

    # 4. Start from a pristine solution and remove projects that cannot build
    #    in this vcpkg environment.
    if (-not (Test-Path "$OEM\IRCBot.sln.orig")) {
        throw "Pristine solution not found at $OEM\IRCBot.sln.orig"
    }
    Copy-Item "$OEM\IRCBot.sln.orig" $Sln -Force

    $RemoveProjects = @(
        # 'Client3', 'Client5', 'MusicScanner' are now enabled below
        'add_checksum',      # built by itself before the parallel solution
        'ibViralSound',      # missing .vcxproj
        # 'Mumble' is kept now; protobuf generated below
        # 'MeshCore' is kept now; driftmeshcore is cloned and mosquitto is in vcpkg
        # 'Twitter' is kept now; libjson source is in-tree
        # 'SMS' is kept now; libspopc is built from source
        # 'RadioBot_Shell' is kept now; Titus_Buffer is provided in shell.h
        # 'adj_enc_opus' builds in Release without FAAC (only Debug config links libfaac_d.lib)
        # 'adj_enc_aac' is kept now; libfaac is built from source
        'adj_enc_aacplus'    # intentionally skipped: libaacplus wraps the 3GPP
                             # reference AAC+ encoder and has restrictive licensing.
                             # The official Windows installer also omits this plugin.
    )
    & $OEM\sln-prune.ps1 -Projects $RemoveProjects

    # Report total build units to the wizard. The solution has been pruned; the
    # add_checksum and ConfigWizard projects are built separately.
    $BuildProgressTotal = (Get-Content $Sln | Select-String '^Project\(').Count + 2
    Write-Output "__PROGRESS_TOTAL__ $BuildProgressTotal"

    # 5. Generate the .pb.cc/.pb.h files expected by AutoDJ, Mumble, and the main exes.
    $Protoc = "$VcpkgRoot\..\x64-windows\tools\protobuf\protoc.exe"
    if (Test-Path $Protoc) {
        & $Protoc -I "$RepoDir\Common" --cpp_out="$RepoDir\Common" "$RepoDir\Common\autodj.proto"
        & $Protoc -I "$RepoDir\Common" --cpp_out="$RepoDir\Common" "$RepoDir\Common\remote_protobuf.proto"
        $MumbleDir = "$RepoDir\v5\Plugins\Mumble"
        if (Test-Path "$MumbleDir\Mumble.proto") {
            New-Item -ItemType Directory -Force -Path "$MumbleDir\proto_win32" | Out-Null
            & $Protoc -I "$MumbleDir" --cpp_out="$MumbleDir\proto_win32" "$MumbleDir\Mumble.proto"
        }
        $Client5Dir = "$RepoDir\Client5"
        if (Test-Path "$Client5Dir\client5_savefile.proto") {
            & $Protoc -I "$Client5Dir" --cpp_out="$Client5Dir" "$Client5Dir\client5_savefile.proto"
        }
    }

    # 5b. Ensure the driftmeshcore submodule used by MeshCore is present.
    $MeshCoreDir = "$RepoDir\v5\Plugins\MeshCore"
    if (-not (Test-Path "$MeshCoreDir\driftmeshcore\libmeshcoremqttclient\meshcoremqttclient.h")) {
        & git clone --depth 1 https://github.com/DriftSolutions/meshcore "$MeshCoreDir\driftmeshcore"
    }

    # 5c. Build libfaac from source for the AAC encoder. It needs no vcpkg package.
    if (-not (Test-Path "C:\deps\lib\libfaac.lib")) {
        & $OEM\build-libfaac.ps1
    }

    # 5d. Build libspopc from source for the SMS plugin.
    if (-not (Test-Path "C:\deps\lib\libspopc.lib")) {
        & $OEM\build-libspopc.ps1
    }

    # 6. Create dependency name aliases (DSL module names, legacy 32-bit lib names).
    & $OEM\fix-deps.ps1

    # 7. Map the host shared drive to Z: if it is not already available.
    #    The build still succeeds if mapping fails; artifacts are copied locally
    #    in that case.
    $FallbackArtifacts = "$RepoDir\artifacts"
    if (-not (Test-Path "Z:\")) {
        try {
            & cmd /c "net use Z: \\host.lan\Data /y" 2>&1 | Out-Null
        } catch {
            Write-Warning "Could not map Z: drive: $_"
        }
    }

    # 8. Locate MSBuild.
    $VsWhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
    $MsBuild = & $VsWhere -latest -products * -requires Microsoft.Component.MSBuild -find MSBuild\Current\Bin\MSBuild.exe | Select-Object -First 1
    if (-not $MsBuild) { throw "MSBuild not found" }

    # 9. Pre-create the output tree so every post-build copy has a valid target.
    #    This is especially important after a clean build where v5\Output may not
    #    yet exist.
    $OutputDir = "$RepoDir\v5\Output"
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    New-Item -ItemType Directory -Force -Path "$OutputDir\plugins" | Out-Null

    # 10. Build add_checksum and inc_build first. They are used by post-build
    #    events, so building them serialised before the parallel solution avoids
    #    file-in-use/copy failures. Explicitly copy the tools to the repo root
    #    so move_and_sign.bat and custom build steps can find them even if the
    #    project post-build copy was skipped by an up-to-date build.
    & $MsBuild "$RepoDir\add_checksum\add_checksum.vcxproj" /p:Configuration=Release /p:Platform=Win32 /v:minimal
    if ($LASTEXITCODE -ne 0) { throw "add_checksum build failed" }
    Copy-Item "$RepoDir\add_checksum\Release\add_checksum.exe" "$RepoDir\add_checksum.exe" -Force -ErrorAction SilentlyContinue

    & $MsBuild "$RepoDir\inc_build\inc_build.vcxproj" /p:Configuration=Release /p:Platform=Win32 /v:minimal
    if ($LASTEXITCODE -ne 0) { throw "inc_build build failed" }
    Copy-Item "$RepoDir\inc_build\Release\inc_build.exe" "$RepoDir\inc_build.exe" -Force -ErrorAction SilentlyContinue

    # Bump build.h once here, then neuter the per-project CustomBuildStep that
    # would otherwise race when the solution is built with /m (two projects
    # try to read build.ini / write build.h at the same time).
    & "$RepoDir\inc_build.exe" "$RepoDir\v5\src\build.ini" "$RepoDir\v5\src\build.h"

    $ns = @{ ms = 'http://schemas.microsoft.com/developer/msbuild/2003' }
    foreach ($projFile in @("$RepoDir\v5\IRCBot5\IRCBot5.vcxproj", "$RepoDir\v5\IRCBot5_Standalone\IRCBot5_Standalone.vcxproj")) {
        if (Test-Path $projFile) {
            [xml]$vcx = Get-Content $projFile
            $cmdNode = (Select-Xml -Xml $vcx -Namespace $ns -XPath '//ms:CustomBuildStep/ms:Command[contains(text(),"inc_build.exe")]' | Select-Object -First 1).Node
            if ($cmdNode -and $cmdNode.InnerText -notmatch 'exit 0') {
                $cmdNode.InnerText = 'cmd /c exit 0'
                $vcx.Save($projFile)
            }
        }
    }

    # 10. Build the full solution in parallel.
    & $MsBuild $Sln /p:Configuration=Release /p:Platform=Win32 /m /v:minimal
    if ($LASTEXITCODE -ne 0) { throw "RadioBot build failed" }

    # 10b. Build the ConfigWizard setup GUI. It is not in the main solution but
    #      uses the same output and signing process, so build it with the
    #      solution directory set to IRCBot\.
    & $MsBuild "$RepoDir\ConfigWizard\ConfigWizard.vcxproj" /p:Configuration=Release /p:Platform=Win32 /p:SolutionDir=$SlnDir\ /v:minimal
    if ($LASTEXITCODE -ne 0) { throw "ConfigWizard build failed" }

    # 11. Stage runtime DLLs and bundled tools next to the binaries so the output is usable.
    $OutputDir = "$RepoDir\v5\Output"
    if (Test-Path $OutputDir) {
        $binSrc = if (Test-Path "$DepsDir\bin") { "$DepsDir\bin" } else { "$VcpkgRoot\bin" }
        if (Test-Path $binSrc) {
            & C:\Windows\System32\robocopy.exe $binSrc $OutputDir *.dll /NDL /NFL /MT:4 /R:3 /W:5
        }

        # The mp3lame frontend (lame.exe) is installed as a vcpkg tool. Copy it
        # into the output so the packaged installer can include it.
        $lamePath = Get-ChildItem -Path "$VcpkgRoot" -Filter 'lame.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($lamePath) {
            Copy-Item $lamePath.FullName "$OutputDir\lame.exe" -Force -ErrorAction SilentlyContinue
            Write-Host "Copied lame.exe to output from $($lamePath.FullName)"
        } else {
            Write-Warning "lame.exe not found in vcpkg installation; the packaged installer will not include it."
        }
    }

    # 12. Copy the final output tree to the host shared drive (or a local
    #     fallback if the shared drive is not reachable).
    $ArtifactDir = if (Test-Path "Z:") { "Z:\artifacts" } else { $FallbackArtifacts }
    New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null
    if (Test-Path $OutputDir) {
        & C:\Windows\System32\robocopy.exe $OutputDir $ArtifactDir /E /NDL /NFL /MT:4 /R:3 /W:5
    }

    Write-Output "__PROGRESS_DONE__"
    Write-Host "Build complete. Artifacts are in $ArtifactDir"
} finally {
    Stop-Transcript
}
