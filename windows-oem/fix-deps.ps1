$ErrorActionPreference = "Stop"
$DepsDir = "C:\deps"
$DepsLib = "$DepsDir\lib"

if (-not (Test-Path $DepsLib)) {
    throw "$DepsLib does not exist"
}

# If ibdsl.lib got removed by an earlier /MIR staging, put it back.
$BuiltLib = "C:\DSL-Build\build\lib\Release\ibdsl.lib"
if ((Test-Path $BuiltLib) -and -not (Test-Path "$DepsLib\ibdsl.lib")) {
    Copy-Item $BuiltLib "$DepsLib\ibdsl.lib" -Force
}

# DSL static lib produced by build-dsl.ps1 is ibdsl.lib.
# Drift Standard Libraries' win32.h auto-links module names based on
# which ENABLE_* macros the consumer defines. Since ibdsl is a single
# static library containing the core and all modules, create copies with
# the names the linker will request.
$Ibdsl = "$DepsLib\ibdsl.lib"
if (Test-Path $Ibdsl) {
    $DslNames = @(
        "dsl-core-static.lib",
        "dsl-mysql-static.lib",
        "dsl-openssl-static.lib",
        "dsl-sqlite-static.lib",
        "dsl-curl-static.lib",
        "dsl-physfs-static.lib",
        "dsl-gnutls-static.lib",
        "dsl-sodium-static.lib",
        "dsl-libevent-static.lib"
    )
    foreach ($name in $DslNames) {
        Copy-Item $Ibdsl "$DepsLib\$name" -Force
    }
}

# win32.h uses legacy 32-bit names for OpenSSL and some 3rd-party libs.
$Aliases = @(
    @("libssl.lib",      "libssl32.lib"),
    @("libcrypto.lib",   "libcrypto32.lib"),
    @("libmysql.lib",    "libmariadb.lib"),
    @("z.lib",           "zlib-static.lib"),
    @("sqlite3.lib",     "sqlite3-static.lib"),
    @("FLAC.lib",        "libFLAC.lib"),
    @("sndfile.lib",     "libsndfile-1.lib"),
    @("sndfile.lib",     "libsndfile.lib"),
    @("vorbis.lib",      "libvorbis.lib"),
    @("vorbisfile.lib",  "libvorbisfile.lib"),
    @("vorbisenc.lib",   "libvorbisenc.lib"),
    @("mpg123.lib",      "libmpg123.lib"),
    @("tag.lib",         "taglib.lib"),
    @("ogg.lib",         "libogg.lib"),
    @("soxr.lib",        "libsoxr.lib"),
    @("muparser.lib",    "muparser32.lib"),
    @("lua.lib",         "lua53.lib")
)
foreach ($pair in $Aliases) {
    $src = $pair[0]
    $dst = $pair[1]
    if ((Test-Path "$DepsLib\$src") -and -not (Test-Path "$DepsLib\$dst")) {
        Copy-Item "$DepsLib\$src" "$DepsLib\$dst" -Force
    }
}

# Make sure any vcpkg libs that were installed after build-dsl.ps1 ran
# are also present under C:\deps. We use /E (not /MIR) so the aliases
# and ibdsl.lib that were just created are not purged.
$VcpkgLib = "C:\vcpkg\installed\x86-windows\lib"
if (Test-Path $VcpkgLib) {
    & C:\Windows\System32\robocopy.exe $VcpkgLib $DepsLib /E /MT:4 /R:3 /W:5 /NDL /NFL
}

# Some RadioBot source files use #include <pcre/pcre.h> while vcpkg
# installs pcre.h at the top level. Make a pcre/ subdir copy.
$PcreSrc = "C:\vcpkg\installed\x86-windows\include"
$PcreDst = "$DepsDir\include\pcre"
if (Test-Path "$PcreSrc\pcre.h") {
    New-Item -ItemType Directory -Force -Path $PcreDst | Out-Null
    Get-ChildItem "$PcreSrc" -Filter pcre* | ForEach-Object {
        Copy-Item $_.FullName "$PcreDst\$($_.Name)" -Force
    }
}

Write-Host "Dependency aliases and copies created under $DepsLib"
