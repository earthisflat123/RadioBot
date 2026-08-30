cd %1
echo src: %2
echo dest1: %3
IF NOT ()==(%4) echo dest2: %4

rem Create destination directories when doing a clean build so the
rem post-build copy does not fail with "The system cannot find the path specified."
set destdir=%~dp3
IF NOT EXIST "%destdir%" mkdir "%destdir%"
IF NOT ()==(%4) (
    set destdir2=%~dp4
    IF NOT EXIST "%destdir2%" mkdir "%destdir2%"
)

add_checksum.exe %2
copy /y %2 %3
IF %ERRORLEVEL% NEQ 0 EXIT %ERRORLEVEL%
IF NOT ()==(%4) copy /y %2 %4
IF NOT ()==(%4) IF %ERRORLEVEL% NEQ 0 EXIT %ERRORLEVEL%
