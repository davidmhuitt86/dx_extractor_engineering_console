@echo off
setlocal
set "REPO_ROOT=%~dp0"
if "%REPO_ROOT:~-1%"=="\" set "REPO_ROOT=%REPO_ROOT:~0,-1%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPO_ROOT%\tools\dx-engineering-console.ps1" -RepositoryRoot "%REPO_ROOT%"
if errorlevel 1 (
    echo.
    echo DX-Extractor Engineering Console failed to start.
    pause
)
endlocal
