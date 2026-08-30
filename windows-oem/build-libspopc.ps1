# Build libspopc 0.15 as a DLL with OpenSSL support.
# Creates C:\deps\lib\libspopc.lib, C:\deps\bin\libspopc.dll,
# and C:\deps\include\libspopc.h.
$ErrorActionPreference = "Stop"

$SrcDir = "C:\libspopc-src\libspopc-0.15"
$DepsDir = "C:\deps"
$VcpkgRoot = "C:\vcpkg\installed\x86-windows"

$Tarball = "C:\libspopc-src\libspopc-0.15.tar.gz"
$SrcRoot = "C:\libspopc-src"

if (-not (Test-Path $Tarball)) {
    New-Item -ItemType Directory -Force -Path $SrcRoot | Out-Null
    Invoke-WebRequest -Uri "http://brouits.free.fr/libspopc/releases/libspopc-0.15.tar.gz" -OutFile $Tarball
}

# Start fresh so patches are idempotent.
if (Test-Path $SrcDir) {
    Remove-Item $SrcDir -Recurse -Force
}
& tar -xzf $Tarball -C $SrcRoot

# Patch the public header and source files for MSVC.
# 1. libspopc.h: make <sys/types.h> conditional and add ssize_t typedef for Windows.
$Header = "$SrcDir\libspopc.h"
(Get-Content $Header -Raw) -replace '#include <sys/types\.h>', @'
#ifdef _WIN32
#include <winsock.h>
#include <BaseTsd.h>
typedef SSIZE_T ssize_t;
#else
#include <sys/types.h>
#endif
'@ | Set-Content $Header -Encoding ASCII -NoNewline

# 2. Remove unconditional <sys/types.h> includes in .c files and condition sys/time.h.
foreach ($c in (Get-ChildItem $SrcDir -Filter '*.c')) {
    $text = Get-Content $c.FullName -Raw
    $text = $text -replace '\r?\n#include <sys/types\.h>\r?\n', "`n"
    $text = $text -replace '#include <sys/time\.h>', "#ifndef _WIN32`n#include <sys/time.h>`n#endif"
    Set-Content $c.FullName $text -Encoding ASCII -NoNewline
}

# 3. Fix the WSAStartup error path in session.c which treats pop3sock_t as a value
#    when it is a pointer in SSL mode.
$SessionC = "$SrcDir\session.c"
$text = Get-Content $SessionC -Raw
$pattern = 'memset\(&sock, 0, sizeof\(sock\)\);\s*sock\.sock = -1;\s*return sock;'
if ($text -match $pattern) {
    $text = $text -replace $pattern, 'return BAD_SOCK;'
    Set-Content $SessionC $text -Encoding ASCII -NoNewline
}

# 4. Use OpenSSL API names available in OpenSSL 3.x
$text = (Get-Content $SessionC -Raw) -replace 'SSLv23_client_method\(\)', 'TLS_client_method()'
Set-Content $SessionC $text -Encoding ASCII -NoNewline

$VcVars = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"

$Includes = "/I`"$SrcDir`" /I`"$VcpkgRoot\include`" /I`"$DepsDir\include`""
$Defines = "/DUSE_SSL /DBUILDING_DLL /DWIN32 /D_WIN32 /D_CRT_SECURE_NO_WARNINGS /D_CRT_NONSTDC_NO_DEPRECATE /D_CRT_NONSTDC_NO_WARNINGS"

$Sources = (Get-ChildItem $SrcDir -Filter '*.c' | ForEach-Object { '"' + $_.FullName + '"' }) -join ' '

$ClCmd = "cl /nologo /TC /O2 /MD /W3 $Defines $Includes /c $Sources"
$LinkCmd = "link /nologo /DLL /OUT:$DepsDir\bin\libspopc.dll /IMPLIB:$DepsDir\lib\libspopc.lib *.obj libssl.lib libcrypto.lib ws2_32.lib crypt32.lib advapi32.lib /LIBPATH:`"$VcpkgRoot\lib`" /LIBPATH:`"$DepsDir\lib`""

$Batch = @"
@call "$VcVars" x86
if %errorlevel% neq 0 exit /b %errorlevel%
cd /d "$SrcDir"
$ClCmd
if %errorlevel% neq 0 exit /b %errorlevel%
$LinkCmd
if %errorlevel% neq 0 exit /b %errorlevel%
copy /Y libspopc.h "$DepsDir\include\libspopc.h"
"@

$BatchFile = "$SrcRoot\build-libspopc-run.bat"
Set-Content -Path $BatchFile -Value $Batch -Encoding ASCII
& cmd /c "$BatchFile"
if ($LASTEXITCODE -ne 0) { throw "libspopc build failed" }

Write-Host "libspopc built at $DepsDir\lib\libspopc.lib, $DepsDir\bin\libspopc.dll"
