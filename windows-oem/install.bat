@echo off
echo Starting RadioBot Windows build environment setup...
powershell -ExecutionPolicy Bypass -NoProfile -File "C:\OEM\setup.ps1"
set LASTERR=%ERRORLEVEL%
if %LASTERR% NEQ 0 (
    echo.
    echo Setup failed. Check Z:\setup-radiobot.log for details.
    echo Press any key to close this window...
    pause >nul
    exit /b %LASTERR%
)
echo.
echo Setup completed. Check Z:\setup-radiobot.log for details.
echo Press any key to close this window...
pause >nul
