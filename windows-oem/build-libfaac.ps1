# Build libfaac (old 1.x API) from the knik0/faac tag faac-1.50.
# Creates C:\deps\lib\libfaac.lib and copies public headers to C:\deps\include.
$ErrorActionPreference = "Stop"

$SrcRoot = "C:\RadioBot\deps-src\faac"
$BuildDir = "$SrcRoot\libfaac\build"
$FaacTag = "faac-1.50"
$env:Path = "C:\Program Files\Git\bin;$env:Path"

if (-not (Test-Path "$SrcRoot\include\faac.h")) {
    New-Item -ItemType Directory -Force -Path (Split-Path $SrcRoot) | Out-Null
    & git clone --depth 1 --branch $FaacTag https://github.com/knik0/faac "$SrcRoot"
}

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

$VcVars = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"

# FAAC expects a config.h. Provide the values meson would generate.
@'
#define HAVE_CONFIG_H
#define PACKAGE "faac"
#define PACKAGE_VERSION "1.50"
#define MAX_CHANNELS 8
#define FAAC_PRECISION_DOUBLE 1
'@ | Set-Content -Path "$SrcRoot\libfaac\config.h" -Encoding ASCII -NoNewline

# Compile all C files. Define the same MSVC flags meson uses.
$Sources = Get-ChildItem "$SrcRoot\libfaac" -Filter *.c |
    Where-Object { $_.Name -ne 'quantize_sse.c' } |
    ForEach-Object { $_.FullName }

$SourceList = $Sources -join ' '
$ClCmd = "cl /nologo /TC /O2 /MD /W3 /D_CRT_SECURE_NO_WARNINGS /DHAVE_CONFIG_H /DWIN32 /DNDEBUG /D_WINDOWS /I`"$SrcRoot\libfaac`" /I`"$SrcRoot\include`" /c $SourceList"
$LibCmd = "lib /nologo /OUT:C:\deps\lib\libfaac.lib *.obj"

$Batch = @"
@call "$VcVars" x86
if %errorlevel% neq 0 exit /b %errorlevel%
cd /d "$BuildDir"
$ClCmd
if %errorlevel% neq 0 exit /b %errorlevel%
$LibCmd
if %errorlevel% neq 0 exit /b %errorlevel%
copy /Y "$SrcRoot\include\faac.h" C:\deps\include\
copy /Y "$SrcRoot\include\faaccfg.h" C:\deps\include\
"@

$BatchFile = "C:\OEM\build-libfaac-run.bat"
Set-Content -Path $BatchFile -Value $Batch -Encoding ASCII
& cmd /c "$BatchFile"
