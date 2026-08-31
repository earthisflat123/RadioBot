@echo off
echo Starting RadioBot Windows build environment setup...
powershell -ExecutionPolicy Bypass -NoProfile -File "C:\OEM\setup.ps1"
set LASTERR=%ERRORLEVEL%
if %LASTERR% NEQ 0 (
    echo.
    echo Setup failed. Check the log with:
    echo   ssh -p 2222 builder@localhost powershell -Command "Get-Content -Wait C:\Temp\setup-radiobot.log"
    echo Press any key to close this window...
    pause >nul
    exit /b %LASTERR%
)
echo.
echo Setup completed. Check the log with:
echo   ssh -p 2222 builder@localhost powershell -Command "Get-Content -Wait C:\Temp\setup-radiobot.log"
echo Press any key to close this window...
pause >nul
