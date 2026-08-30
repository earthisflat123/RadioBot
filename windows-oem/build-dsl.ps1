#Requires -Version 5.1

<#
.SYNOPSIS
    Clones the Drift Standard Library (DSL) and builds ibdsl.lib.

.DESCRIPTION
    This script clones DSL from GitHub, mirrors its source tree into
    C:\DSL-Build, overlays a custom CMakeLists.txt that consumes the vcpkg
    packages, and builds the static ibdsl.lib required by RadioBot.
#>

$ErrorActionPreference = "Stop"

$DepsDir = "C:\deps"
$VcpkgRoot = "C:\vcpkg\installed\x86-windows"
$DslRepo = "https://github.com/DriftSolutions/DSL.git"
$DslSrc = "C:\DSL"
$DslBuild = "C:\DSL-Build"
$CMakeListsSrc = "C:\OEM\CMakeLists.dsl.txt"

Write-Host "Staging vcpkg outputs to C:\deps..."
if (Test-Path $VcpkgRoot) {
    & C:\Windows\System32\robocopy.exe "$VcpkgRoot\include" "$DepsDir\include" /E /MT:4 /R:3 /W:5 /NDL /NFL
    & C:\Windows\System32\robocopy.exe "$VcpkgRoot\lib"    "$DepsDir\lib"    /E /MT:4 /R:3 /W:5 /NDL /NFL
    & C:\Windows\System32\robocopy.exe "$VcpkgRoot\bin"    "$DepsDir\bin"    /E /MT:4 /R:3 /W:5 /NDL /NFL
}

Write-Host "Cloning DSL source..."
if (-not (Test-Path "$DslSrc\.git")) {
    # C:\DSL's parent is the drive root, which already exists and cannot be
    # created with New-Item. Create the target directory directly instead.
    New-Item -ItemType Directory -Force -Path $DslSrc | Out-Null
    & "C:\Program Files\Git\bin\git.exe" clone $DslRepo $DslSrc
}

Write-Host "Mirroring DSL source to C:\DSL-Build..."
if (Test-Path $DslBuild) { Remove-Item -Recurse -Force $DslBuild }
New-Item -ItemType Directory -Force -Path $DslBuild | Out-Null
& C:\Windows\System32\robocopy.exe $DslSrc $DslBuild /E /MT:4 /R:3 /W:5 /NDL /NFL

Write-Host "Copying custom CMakeLists..."
if (-not (Test-Path $CMakeListsSrc)) {
    throw "CMakeLists.dsl.txt not found at $CMakeListsSrc"
}
Copy-Item $CMakeListsSrc "$DslBuild\CMakeLists.txt" -Force

# Make DSL headers available to RadioBot builds
$DriftDst = "$DepsDir\drift\drift"
New-Item -ItemType Directory -Force -Path $DriftDst | Out-Null
& C:\Windows\System32\robocopy.exe "$DslSrc\drift" $DriftDst /E /MT:4 /R:3 /W:5 /NDL /NFL

Write-Host "Configuring DSL..."
& "C:\Program Files\CMake\bin\cmake.exe" -G "Visual Studio 17 2022" -A Win32 -S $DslBuild -B "$DslBuild\build" -DCMAKE_BUILD_TYPE=Release
if ($LASTEXITCODE -ne 0) { throw "DSL cmake configure failed" }

Write-Host "Building DSL..."
& "C:\Program Files\CMake\bin\cmake.exe" --build "$DslBuild\build" --config Release --target ibdsl
if ($LASTEXITCODE -ne 0) { throw "DSL build failed" }

$BuiltLib = "$DslBuild\build\lib\Release\ibdsl.lib"
if (-not (Test-Path $BuiltLib)) {
    $BuiltLib = "$DslBuild\build\lib\ibdsl.lib"
}
if (-not (Test-Path $BuiltLib)) {
    throw "Could not find built ibdsl.lib"
}

Copy-Item $BuiltLib "$DepsDir\lib\ibdsl.lib" -Force
Write-Host "DSL built and installed to $DepsDir\lib\ibdsl.lib"
