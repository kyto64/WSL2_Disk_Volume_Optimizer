@echo off
setlocal enabledelayedexpansion

REM Set working directory to the directory where this batch file is located
cd /d "%~dp0"

REM =====================================================
REM WSL2 Disk Volume Optimizer - Batch Execution File
REM =====================================================

echo.
echo ========================================
echo WSL2 Disk Volume Optimizer
echo ========================================
echo Current directory: %CD%
echo.

REM Administrator privilege check
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] This script requires administrator privileges.
    echo.
    echo Please follow these steps:
    echo 1. Open Command Prompt or PowerShell as "Run as administrator"
    echo 2. Navigate to this folder
    echo 3. Run this batch file
    echo.
    pause
    exit /b 1
)

REM Script file existence check
if not exist "Optimize-WSL2Disk.ps1" (
    echo [ERROR] Optimize-WSL2Disk.ps1 not found.
    echo Please place it in the same folder as this batch file.
    pause
    exit /b 1
)

echo.
echo Running WSL2 VHD compression...
echo.
powershell -ExecutionPolicy Bypass -File "Optimize-WSL2Disk.ps1"

echo.
if %errorLevel% equ 0 (
    echo ========================================
    echo Process completed successfully!
    echo ========================================
    echo.
    echo You can restart WSL and check the results.
    echo Example command: wsl -d Ubuntu -- df -h
) else (
    echo ========================================
    echo An error occurred during processing
    echo ========================================
    echo.
    echo Please check the logs to resolve the issue.
)

echo.
pause

exit /b %errorLevel%